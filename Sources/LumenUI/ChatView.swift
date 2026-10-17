import AppKit
import LumenCore
import SwiftUI
import UniformTypeIdentifiers

/// Чат (`pages/chat-page.tsx`): шапка, переписка, поле ввода — размеры из макета.
/// Чего нет, потому что ещё не работает: «+», голос, песочница и правая панель контекста.
struct ChatView: View {
    @Bindable var app: AppModel
    /// Разговор рядом (разделённый экран) — со своим контроллером; nil — главный
    var controller: ChatController?

    @Environment(\.palette) private var p
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var dropping = false

    private var chat: ChatController { controller ?? app.chat }
    private var isSplit: Bool { controller != nil }
    private var backend: Backend { chat.conversation?.backend ?? app.prefs.backend }
    private var agent: Bool { chat.conversation.map { $0.kind == .agent } ?? (app.tab == .agent) }
    private var folder: URL? { chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder }
    /// Открыт постоянный разговор бота
    private var bot: Bot? { chat.conversation?.kind == .bot ? app.bot(chat.conversation?.botID) : nil }
    private var group: BotGroup? { chat.conversation?.kind == .group ? app.group(chat.conversation?.groupID) : nil }

    var body: some View {
        HStack(spacing: 0) {
            content
            if app.prefs.contextOpen && !isSplit {
                Group {
                    if let group { GroupPanel(app: app, group: group) } else if let bot { BotPassport(app: app, bot: bot) } else { ContextPanel(app: app) }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.prefs.contextOpen)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if chat.messages.isEmpty && !chat.busy {
                // как в Claude: на пустом экране приветствие и поле ввода — по центру; в разговоре поле внизу
                Group {
                    if agent { AgentHome(app: app, draft: $draft, attachments: $attachments, backend: backend) } else { startScreen }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
                // план — закреплён над полем, как в Claude: виден, пока идёт работа или есть несделанное
                if let c = chat.conversation, c.kind != .chat, !c.plan.isEmpty,
                   chat.busy || app.claudeBusy(c.id) || c.plan.contains(where: { $0.state != .done }) {
                    PlanCard(items: c.plan)
                        .frame(maxWidth: Composer.width)
                        .padding(.horizontal, 20).padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                }
                Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: agent, controller: controller)
            }
        }
        .foregroundStyle(p.foreground)
        // файлы и картинки можно бросить в любое место разговора, не только в поле
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            app.attach(providers) { attachments.append($0) }
            return true
        }
        .overlay {
            if dropping {
                ZStack {
                    p.background.opacity(0.7)
                    VStack(spacing: 10) {
                        Icon("paperclip", 28).foregroundStyle(p.glow)
                        Text("Отпусти — прикреплю").tw(16, .medium, lh: 22)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(12))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropping)
        // тянут разговор из списка — правая половина: «откроется рядом»
        .overlay(alignment: .trailing) {
            if app.draggingChat != nil, !isSplit, app.split == nil {
                SplitDropZone(app: app).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.draggingChat)
    }

    /// h-14 border-b px-5 gap-3: знак 28 со сферой 18, заголовок text-sm medium, подпись text-xs
    private var header: some View {
        HStack(spacing: 12) {
            if let group {
                GroupAvatars(bots: app.groupMembers(group), size: 24)
            } else if let bot {
                BotAvatar(bot: bot, size: 28)
            } else if agent {
                Icon("folder", 16).foregroundStyle(p.glow)
                    .frame(width: 28, height: 28)
                    .background(p.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: R.lg))
            } else {
                Orb(state: app.orb, size: 18).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let group {
                    Text(group.name).tw(14, .medium, lh: 20).lineLimit(1)
                    Text("Группа · " + app.groupMembers(group).map { "@\($0.id)" }.joined(separator: ", "))
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                } else if let bot {
                    Text(bot.name).tw(14, .medium, lh: 20).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("@\(bot.id)").foregroundStyle(BotColor.accent(bot.hue))
                        Text("·").foregroundStyle(p.foreground.opacity(0.2))
                        Text(bot.role)
                    }
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                } else if let c = chat.conversation {
                    RenamableTitle(app: app, conversation: c)
                } else {
                    Text(agent ? "Новая задача" : "Новый чат").tw(14, .medium, lh: 20).lineLimit(1)
                }
                if bot != nil || group != nil {
                } else if agent {
                    HStack(spacing: 6) {
                        Text(folder.map { AppModel.isHome($0) ? "Агент во всех моих файлах" : "Агент в папке \($0.lastPathComponent)" } ?? "Агент во всех моих файлах")
                        Text("·").foregroundStyle(p.foreground.opacity(0.2))
                        Icon("laptop", 12)
                        Text("на этом Маке" + (backend == .api ? ", по ключу API" : ""))
                    }
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                } else {
                    Text("Чат — просто разговор, Lumen ничего не трогает" + (backend == .api ? " · через API" : ""))
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                }
            }
            Spacer()
            if isSplit {
                IconButton(icon: "x", help: chat.busy ? "Закроется, когда ответ закончится" : "Закрыть разговор рядом") { app.closeSplit() }
                    .disabled(chat.busy)
            }
            if let bot { IconButton(icon: "pencil", help: "Изменить бота") { app.page = .botEditor(bot.id) } }
            if let group { IconButton(icon: "pencil", help: "Изменить группу") { app.page = .groupEditor(group.id) } }
            if !isSplit {
                IconButton(icon: "globe", help: "Браузер сбоку (⇧⌘B): агенты работают в нём, ты входишь в аккаунты", active: app.browserOpen) {
                    app.toggleBrowser()
                }
                IconButton(icon: "panel-right", help: bot == nil ? "Контекст: память, окно, расход" : "Паспорт бота: что может и что отрезано",
                           active: app.prefs.contextOpen) {
                    app.update { $0.contextOpen.toggle() }
                }
            }
        }
        .padding(.horizontal, 20)
        // панель спрятана — слева кнопки окна и «показать панель»
        .padding(.leading, app.prefs.sidebarHidden ? 150 : 0)
        .frame(height: 56)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    /// Пустой экран как в Claude: крупное приветствие, под ним сразу поле ввода, ниже — подсказки
    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            greeting
                .padding(.bottom, 28)
            Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: false)
            startChips
                .padding(.top, 4)
                .frame(maxWidth: Composer.width)
            Spacer(minLength: 24)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var greeting: some View {
        if let group {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    GroupAvatars(bots: app.groupMembers(group), size: 40)
                    Text(group.name).font(.system(size: 38, weight: .regular, design: .serif)).lineLimit(1)
                }
                Text("Пиши всем — ответят по очереди. «@id …» — ответит только он.")
                    .tw(13, lh: 18).foregroundStyle(p.mutedFg)
            }
        } else if let bot {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    BotAvatar(bot: bot, size: 44)
                    Text(bot.name).font(.system(size: 38, weight: .regular, design: .serif)).lineLimit(1)
                }
                if !bot.role.isEmpty { Text(bot.role).tw(13, lh: 18).foregroundStyle(p.mutedFg) }
            }
        } else {
            HStack(spacing: 16) {
                Orb(state: app.orb, size: 44)
                Text(app.profile.name.isEmpty ? "Привет" : "Привет, \(app.profile.name)")
                    .font(.system(size: 40, weight: .regular, design: .serif)).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var startChips: some View {
        if let group {
            let first = app.groupMembers(group).first?.id ?? "бот"
            StartChips(items: ["Обсудите, с чего начать", "Каждый — по одной идее", "@\(first) начни"],
                       icons: ["users", "lightbulb", "at-sign"], tint: p.glow) { draft = $0 }
        } else if let bot {
            if !bot.starters.isEmpty {
                StartChips(items: bot.starters, icons: [bot.icon], tint: BotColor.accent(bot.hue)) { draft = $0 }
            }
        } else {
            StartChips(items: app.suggestions, icons: ["lightbulb", "pen-line", "sparkles", "message-circle"], tint: p.glow) { draft = $0 }
                .animation(.easeOut(duration: 0.3), value: app.suggestions)
                .task { app.refreshSuggestionsIfNeeded() }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            transcriptScroll(proxy)
        }
        // свой список на каждый разговор: ленивый список не путает строки при смене вкладки
        .id(chat.conversation?.id ?? "new")
    }

    private func transcriptScroll(_ proxy: ScrollViewProxy) -> some View {
        Group {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { m in
                        MessageRow(message: m, chat: chat, isLast: m.id == chat.messages.last?.id).id(m.id)
                            // новый вопрос отделён от прошлого ответа, а ответ стоит близко к вопросу
                            .padding(.top, m.role == .user && m.id != chat.messages.first?.id ? 18 : 0)
                    }
                    if !chat.busy, let last = chat.messages.last, let next = last.next {
                        NextStepCard(next: next) { chat.answer($0, on: last) } close: { chat.dismissNext(last) }
                    }
                    if let s = chat.streaming {
                        MessageRow(message: s, chat: chat, streaming: true)
                    }
                    // разговор сейчас идёт в приложении Claude — видно здесь (по записям сессии, а не по времени файла)
                    if !chat.busy, let c = chat.conversation, let live = app.claudeLive[c.id] {
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            switch live.active(now: ctx.date) {
                            case .working(let since, let step): LiveStepLine(text: step.map { "Claude Code: \($0)" } ?? "Идёт в Claude Code", since: since)
                            case .retrying(let since):
                                LiveStepLine(text: "Claude Code: нет связи с API — повторяет", since: since, tint: Palette.destructive)
                            case .idle: EmptyView()
                            }
                        }
                    }
                    // что агент делает прямо сейчас — пока идёт инструмент (текст после него ещё не пошёл)
                    if chat.busy, !chat.thinking, chat.pendingPermission == nil, let live = chat.liveStep,
                       (live.step.at ?? 0) >= (chat.streaming?.text.count ?? 0) {
                        LiveStepLine(text: live.step.text, since: live.since, tint: app.bot(chat.turnBot).map { BotColor.accent($0.hue) })
                    }
                    // claude долго молчит — сказать прямо, что происходит, и дать выход
                    if chat.busy, chat.pendingPermission == nil, chat.conversation?.usesCLI == true {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            if let s = chat.silence(now: ctx.date), s >= 30 {
                                HStack(spacing: 10) {
                                    Icon("clock", 14)
                                    Text("Claude Code молчит \(Int(s)) с — \(s > 90 ? "похоже, завис" : "думает или ждёт ответа API")")
                                        .tw(13, lh: 18)
                                    Button("Журнал") { app.update { $0.contextOpen = true; $0.panelHidden.removeAll { $0 == "log" } } }
                                        .buttonStyle(.plain).foregroundStyle(p.glow)
                                    Button("Стоп") { chat.stop() }.buttonStyle(.plain).foregroundStyle(p.glow)
                                }
                                .font(.geist(13))
                                .foregroundStyle(s > 90 ? Palette.destructive : p.mutedFg)
                                .padding(.leading, 36)
                            }
                        }
                    }
                    if let ask = chat.pendingPermission, ask.conversationID == chat.conversation?.id {
                        PermissionCard(chat: chat, ask: ask.request).id("permission-\(ask.request.id)")
                    } else if chat.thinking {
                        HStack(spacing: 12) {
                            if let b = app.bot(chat.turnBot) {
                                BotAvatar(bot: b, size: 22)
                                Text("\(b.name) работает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(BotColor.accent(b.hue))
                            } else {
                                Orb(state: .thinking, size: 22)
                                Text("Думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(p.foreground)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                // поля по бокам: на узком окне переписка не упирается в края
                .padding(.horizontal, 44).padding(.vertical, 32)
                .frame(maxWidth: app.prefs.chatWidth.points)
                .animation(.easeInOut(duration: 0.3), value: app.prefs.chatWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            // к концу — когда страница уже разложена (иначе после смены вкладки переписка оказывалась пустой)
            .onAppear { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            // перенесённый из Claude Code разговор: пока открыт — догоняет то, что пишется там (раз в 3 с, только если файл менялся)
            .task(id: chat.conversation?.id) {
                while !Task.isCancelled {
                    if let c = chat.conversation, c.kind == .agent {
                        await app.syncFromClaude(c, in: chat)
                        chat.claudeWentIdle(c.id)
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .onChange(of: chat.messages.count) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.conversation?.id) { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.pendingPermission?.request.id) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.scrollTarget) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .top) }
                chat.scrollTarget = nil
            }
            // оглавление: главы разговора справа сверху
            .overlay(alignment: .topTrailing) {
                if chat.messages.contains(where: \.chapter) { ChaptersButton(chat: chat).padding(16) }
            }
        }
    }
}

/// Подсказки пустого чата: rounded-full border bg-card/50 px-3.5 py-1.5 text-sm, в несколько строк по центру
struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        // в макете flex-wrap justify-center: при узком окне переносятся
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(spacing: 8) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { i in Chip(text: i) { pick(i) } }
    }

    private struct Chip: View {
        let text: String
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                Text(text).tw(14, lh: 20)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(hover ? p.card : p.card.opacity(0.5), in: Capsule())
                    .overlay(Capsule().strokeBorder(hover ? p.glow.opacity(0.4) : p.border))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

enum Plural {
    /// «1 факт», «3 факта», «15 фактов»
    static func facts(_ n: Int) -> String { "\(n) " + form(n, "факт", "факта", "фактов") }
    static func links(_ n: Int) -> String { "\(n) " + form(n, "связь", "связи", "связей") }
    static func bots(_ n: Int) -> String { "\(n) " + form(n, "бот", "бота", "ботов") }

    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}

/// Одно сообщение: своё — пузырём справа (`UserMsg`), ответ Lumen — со сферой слева (`LumenMsg`)
struct MessageRow: View {
    let message: ChatMessage
    var chat: ChatController?
    var streaming = false
    /// Последнее сообщение — действия видны всегда, у остальных — при наведении
    var isLast = false

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var editing = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.chapter { ChapterMark(title: ChapterMark.title(message)) }
            content
        }
        .onHover { hover = $0 }
    }

    /// Действия под сообщением: как в Claude
    private var showActions: Bool { chat != nil && !streaming && message.note == nil && (hover || isLast || editing) }

    @ViewBuilder private var content: some View {
        if let note = message.note {
            HStack(spacing: 8) {
                Icon("rotate-ccw", 14)
                Text(note)
            }
            .font(.geist(12)).foregroundStyle(p.mutedFg)
            .frame(maxWidth: .infinity)
        } else if message.role == .user {
            VStack(alignment: .trailing, spacing: 8) {
            if !message.attachments.isEmpty {
                MessageAttachments(items: message.attachments).frame(maxWidth: .infinity, alignment: .trailing)
            }
            if editing {
                editor
            } else if !message.text.isEmpty {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(message.text)
                    .tw(14, lh: 22.75)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(p.secondary, in: UnevenRoundedRectangle(topLeadingRadius: R.xxl, bottomLeadingRadius: R.xxl,
                                                                        bottomTrailingRadius: R.md, topTrailingRadius: R.xxl))
                    // 80% колонки переписки, а не окна: иначе на широком окне пузырь вылезает к правому краю
                    .frame(maxWidth: bubbleMax, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            if let via = message.via, !via.isClaudeCode { ViaChip(via: via, app: chat?.app) }
            if !editing, let chat {
                MessageActions(message: message, chat: chat, user: true) { editText = message.text; editing = true }
                    .opacity(showActions ? 1 : 0)
            }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                if let b = chat?.app.bot(message.botID) {
                    BotAvatar(bot: b, size: 22).padding(.top, 2)
                } else {
                    Orb(state: streaming ? .writing : .idle, size: 22, animated: streaming).padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 12) {
                    // ответ бота в чужом чате — подписан, чтобы было видно, кто отвечал
                    if let b = chat?.app.bot(message.botID), chat?.conversation?.kind != .bot {
                        Text("@\(b.id) · \(b.name)").tw(12, .medium, lh: 16).foregroundStyle(BotColor.accent(b.hue))
                    }
                    // как в Claude Code: абзац — шаги — абзац; блок «что дальше» пока пишется — не показывать сырым
                    let pieces = AnswerPiece.layout(text: NextStep.split(message.text).text, steps: message.steps)
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                        let last = i == pieces.count - 1
                        switch piece {
                        case .text(let t): RichText(text: t, caret: streaming && last)
                        case .steps(let s): StepsView(steps: s)
                        }
                    }
                    // снимки страниц и файлы, которые агент показал в чате
                    if !message.attachments.isEmpty { AttachmentThumbs(items: message.attachments, app: chat?.app) }
                    if let changes = message.changes, let chat {
                        ChangeCard(message: message, changes: changes, chat: chat)
                    }
                    if let d = message.skillDraft, let chat {
                        SkillProposalCard(app: chat.app, message: message, draft: d)
                    }
                    if let chat {
                        ForEach(message.proposals) { pr in ProposalCard(app: chat.app, message: message, proposal: pr) }
                    }
                    if let chat {
                        ForEach(message.remembered, id: \.self) { id in RememberedCard(app: chat.app, id: id) }
                        if !message.recalled.isEmpty && !streaming {
                            RecalledLine(app: chat.app, ids: message.recalled)
                        }
                    }
                    if message.stopped {
                        IconLabel(text: "Остановлено", icon: "circle-stop", size: 14).font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    if let error = message.error {
                        IconLabel(text: error, icon: "triangle-alert", size: 16)
                            .font(.geist(14)).foregroundStyle(Palette.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chat, !streaming {
                            HStack(spacing: 8) {
                                LButton(title: "Повторить", icon: "rotate-ccw", kind: .outline, small: true) { chat.retry(message) }
                                    .disabled(chat.busy)
                                LButton(title: "Журнал", icon: "file-text", kind: .ghost, small: true) {
                                    NSWorkspace.shared.open(chat.app.logFile)
                                }
                                .disabled(!FileManager.default.fileExists(atPath: chat.app.logFile.path))
                            }
                        }
                    }
                    if let chat, message.error == nil {
                        MessageActions(message: message, chat: chat, user: false) {}
                            .opacity(showActions ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension MessageRow {
    /// Самый широкий пузырь человека — 80% колонки переписки
    var bubbleMax: CGFloat { CGFloat((chat?.app.prefs.chatWidth.points ?? 704) * 0.8) }

    var editor: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(14))
                .lineLimit(1...14)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(p.secondary, in: RoundedRectangle(cornerRadius: R.xxl))
                .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(0.35)))
                .onSubmit(sendEdit)
            HStack(spacing: 8) {
                Text("Ответ ниже заменится — Lumen забудет, что было после").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                LButton(title: "Отмена", kind: .ghost, small: true) { editing = false }
                LButton(title: "Отправить", kind: .primary, small: true, action: sendEdit)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat?.busy == true)
            }
        }
        .frame(maxWidth: bubbleMax, alignment: .trailing)
    }

    private func sendEdit() {
        let t = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let chat, !chat.busy else { return }
        editing = false
        chat.resend(from: message, text: t)
    }
}

/// Строка действий: у своего — время, «Попробовать снова», «Изменить», «Копировать», «Глава»;
/// у ответа — «Копировать», «Попробовать снова», «Глава», время
struct MessageActions: View {
    let message: ChatMessage
    let chat: ChatController
    let user: Bool
    let edit: () -> Void

    @Environment(\.palette) private var p
    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            if user {
                time.padding(.trailing, 6)
                act("refresh-cw", "Попробовать снова — ответ ниже заменится") { chat.resend(from: message, text: message.text) }
                    .disabled(chat.busy)
                act("pencil", "Изменить", action: edit).disabled(chat.busy)
                copy
                chapter
            } else {
                copy
                act("refresh-cw", "Попробовать снова") { chat.retry(message) }.disabled(chat.busy)
                chapter
                time.padding(.leading, 6)
            }
        }
        .animation(.easeOut(duration: 0.12), value: copied)
    }

    private var time: some View {
        Text(Self.when(message.createdAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.8))
            .help(message.createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute()))
    }

    private var copy: some View {
        act(copied ? "check" : "copy", copied ? "Скопировано" : "Копировать") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NextStep.split(message.text).text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        }
    }

    private var chapter: some View {
        act("bookmark", message.chapter ? "Убрать главу" : "Закрепить главу — появится в оглавлении разговора", on: message.chapter) {
            chat.toggleChapter(message)
        }
    }

    private func act(_ icon: String, _ help: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        ActionIcon(icon: icon, on: on, action: action).help(help)
    }

    /// «сейчас», «14:32», «вчера, 14:32», «12 окт, 14:32»
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if Date().timeIntervalSince(d) < 60 { return "сейчас" }
        let hm = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return hm }
        if cal.isDateInYesterday(d) { return "вчера, " + hm }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return f.string(from: d).replacingOccurrences(of: ".", with: "") + ", " + hm
    }
}

private struct ActionIcon: View {
    let icon: String
    var on = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(icon, 15)
                .foregroundStyle(on ? p.glow : hover && enabled ? p.foreground : p.mutedFg)
                .frame(width: 28, height: 28)
                .background(hover && enabled ? p.foreground.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// Метка над сообщением-главой
struct ChapterMark: View {
    let title: String
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(p.border).frame(height: 1).frame(maxWidth: 40)
            IconLabel(text: title, icon: "bookmark", size: 12).tw(12, .medium, lh: 16).foregroundStyle(p.glow).lineLimit(1)
            Rectangle().fill(p.border).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Название главы — первая строка сообщения, коротко
    static func title(_ m: ChatMessage) -> String {
        let line = NextStep.split(m.text).text.split(separator: "\n").first.map(String.init) ?? "Глава"
        let clean = line.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        return clean.count > 60 ? String(clean.prefix(58)) + "…" : (clean.isEmpty ? "Глава" : clean)
    }
}

/// Оглавление разговора: главы по порядку, щелчок — прокрутить к ней
struct ChaptersButton: View {
    let chat: ChatController
    @Environment(\.palette) private var p
    @State private var open = false

    var body: some View {
        let chapters = chat.messages.filter(\.chapter)
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Icon("list", 13)
                Text("Главы · \(chapters.count)").font(.geist(12, .medium))
            }
            .foregroundStyle(p.foreground.opacity(0.85))
            .padding(.horizontal, 10).frame(height: 28)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(p.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Главы").tw(11, .medium, lh: 14).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.bottom, 4)
                ForEach(Array(chapters.enumerated()), id: \.element.id) { i, m in
                    Button {
                        chat.scrollTarget = m.id
                        open = false
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.geist(12, .medium)).foregroundStyle(p.glow).frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ChapterMark.title(m)).tw(13, lh: 18).lineLimit(1)
                                Text(MessageActions.when(m.createdAt)).tw(11, lh: 14).foregroundStyle(p.mutedFg)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(width: 300)
        }
    }
}

/// Текст ответа: text-[0.9375rem] leading-[1.65], абзацы через 12; разметка (жирный, курсив, `код`, ссылки) и блоки кода ```
struct RichText: View {
    let text: String
    /// Пока ответ печатается — в конце мигает светящийся курсор (`.caret` в макете)
    var caret = false

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let parts = Self.parts(text)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                switch part {
                case .prose(let s) where caret && i == parts.count - 1:
                    // мигает раз в полсекунды, как steps(2) за 1 с
                    TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                        let on = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                        (Text(Self.markdown(s)) + Text(" ▍").foregroundColor(on ? p.glow : .clear))
                            .tw(15, lh: 24.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .prose(let s):
                    Text(Self.markdown(s)).tw(15, lh: 24.75).textSelection(.enabled)
                        .tint(p.glow)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let s):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(s).font(.system(size: 12.5, design: .monospaced)).lineSpacing(3).textSelection(.enabled).padding(14)
                    }
                    .background(p.card, in: RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                }
            }
        }
    }

    enum Part: Equatable { case prose(String), code(String) }

    static func parts(_ text: String) -> [Part] {
        var out: [Part] = []
        for (i, chunk) in text.components(separatedBy: "```").enumerated() {
            if i % 2 == 1 {
                // первая строка блока — язык, её не показываем
                var lines = chunk.components(separatedBy: "\n")
                if let first = lines.first, !first.contains(" ") { lines.removeFirst() }
                let code = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                if !code.isEmpty { out.append(.code(code)) }
            } else {
                // абзацы — отдельными блоками, как <p> в макете
                for para in chunk.components(separatedBy: "\n\n") {
                    let s = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(.prose(s)) }
                }
            }
        }
        return out
    }

    /// Разобранные куски: во время стрима текст меняется 30 раз в секунду, а готовые абзацы — нет
    @MainActor private static var parsed: [String: AttributedString] = [:]

    @MainActor static func markdown(_ s: String) -> AttributedString {
        if let hit = parsed[s] { return hit }
        let out = parseMarkdown(s)
        if parsed.count > 400 { parsed.removeAll() }
        parsed[s] = out
        return out
    }

    private static func parseMarkdown(_ s: String) -> AttributedString {
        // заголовки «## …» и «**…**» в начале строки — жирным, списки оставляем как есть
        let cleaned = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let l = String(line)
            if let r = l.range(of: #"^#{1,6}\s+"#, options: .regularExpression) { return "**" + l[r.upperBound...] + "**" }
            return l
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// Поле ввода (`Composer`): px-5 pt-1 pb-5, сверху плавный переход в фон; поле rounded-2xl border bg-card/60 p-3
struct Composer: View {
    @Bindable var app: AppModel
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let backend: Backend
    /// Ширина поля — своя, не зависит от «Ширины переписки» (Рома, 16.10)
    static let width: CGFloat = 640
    var agent = false
    /// Большое поле по центру экрана новой задачи (вариант A): выше, крупнее текст, папка — кнопкой
    var big = false
    /// Поле разговора рядом (разделённый экран)
    var controller: ChatController?

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    @State private var modelOpen = false
    @State private var effortOpen = false
    @State private var folderOpen = false
    @State private var modeOpen = false

    private var chat: ChatController { controller ?? app.chat }
    private var model: ChatModel { chat.conversation?.model ?? (agent ? app.defaultAgentModel : app.prefs.model) }
    private var effort: Effort { chat.conversation?.effort ?? (agent ? app.prefs.agentEffort ?? .high : app.prefs.effort) }
    /// Начатый разговор продолжается тем же движком: Claude не продолжит ход ChatGPT и наоборот
    private var models: [ChatModel] {
        let all = app.availableModels(for: backend)
        guard chat.conversation != nil else { return all }
        return all.filter { $0.isGPT == model.isGPT }
    }
    /// Агенту без папки отправлять нечего
    private var ready: Bool { !agent || chat.conversation != nil || app.agentFolder != nil }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    /// Набирают «@…» в начале — какие боты подходят (в разговоре самого бота не нужно)
    private var mentionHits: [Bot] {
        guard chat.conversation?.kind != .bot, draft.hasPrefix("@"), !draft.contains(" "), !draft.contains("\n") else { return [] }
        let q = draft.dropFirst().lowercased()
        // в группе — только её участники
        let pool = chat.conversation?.kind == .group ? (app.group(chat.conversation?.groupID).map(app.groupMembers) ?? []) : app.bots
        return pool.filter { q.isEmpty || $0.id.hasPrefix(q) || $0.name.lowercased().contains(q) }
    }
    private var inBot: Bool { chat.conversation?.kind == .bot }
    private var currentBot: Bot? { inBot ? app.bot(chat.conversation?.botID) : nil }
    @State private var botFolderOpen = false
    @State private var botEffortOpen = false

    /// Кому пишешь: знак и @имя в цвете бота
    private func botChip(_ b: Bot) -> some View {
        HStack(spacing: 6) {
            BotAvatar(bot: b, size: 18)
            Text("@\(b.id)").font(.geist(12, .medium)).foregroundStyle(BotColor.accent(b.hue))
        }
        .padding(.leading, 4).padding(.trailing, 8).frame(height: 26)
        .background(BotColor.faint(b.hue), in: Capsule())
        .overlay(Capsule().strokeBorder(BotColor.soft(b.hue)))
        .help(b.role)
    }

    /// Папка бота — меняется прямо здесь (как у агента), сразу для его следующего ответа
    private func botFolderPicker(_ b: Bot) -> some View {
        let current = b.folder.map { URL(fileURLWithPath: $0) }
        return PickerButton(open: $botFolderOpen) {
            Icon("folder", 14).foregroundStyle(BotColor.accent(b.hue))
            Text(current.map(AppModel.folderName) ?? "Своя папка").font(.geist(12))
        } panel: {
            PopoverPanel(title: "Где работает бот", width: 256) {
                PopoverOption(name: "Своя папка", note: "пустая, чужих файлов не видит", active: current == nil) {
                    Icon("folder", 16).foregroundStyle(p.mutedFg)
                } action: { setBotFolder(b, nil) }
                PopoverOption(name: "Мои файлы", note: "вся домашняя папка, ~", active: current.map(AppModel.isHome) ?? false) {
                    Icon("laptop", 16).foregroundStyle(p.mutedFg)
                } action: { setBotFolder(b, AppModel.home.path) }
                ForEach(app.recentFolders.filter { !AppModel.isHome($0) }, id: \.self) { f in
                    PopoverOption(name: f.lastPathComponent, note: f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                  active: f.standardizedFileURL.path == current?.standardizedFileURL.path) {
                        Icon("folder", 16).foregroundStyle(p.mutedFg)
                    } action: { setBotFolder(b, f.path) }
                }
                Button {
                    botFolderOpen = false
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Выбрать"
                    if panel.runModal() == .OK, let url = panel.url { setBotFolder(b, url.path) }
                } label: {
                    Text("Другая папка…").font(.geist(12)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(chat.busy)
    }

    private func botEffortPicker(_ b: Bot) -> some View {
        PickerButton(open: $botEffortOpen) {
            Text(b.effort.name).font(.geist(12)).foregroundStyle(p.mutedFg)
        } panel: {
            PopoverPanel(title: "Сколько думать") {
                ForEach(Effort.allCases) { e in
                    PopoverOption(name: e.name, note: e.note, active: e == b.effort) { EmptyView() } action: {
                        var nb = b
                        nb.effort = e
                        app.saveBot(nb)
                        chat.refresh(app.botConversation(for: nb))
                        botEffortOpen = false
                    }
                }
            }
        }
        .disabled(chat.busy)
    }

    private func setBotFolder(_ b: Bot, _ path: String?) {
        var nb = b
        nb.folder = path
        app.saveBot(nb)
        if let path { app.rememberFolder(URL(fileURLWithPath: path)) }
        chat.refresh(app.botConversation(for: nb))
        botFolderOpen = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mentionHits.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(mentionHits) { b in
                        Button { draft = "@\(b.id) " } label: {
                            HStack(spacing: 10) {
                                BotAvatar(bot: b, size: 22)
                                Text("@\(b.id)").font(.geist(13, .medium)).foregroundStyle(BotColor.accent(b.hue))
                                Text(b.role).font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            }
            if !chat.openQueue.isEmpty { queueList }
            if !attachments.isEmpty { AttachmentStrip(items: $attachments) }
            TextField(big ? "Опиши задачу: что сделать, починить или проверить" : (agent ? "Что сделать в проекте?" : (currentBot.map { "Задача для «\($0.name)»" } ?? (chat.conversation?.kind == .group ? "Написать группе · @id — ответит один" : "Просто напиши"))),
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(big ? 15 : 14))
                .lineSpacing(big ? 6 : 3)
                .lineLimit(big ? 4...14 : 2...12)
                .focused($focused)
                .onSubmit(send)
                .frame(minHeight: big ? 96 : 48, alignment: .topLeading)
            HStack(spacing: 2) {
                // как в Claude: «+» в левом нижнем углу — картинки и файлы
                PlusMenu(app: app, agent: agent, canPickFolder: agent && chat.conversation == nil, draft: $draft, attachments: $attachments)
                if agent { folderPicker; modePicker }
                if let b = currentBot { botChip(b); botFolderPicker(b); botEffortPicker(b) }
                ElsewherePill(app: app)
                Spacer()
                // у бота модель задана в его паспорте
                if !inBot {
                    modelPicker
                    effortPicker
                }
                sendButton.padding(.leading, 4)
            }
            .frame(height: big ? 32 : 28)
        }
        .padding(big ? 16 : 12)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.xxl))
        // без свечения в фокусе (Рома, 16.10): ровная рамка
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(
            currentBot.map { focused ? BotColor.accent($0.hue).opacity(0.45) : BotColor.soft($0.hue) } ?? (focused ? p.foreground.opacity(0.14) : p.border)))
        .background {
            // у бота — его цвет: лёгкое свечение за полем
            if let b = currentBot {
                RoundedRectangle(cornerRadius: R.xxl).fill(BotColor.faint(b.hue)).blur(radius: 18).padding(-6).allowsHitTesting(false)
            }
        }
        .onPasteCommand(of: [.fileURL, .png, .tiff, .jpeg]) { providers in app.attach(providers) { attachments.append($0) } }
        .frame(maxWidth: big ? .infinity : Self.width)
        .padding(.horizontal, big ? 0 : 20).padding(.bottom, big ? 0 : 20).padding(.top, big ? 0 : 4)
        .frame(maxWidth: .infinity)
        // from-background to-transparent над полем
        .background(alignment: .top) {
            LinearGradient(colors: [p.background.opacity(0), p.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 40).offset(y: -40).allowsHitTesting(false)
        }
        .onAppear { focused = true }
        // щелчок по участнику группы справа — «@id » в начало поля
        .onChange(of: chat.mentionRequest) { _, m in
            guard let m else { return }
            if !draft.hasPrefix(m) { draft = m + draft }
            focused = true
            chat.mentionRequest = nil
        }
    }

    private var inGroup: Bool { chat.conversation?.kind == .group }

    /// Очередь: что уйдёт после ответа — «Сейчас» (остановить ответ и отправить это) или убрать
    private var queueList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.claudeBusy(chat.conversation?.id) && !chat.busy ? "В очереди — уйдёт, когда Claude Code закончит" : "В очереди — уйдёт после ответа")
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            ForEach(chat.openQueue) { q in
                HStack(spacing: 8) {
                    Icon("clock", 14).foregroundStyle(p.mutedFg)
                    Text(q.text.isEmpty ? (q.attachments.first?.name ?? "Вложение") : q.text)
                        .tw(13, lh: 18).lineLimit(1)
                    if !q.attachments.isEmpty, !q.text.isEmpty {
                        Icon("paperclip", 12).foregroundStyle(p.mutedFg)
                    }
                    Spacer(minLength: 8)
                    Button { chat.sendNow(q.id) } label: { Text("Сейчас").tw(12, .medium, lh: 16).foregroundStyle(p.glow) }
                        .buttonStyle(.plain).help("Остановить ответ и отправить это")
                    Button { chat.unqueue(q.id) } label: { Icon("x", 12).foregroundStyle(p.mutedFg) }
                        .buttonStyle(.plain).help("Убрать из очереди")
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(p.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: R.md))
            }
        }
        .padding(.bottom, 4)
    }

    private func send() {
        // идёт ответ — сообщение встаёт в очередь (в группе — сразу в комнату)
        guard canSend, ready else { return }
        chat.send(draft, attachments: attachments)
        draft = ""
        attachments = []
    }

    /// `FolderPicker`: папка проекта; у начатой сессии папка уже не меняется
    private var folderPicker: some View {
        let current = chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder
        return PickerButton(open: $folderOpen, bordered: big) {
            Icon(big ? "folder-open" : "folder", big ? 16 : 14).foregroundStyle(p.glow)
            Text(current.map(AppModel.folderName) ?? "Мои файлы").font(.geist(big ? 14 : 12))
        } panel: {
            PopoverPanel(title: "Где работать", width: 256) {
                PopoverOption(name: "Мои файлы", note: "вся домашняя папка, ~", active: current.map(AppModel.isHome) ?? true) {
                    Icon("laptop", 16).foregroundStyle(p.mutedFg)
                } action: {
                    app.agentFolder = AppModel.home
                    folderOpen = false
                }
                ForEach(app.recentFolders.filter { !AppModel.isHome($0) }, id: \.self) { f in
                    PopoverOption(name: f.lastPathComponent, note: f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                  active: f.standardizedFileURL.path == current?.standardizedFileURL.path) {
                        Icon("folder", 16).foregroundStyle(p.mutedFg)
                    } action: {
                        app.agentFolder = f
                        folderOpen = false
                    }
                }
                Button {
                    folderOpen = false
                    app.chooseFolder()
                } label: {
                    Text("Другая папка…").font(.geist(12)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(chat.conversation != nil || chat.busy)
    }

    /// `ModelPicker`: Sparkles text-glow + название text-xs medium + стрелка
    private var modelPicker: some View {
        PickerButton(open: $modelOpen) {
            Text(model.name).font(.geist(12, .medium))
        } panel: {
            PopoverPanel(title: "Модель") {
                ForEach(models) { m in
                    if m == ChatModel.gpt.first, models.contains(where: { !$0.isGPT }) {
                        p.border.frame(height: 1).padding(.vertical, 5).padding(.horizontal, 2)
                    }
                    PopoverOption(name: m.name, note: m.note, active: m == model) {
                        Icon(m.isGPT ? "message-circle" : "sparkles", 16).foregroundStyle(p.mutedFg)
                    } action: {
                        chat.set(model: m)
                        modelOpen = false
                    }
                }
            }
        }
        .disabled(chat.busy)
    }

    /// Режим агента: как в Claude Code, Shift+Tab — следующий
    private var mode: AgentMode { chat.conversation?.mode ?? app.prefs.agentMode }

    private var modePicker: some View {
        PickerButton(open: $modeOpen) {
            Icon(mode.icon, 14).foregroundStyle(mode == .bypassPermissions ? Palette.destructive : p.glow)
            Text(mode.name).font(.geist(12))
        } panel: {
            PopoverPanel(title: "Режим · Shift+Tab — следующий", width: 300) {
                ForEach(app.prefs.visibleModes) { m in
                    PopoverOption(name: m.name, note: m.note, active: m == mode) {
                        Icon(m.icon, 16).foregroundStyle(m == .bypassPermissions ? Palette.destructive : p.mutedFg)
                    } action: {
                        chat.set(mode: m)
                        modeOpen = false
                    }
                }
            }
        }
        .background {
            Button("") {
                let all = app.prefs.visibleModes
                chat.set(mode: all[((all.firstIndex(of: mode) ?? -1) + 1) % all.count])
            }
            .keyboardShortcut(.tab, modifiers: .shift).opacity(0)
        }
        .help("Режим: \(mode.note)")
    }

    /// `EffortPicker`: столбики уровня + название text-xs
    private var effortPicker: some View {
        PickerButton(open: $effortOpen) {
            Text(effort.name).font(.geist(12)).foregroundStyle(p.mutedFg)
        } panel: {
            PopoverPanel(title: "Сколько думать") {
                ForEach(Effort.allCases) { e in
                    PopoverOption(name: e.name, note: e.note, active: e == effort) {
                        EmptyView()
                    } action: {
                        chat.set(effort: e)
                        effortOpen = false
                    }
                }
            }
        }
        .disabled(chat.busy)
    }

    @ViewBuilder private var sendButton: some View {
        if (chat.busy || app.claudeBusy(chat.conversation?.id)) && !inGroup && canSend {
            // ответ идёт, а в поле уже есть следующее — в очередь (↩ делает то же)
            Button(action: send) {
                HStack(spacing: 6) {
                    Icon("clock", 12)
                    Text("В очередь").font(.geist(13, .medium))
                }
                .foregroundStyle(p.onGlow)
                .padding(.horizontal, 12).frame(height: 32)
                .background(p.glow, in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(chat.busy ? "Отправится сам, когда Lumen закончит · ↩" : "Отправится сам, когда Claude Code закончит · ↩")
            .padding(.trailing, 4)
        }
        if chat.busy && !(inGroup && canSend) {
            Button { chat.stop() } label: {
                HStack(spacing: 6) {
                    Icon("square", 12)
                    Text("Стоп").font(.geist(13, .medium))
                }
                .foregroundStyle(p.foreground)
                .padding(.horizontal, 12).frame(height: 32)
                .background(p.secondary, in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .help("Остановить · ⌘.")
        } else if !(app.claudeBusy(chat.conversation?.id) && canSend) {
            Button(action: send) {
                Icon("arrow-up", 16)
                    .foregroundStyle(p.onGlow)
                    .frame(width: big ? 32 : 28, height: big ? 32 : 28)
                    // как в макете: кнопка всегда светится (bg-glow, тень 16px glow-soft)
                    .background(currentBot.map { BotColor.accent($0.hue) } ?? p.glow, in: Circle())
                    .shadow(color: currentBot.map { BotColor.soft($0.hue) } ?? p.glowSoft, radius: 8)
            }
            .buttonStyle(.plain)
            // пустое поле — нечего отправлять: кнопка тусклая и не нажимается
            .disabled(!ready || !canSend)
            .opacity(canSend ? 1 : 0.35)
            .help(!ready ? "Сначала выбери папку проекта" : (canSend ? "Отправить · ↩" : "Напиши сообщение"))
        }
    }
}

/// Кнопка-открывашка поповера: h-7 rounded-lg px-2 text-xs, стрелка вниз на 50%
struct PickerButton<Label: View, Panel: View>: View {
    @Binding var open: Bool
    /// Кнопка с рамкой (папка в большом поле новой задачи)
    var bordered = false
    @ViewBuilder let label: Label
    @ViewBuilder let panel: Panel

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                label
                Icon("chevron-down", 12).opacity(0.5)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, bordered ? 10 : 8).frame(height: bordered ? 32 : 28)
            .background(bordered ? p.background.opacity(hover ? 0.6 : 0.4) : (hover ? p.foreground.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: bordered ? R.md : R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(bordered ? p.input : .clear))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $open, arrowEdge: .top) {
            panel.environment(\.palette, p)
        }
    }
}

/// Пять столбиков, закрашены до уровня — как индикатор сигнала (`EffortBars`)
struct EffortBars: View {
    let level: Int

    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<Effort.allCases.count, id: \.self) { i in
                Capsule().fill(i <= level ? p.glow : p.foreground.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .frame(height: 14, alignment: .bottom)
    }
}

/// Название разговора в шапке: двойной щелчок — переименовать
struct RenamableTitle: View {
    @Bindable var app: AppModel
    let conversation: Conversation

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("", text: $text)
                .textFieldStyle(.plain).tw(14, .medium, lh: 20)
                .focused($focused)
                .onSubmit {
                    app.renameChat(conversation, text)
                    editing = false
                }
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, f in if !f { editing = false } }
        } else {
            Text(conversation.title).tw(14, .medium, lh: 20).lineLimit(1)
                .onTapGesture(count: 2) {
                    text = conversation.title
                    editing = true
                    focused = true
                }
                .help("Дважды щёлкни, чтобы переименовать")
        }
    }
}


/// Под сообщением в разговоре бота: откуда его позвали (щелчок — открыть тот чат)
private struct ViaChip: View {
    let via: Via
    let app: AppModel?

    @Environment(\.palette) private var p

    var body: some View {
        Button {
            if let id = via.conversationID, let c = app?.conversations.first(where: { $0.id == id }) { app?.openChat(c) }
        } label: {
            HStack(spacing: 4) {
                Icon("at-sign", 11)
                Text(via.fromBot ? "позвал \(via.title)" : "из чата «\(via.title)»").lineLimit(1)
            }
            .tw(11, lh: 14).foregroundStyle(p.mutedFg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(via.conversationID == nil)
        .help(via.conversationID == nil ? "" : "Открыть тот чат")
    }
}

/// Где ещё Lumen сейчас отвечает (писать здесь можно и так): живая точка и название, щелчок — открыть
private struct ElsewherePill: View {
    let app: AppModel

    @Environment(\.palette) private var p
    @State private var pulse = false
    @State private var hover = false

    var body: some View {
        let others = app.chat.turns.values.map(\.conversation).filter { $0.id != app.chat.conversation?.id }
            .sorted { $0.title < $1.title }
        if let first = others.first {
            Button { app.openChat(first) } label: {
                HStack(spacing: 7) {
                    Circle().fill(p.glow).frame(width: 6, height: 6)
                        .shadow(color: p.glow.opacity(pulse ? 0.9 : 0.2), radius: pulse ? 5 : 1)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                    Text(others.count == 1 ? "Ещё отвечаю: «\(first.title)»" : "Ещё отвечаю в \(others.count) разговорах")
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.geist(12)).foregroundStyle(hover ? p.foreground : p.mutedFg)
                .padding(.horizontal, 10).frame(height: 26)
                .background(p.glow.opacity(hover ? 0.12 : 0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(p.glow.opacity(0.22)))
                .frame(maxWidth: 260, alignment: .leading)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .onHover { hover = $0 }
            .help(others.map(\.title).joined(separator: "\n") + "\nЩелчок — открыть")
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }
}

/// Подсказки под полем на пустом экране: компактные пилюли в ряд по центру, со значком; при наведении — светятся
struct StartChips: View {
    let items: [String]
    var icons: [String] = ["lightbulb"]
    var tint: Color
    let pick: (String) -> Void

    @Environment(\.palette) private var p

    var body: some View {
        if items.contains(where: { $0.count > 34 }) {
            // длинные — списком под полем: весь текст виден, строки тонко разделены
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { i, text in
                    if i > 0 { p.border.frame(height: 1).padding(.horizontal, 14) }
                    Row(text: text, icon: icons[i % max(1, icons.count)], tint: tint) { pick(text) }
                }
            }
            .padding(.horizontal, 10)
        } else {
            CenterFlow(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element) { i, text in
                    Chip(text: text, icon: icons[i % max(1, icons.count)], tint: tint) { pick(text) }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private struct Row: View {
        let text: String
        let icon: String
        let tint: Color
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Icon(icon, 14).foregroundStyle(hover ? tint : p.mutedFg)
                    Text(text).font(.geist(13.5)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.72))
                    Spacer(minLength: 8)
                    Icon("arrow-up", 12).rotationEffect(.degrees(45)).foregroundStyle(tint).opacity(hover ? 1 : 0)
                }
                .padding(.horizontal, 14).frame(height: 42)
                .background(hover ? tint.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
    }

    private struct Chip: View {
        let text: String
        let icon: String
        let tint: Color
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 7) {
                    Icon(icon, 13).foregroundStyle(hover ? tint : p.mutedFg)
                    Text(text).font(.geist(13)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.75))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .frame(maxWidth: 320)
                .background(hover ? tint.opacity(0.08) : p.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(hover ? tint.opacity(0.35) : p.border))
                .contentShape(RoundedRectangle(cornerRadius: R.lg))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// Перенос по строкам с выравниванием каждой строки по центру
struct CenterFlow: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            let w = min(s.width, width)
            if x > 0 && x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, CGSize(width: w, height: s.height)))
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 640
        let rs = rows(subviews, width: width)
        let h = rs.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + spacing * CGFloat(max(0, rs.count - 1))
        return CGSize(width: width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowW = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rowH = row.map(\.1.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowW) / 2
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowH + spacing
        }
    }
}


/// Правая половина окна, пока тянут разговор: отпусти — откроется рядом
struct SplitDropZone: View {
    @Bindable var app: AppModel
    @Environment(\.palette) private var p
    @State private var over = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                p.background.opacity(over ? 0.85 : 0.6)
                VStack(spacing: 10) {
                    Icon("panel-right", 28).foregroundStyle(p.glow)
                    Text("Отпусти — откроется рядом").tw(15, .medium, lh: 20)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(over ? 0.8 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(12))
            .frame(width: g.size.width / 2)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .dropDestination(for: String.self) { items, _ in
                guard let c = app.dropped(items) else { return false }
                app.openSplit(c)
                return true
            } isTargeted: { over = $0 }
        }
    }
}
