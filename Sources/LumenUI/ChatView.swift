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
    /// Переписка у самого низа — тогда кнопка «вниз» не нужна, а при смене ширины окна держимся низа
    @State private var atBottom = true
    /// Был ли внизу, когда начала меняться ширина, и счётчик изменений ширины
    @State private var wasAtBottom: Bool?
    @State private var widthGeneration = 0

    private var chat: ChatController { controller ?? app.chat }
    private var isSplit: Bool { controller != nil }
    private var backend: Backend { chat.conversation?.backend ?? app.prefs.backend }
    private var agent: Bool { chat.conversation.map { $0.kind == .agent } ?? (app.tab == .agent) }
    private var folder: URL? { chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder }
    /// Проект разговора — в шапке видно, что чат создан именно в нём (и у начатого, и у нового)
    private var projectName: String? { app.project(chat.conversation?.projectID ?? chat.newProjectID)?.name }
    /// Открыт постоянный разговор бота
    private var bot: Bot? { chat.conversation?.kind == .bot ? app.bot(chat.conversation?.botID) : nil }
    private var group: BotGroup? { chat.conversation?.kind == .group ? app.group(chat.conversation?.groupID) : nil }

    var body: some View {
        HStack(spacing: 0) {
            // переписка меняет ширину сразу (см. RootView): анимирует только выезжающая панель
            content.transaction { $0.animation = nil }
            if app.prefs.contextOpen && !isSplit {
                Group {
                    if let group { GroupPanel(app: app, group: group) } else if let bot { BotPassport(app: app, bot: bot) } else { ContextPanel(app: app) }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.prefs.contextOpen)
    }

    /// Ширина колонки переписки: у агента — из настроек, у чата и ботов — всегда обычная, не меняется (Рома, 18.10)
    static func columnWidth(app: AppModel, conversation: Conversation?, agent: Bool = false) -> CGFloat {
        let isAgent = conversation.map { $0.kind == .agent } ?? agent
        return CGFloat(isAgent ? app.prefs.chatWidth.points : ChatWidth.normal.points)
    }

    private var columnWidth: CGFloat { Self.columnWidth(app: app, conversation: chat.conversation, agent: agent) }

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
                        if let projectName {
                            Text("Проект «\(projectName)»")
                            Text("·").foregroundStyle(p.foreground.opacity(0.2))
                        }
                        Text(folder.map { AppModel.isHome($0) ? "Агент во всех моих файлах" : "Агент в папке \($0.lastPathComponent)" } ?? "Агент во всех моих файлах")
                        Text("·").foregroundStyle(p.foreground.opacity(0.2))
                        Icon("laptop", 12)
                        Text("на этом Маке" + (backend == .api ? ", по ключу API" : ""))
                    }
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                } else {
                    Text(projectName.map { "Проект «\($0)» · чат видит контекст проекта" + (backend == .api ? " · через API" : "") }
                         ?? "Чат — просто разговор, Lumen ничего не трогает" + (backend == .api ? " · через API" : ""))
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
    }

    /// Пустой экран как в Claude: крупное приветствие, под ним сразу поле ввода, ниже — подсказки
    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            greeting
                .padding(.bottom, 28)
            Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: false)
            // подсказок для начала разговора в чате нет (Рома, 18.10)
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
                    // план — над идущим ответом, близко к нему; что агент делает сейчас — уже под планом
                    VStack(alignment: .leading, spacing: 6) {
                        // план — в самой переписке, после последнего сообщения: листается вместе с чатом и не закрывает экран
                        // план — только пока идёт ход (здесь или в приложении Claude) и в нём есть несделанное.
                        // Ход кончился — план уходит, даже если агент не отметил шаги; весь сделан — тоже уходит,
                        // и новый ход в Claude не показывает старый план, пока не составит свой (Рома, 17.10)
                        if let c = chat.conversation, c.kind != .chat, !c.plan.isEmpty,
                           chat.busy || app.claudeBusy(c.id), c.plan.contains(where: { $0.state != .done }) {
                            PlanCard(items: c.plan)
                        }
                        if let s = chat.streaming {
                            MessageRow(message: s, chat: chat, streaming: true)
                        }
                    }
                    // позванный бот работает: что делает и что пишет — прямо в чате, пока не закончит
                    if let c = chat.conversation, let w = chat.liveWork[c.id] {
                        LiveBotWork(work: w, bot: app.bot(w.bot))
                    }
                    // разговор сейчас идёт в приложении Claude — видно здесь (по записям сессии, а не по времени файла)
                    if !chat.busy, let c = chat.conversation, let live = app.claudeLive[c.id] {
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            let steps = chat.messages.last.flatMap { $0.role == .assistant && $0.via?.isClaudeCode == true ? $0.steps : nil } ?? []
                            switch live.active(now: ctx.date) {
                            case .working(let since, let step): ClaudeLiveLine(text: step ?? "Работает", since: since, steps: steps)
                            case .retrying(let since):
                                ClaudeLiveLine(text: "Нет связи с API, повторяет", since: since, steps: steps, tint: Palette.destructive)
                            case .idle: EmptyView()
                            }
                        }
                    }
                    // что агент делает прямо сейчас — пока идёт инструмент (текст после него ещё не пошёл)
                    // (если шаги уже в ответе — это его последняя группа шагов, отдельной строки не нужно)
                    if chat.busy, !chat.thinking, chat.pendingPermission == nil, let live = chat.liveStep, chat.streaming == nil,
                       (live.step.at ?? 0) >= (chat.streaming?.text.count ?? 0) {
                        LiveStepLine(text: live.step.text, since: live.since, tint: app.bot(chat.turnBot).map { BotColor.accent($0.hue) })
                    }
                    // claude долго молчит — сказать прямо, что происходит, и дать выход
                    // сбой связи: Lumen сам повторяет или ждёт сеть — видно, что не завис
                    if chat.busy, let c = chat.conversation, let note = chat.retryNote[c.id] {
                        HStack(spacing: 10) {
                            Icon("refresh-cw", 14)
                            Text(note).tw(13, lh: 18)
                            Button("Стоп") { chat.stop() }.buttonStyle(.plain).foregroundStyle(p.glow)
                        }
                        .foregroundStyle(p.mutedFg)
                        
                    }
                    if chat.busy, chat.pendingPermission == nil, chat.conversation?.usesCLI == true,
                       chat.conversation.map({ chat.retryNote[$0.id] == nil }) ?? true {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            // идёт инструмент (Bash, сборка) — тишина ожидаемая: не «молчит», а «выполняет»
                            let tool = chat.conversation.map { chat.toolRunning[$0.id] == true } ?? false
                            if let s = chat.silence(now: ctx.date), s >= (tool ? 60 : 30) {
                                // одной строкой текста: слова переносятся по ширине колонки, кнопки — следом, а не столбиком
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Icon("clock", 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                                        Text(tool ? "\(chat.liveStep?.step.text ?? "Выполняет команду") — \(Int(s)) с. Ждёт, пока команда закончится: для сборок и тестов это нормально"
                                             : "Claude Code молчит \(Int(s)) с — \(s > 90 ? "ждёт ответа API; на 3-й минуте прерву и повторю сам" : "думает или ждёт ответа API")")
                                            .tw(13, lh: 18).fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    HStack(spacing: 14) {
                                        Button("Журнал") { app.update { $0.contextOpen = true; $0.panelHidden.removeAll { $0 == "log" } } }
                                            .buttonStyle(.plain).foregroundStyle(p.glow)
                                        Button("Стоп") { chat.stop() }.buttonStyle(.plain).foregroundStyle(p.glow)
                                    }
                                    .padding(.leading, 21)
                                }
                                .font(.geist(13))
                                .foregroundStyle(s > 90 && !tool ? Palette.destructive : p.mutedFg)
                                
                            }
                        }
                    }
                    if let ask = chat.pendingPermission, ask.conversationID == chat.conversation?.id {
                        PermissionCard(chat: chat, ask: ask.request).id("permission-\(ask.request.id)")
                    } else if chat.thinking {
                        HStack(spacing: 10) {
                            if let b = app.bot(chat.turnBot) {
                                DotsSpinner(color: BotColor.accent(b.hue))
                                Text("\(b.name) работает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(BotColor.accent(b.hue))
                            } else {
                                DotsSpinner(color: p.glow)
                                Text("Думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(p.foreground)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                // поля по бокам: на узком окне переписка не упирается в края
                .padding(.horizontal, 44).padding(.vertical, 32)
                .frame(maxWidth: columnWidth)
                .animation(.easeInOut(duration: 0.3), value: app.prefs.chatWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            // к концу — когда страница уже разложена (иначе после смены вкладки переписка оказывалась пустой)
            // разговор открывается сразу внизу и держится у низа, пока высоты сообщений досчитываются
            // (раньше прокрутка «к низу» при открытии промахивалась мимо ленивого списка — экран был пустой)
            .defaultScrollAnchor(.bottom)
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
            // за ответом вниз — только если человек и так внизу; отлистал вверх читать — не дёргать
            .onChange(of: chat.messages.count) { if atBottom || chat.messages.last?.role == .user { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text.count) { if atBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
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
            // где мы в переписке: у низа ли и какое сообщение сверху
            .modifier(ScrollTracking(atBottom: $atBottom))
            // ширина поменялась (спрятали или показали панель, потянули окно) — ленивый список теряет место:
            // вернуть к низу или к тому сообщению, что было сверху
            // ширина поменялась (панель, браузер): был внизу — остаться внизу, когда ширина успокоится.
            // Середину не трогаем: прыжок к сообщению в ленивом списке оставлял экран пустым до прокрутки
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                if wasAtBottom == nil { wasAtBottom = atBottom }
                widthGeneration += 1
                let gen = widthGeneration
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard gen == widthGeneration, let bottom = wasAtBottom else { return }
                    wasAtBottom = nil
                    if bottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            // кнопка «вниз», когда отлистал вверх
            .overlay(alignment: .bottom) {
                if !atBottom && !chat.messages.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Icon("arrow-down", 16).foregroundStyle(p.foreground)
                            .frame(width: 34, height: 34)
                            .background(p.popover, in: Circle())
                            .overlay(Circle().strokeBorder(p.foreground.opacity(0.12)))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .help("Вниз, к последнему сообщению")
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
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
    /// Какой из прежних вариантов ответа показан (nil — нынешний)
    @State private var variant: Int?

    /// Ответ с выбранным вариантом вместо нынешнего
    private var shownMessage: ChatMessage {
        guard let i = variant, let alts = message.alternates, alts.indices.contains(i) else { return message }
        var m = message
        let v = alts[i]
        m.text = v.text
        m.steps = v.steps
        m.attachments = v.attachments
        m.error = v.error
        m.changes = nil
        m.next = nil
        m.createdAt = v.createdAt
        return m
    }

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
            } else if !Attachment.splitSavedNote(message.text).text.isEmpty {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                // приписка агенту с путями вложений — не для человека
                Text(Attachment.splitSavedNote(message.text).text)
                    .chatTw(14, lh: 22.75)
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
            // выбран прежний вариант ответа (‹ 1/3 ›) — показываем его
            let original = message
            let message = shownMessage
            HStack(alignment: .top, spacing: 14) {
                // без значка слева, как в Claude: ответ — просто текст; бот подписан своим именем и цветом
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
                        // последняя группа шагов идущего ответа — она же «что делает сейчас»
                        case .steps(let s):
                            if streaming && last, let chat, chat.busy, !chat.thinking, chat.pendingPermission == nil, let live = chat.liveStep {
                                StepsView(steps: s, live: (live.since, chat.app.bot(chat.turnBot).map { BotColor.accent($0.hue) }))
                            } else {
                                StepsView(steps: s)
                            }
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
                        MessageActions(message: original, chat: chat, user: false, variant: $variant) {}
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
    var bubbleMax: CGFloat { (chat.map { ChatView.columnWidth(app: $0.app, conversation: $0.conversation) } ?? 704) * 0.8 }

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
    /// Варианты ответа: какой показан (nil — нынешний, последний)
    var variant: Binding<Int?>? = nil
    let edit: () -> Void

    @Environment(\.palette) private var p
    @State private var copied = false

    init(message: ChatMessage, chat: ChatController, user: Bool, variant: Binding<Int?>? = nil, edit: @escaping () -> Void) {
        self.message = message
        self.chat = chat
        self.user = user
        self.variant = variant
        self.edit = edit
    }

    var body: some View {
        HStack(spacing: 2) {
            if user {
                time.padding(.trailing, 6)
                act("refresh-cw", "Попробовать снова — прежний ответ останется вариантом") {
                    // ответ на это сообщение есть — он станет вариантом нового, как в Claude
                    if let i = chat.messages.firstIndex(where: { $0.id == message.id }),
                       let answer = chat.messages[(i + 1)...].prefix(while: { $0.role != .user }).last(where: { $0.role == .assistant && $0.note == nil }) {
                        chat.retry(answer)
                    } else {
                        chat.resend(from: message, text: message.text)
                    }
                }
                .disabled(chat.busy)
                act("pencil", "Изменить", action: edit).disabled(chat.busy)
                copy
                chapter
            } else {
                copy
                act("refresh-cw", "Попробовать снова — этот ответ останется вариантом") { chat.retry(message) }.disabled(chat.busy)
                chapter
                variants
                time.padding(.leading, 6)
            }
        }
        .animation(.easeOut(duration: 0.12), value: copied)
    }

    /// ‹ 2/3 › — листать прежние варианты ответа
    @ViewBuilder private var variants: some View {
        if let variant, let alts = message.alternates, !alts.isEmpty {
            let total = alts.count + 1
            let current = (variant.wrappedValue ?? alts.count) + 1
            HStack(spacing: 0) {
                act("chevron-down", "Прежний вариант") {
                    let i = (variant.wrappedValue ?? alts.count) - 1
                    if i >= 0 { variant.wrappedValue = i }
                }
                .rotationEffect(.degrees(90)).disabled(current <= 1)
                Text("\(current) / \(total)").tw(12, lh: 16).foregroundStyle(p.mutedFg).monospacedDigit().padding(.horizontal, 2)
                act("chevron-down", "Следующий вариант") {
                    let i = (variant.wrappedValue ?? alts.count) + 1
                    variant.wrappedValue = i >= alts.count ? nil : i
                }
                .rotationEffect(.degrees(-90)).disabled(current >= total)
            }
            .padding(.leading, 4)
        }
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
                            .chatTw(15, lh: 24.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .prose(let s):
                    // ссылки кликаются без ⌘ и подчёркиваются под курсором (LinkText.swift)
                    LinkText(text: Self.markdown(s))
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let s, let lang):
                    CodeBlock(code: s, lang: lang)
                case .table(let rows):
                    MarkdownTable(rows: rows)
                case .visual(let code, let done):
                    VisualBlock(code: code, done: done)
                }
            }
        }
    }

    enum Part: Equatable { case prose(String), code(String, lang: String?), table([[String]]), visual(String, done: Bool) }

    /// Таблица markdown: строки «| a | b |», вторая — «|---|---|». Не таблица — nil
    static func table(_ para: String) -> [[String]]? {
        let lines = para.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("|") }),
              lines[1].replacingOccurrences(of: " ", with: "").allSatisfy({ "|-:".contains($0) }) else { return nil }
        func cells(_ l: String) -> [String] {
            var t = l
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return [cells(lines[0])] + lines.dropFirst(2).map(cells)
    }

    static func parts(_ text: String) -> [Part] {
        var out: [Part] = []
        let chunks = text.components(separatedBy: "```")
        for (i, chunk) in chunks.enumerated() {
            if i % 2 == 1 {
                // первая строка блока — язык: он подписью над кодом
                var lines = chunk.components(separatedBy: "\n")
                var lang: String?
                if let first = lines.first, !first.contains(" ") {
                    lines.removeFirst()
                    let l = first.trimmingCharacters(in: .whitespaces)
                    if !l.isEmpty { lang = l }
                }
                let code = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                // ```visual — живая картинка; пока блок не закрыт (ответ ещё пишется), рисовать нечего
                if let l = lang?.lowercased(), Visuals.langs.contains(l) {
                    out.append(.visual(code, done: i < chunks.count - 1))
                } else if !code.isEmpty {
                    out.append(.code(code, lang: lang))
                }
            } else {
                // абзацы — отдельными блоками, как <p> в макете
                for para in chunk.components(separatedBy: "\n\n") {
                    let s = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty else { continue }
                    // таблица может идти сразу под строкой текста, без пустой строки
                    let lines = s.components(separatedBy: "\n")
                    let isRow = { (l: String) in l.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
                    if let first = lines.firstIndex(where: isRow) {
                        let end = lines[first...].firstIndex(where: { !isRow($0) }) ?? lines.endIndex
                        if let rows = table(lines[first..<end].joined(separator: "\n")) {
                            let before = lines[..<first].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            let after = lines[end...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !before.isEmpty { out.append(.prose(before)) }
                            out.append(.table(rows))
                            if !after.isEmpty { out.append(.prose(after)) }
                        } else {
                            out.append(.prose(s))
                        }
                    } else {
                        out.append(.prose(s))
                    }
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
        var out = (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        detectLinks(&out)
        return out
    }

    /// Голые адреса в тексте («https://…», «www.…») — тоже ссылки. Имена файлов вроде README.md ссылками не становятся,
    /// уже размеченные ссылки и код не трогаем
    static func detectLinks(_ a: inout AttributedString) {
        let plain = String(a.characters)
        guard plain.contains("://") || plain.lowercased().contains("www."),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        for m in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = m.url, let r = Range(m.range, in: plain) else { continue }
            let raw = plain[r].lowercased()
            guard raw.contains("://") || raw.hasPrefix("www.") else { continue }
            let lo = a.characters.index(a.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = a.characters.index(lo, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            if a[lo..<hi].runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) { continue }
            a[lo..<hi].link = url
        }
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
    /// Позванный бот — чипом в его цвете в начале поля, «@id» из текста убран (как в Codex). ⌫ в пустом поле — убрать
    @State private var mentioned: Bot?
    /// Навык из «/» — тоже чипом; при отправке становится просьбой взять этот навык
    @State private var pickedSkill: Skill?
    @State private var slashIndex = 0

    /// Что предлагает «/»: действия Lumen и навыки из библиотеки Lumen (навыков Claude Code здесь нет)
    struct SlashItem: Identifiable {
        enum Kind { case action, skill }
        let id: String
        let kind: Kind
        let icon: String
        let note: String
    }

    private var slashItems: [SlashItem] {
        guard draft.hasPrefix("/"), !draft.contains(" "), !draft.contains("\n") else { return [] }
        let q = draft.dropFirst().lowercased()
        var all: [SlashItem] = []
        if !inGroup {
            all.append(SlashItem(id: agent ? "new" : "new", kind: .action, icon: "square-pen", note: agent ? "Новая задача" : "Новый чат"))
            if chat.conversation?.usesCLI == true && !chat.busy {
                all.append(SlashItem(id: "compact", kind: .action, icon: "layers", note: "Сжать разговор: пересказать старое и освободить место"))
            }
            all.append(SlashItem(id: "remember", kind: .action, icon: "brain", note: "Запомнить то, что напишешь дальше"))
            all.append(SlashItem(id: "browser", kind: .action, icon: "globe", note: app.browserOpen ? "Спрятать браузер" : "Открыть браузер сбоку"))
            all.append(SlashItem(id: "memory", kind: .action, icon: "book-text", note: "Открыть память"))
        }
        all += app.skills.map { SlashItem(id: $0.name, kind: .skill, icon: "book-open", note: $0.description) }
        return all.filter { q.isEmpty || $0.id.lowercased().hasPrefix(q) || $0.note.lowercased().contains(q) }
    }

    /// Выбрали строку «/»: действие — сразу, навык — чипом
    private func pickSlash(_ item: SlashItem) {
        draft = ""
        slashIndex = 0
        switch (item.kind, item.id) {
        case (.action, "new"): agent ? app.newAgentTask() : app.newChat()
        case (.action, "compact"): chat.compact()
        case (.action, "remember"): draft = "Запомни: "
        case (.action, "browser"): app.toggleBrowser()
        case (.action, "memory"): app.page = .memory
        case (.skill, _): pickedSkill = app.skills.first { $0.name == item.id }
        default: break
        }
        focused = true
    }

    /// «@id » в начале текста (выбрали из списка, вставили, нажали участника группы) — превратить в чип
    private func absorbMention() {
        guard !inBot, mentioned == nil, draft.hasPrefix("@"), let space = draft.firstIndex(where: { $0 == " " || $0 == "\n" }) else { return }
        let id = String(draft[draft.index(after: draft.startIndex)..<space]).lowercased()
        let pool = inGroup ? (app.group(chat.conversation?.groupID).map(app.groupMembers) ?? []) : app.bots
        guard let b = pool.first(where: { $0.id == id }) else { return }
        mentioned = b
        draft = String(draft[draft.index(after: space)...])
    }

    /// Чип в поле: значок и имя в цвете, щелчок по крестику — убрать
    private func fieldChip(_ text: String, color: Color, @ViewBuilder icon: () -> some View, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            icon()
            Text(text).font(.geist(13, .medium)).foregroundStyle(color)
            Button(action: remove) { Icon("x", 11).foregroundStyle(color.opacity(0.7)) }.buttonStyle(.plain).help("Убрать")
        }
        .padding(.leading, 4).padding(.trailing, 7).frame(height: 24)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3)))
    }

    /// Цвет поля: бот, в чьём разговоре мы, или позванный чипом
    private var tintBot: Bot? { currentBot ?? mentioned }
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
            HStack(alignment: .top, spacing: 6) {
            if let b = mentioned {
                fieldChip(b.name, color: BotColor.accent(b.hue)) { BotAvatar(bot: b, size: 16) } remove: { mentioned = nil }
                    .padding(.top, big ? 0 : -2)
            }
            if let sk = pickedSkill {
                fieldChip("/" + sk.name, color: p.glow) { Icon("book-open", 12).foregroundStyle(p.glow) } remove: { pickedSkill = nil }
                    .padding(.top, big ? 0 : -2)
            }
            TextField(mentioned.map { "Задача для «\($0.name)»" } ?? (big ? "Опиши задачу: что сделать, починить или проверить" : (agent ? "Что сделать в проекте? / — команды и навыки" : (currentBot.map { "Задача для «\($0.name)»" } ?? (chat.conversation?.kind == .group ? "Написать группе · @id — ответит один" : "Просто напиши · / — команды и навыки")))),
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(big ? 15 : 14))
                .lineSpacing(big ? 6 : 3)
                .lineLimit(big ? 4...14 : 2...12)
                .focused($focused)
                .onSubmit(send)
                .onChange(of: draft) { absorbMention(); if slashIndex >= slashItems.count { slashIndex = 0 } }
                // ⌫ в пустом поле — убрать чип; стрелки и Tab — по меню «/»
                // Enter — отправить, Shift+Enter — новая строка; в настройках можно наоборот: ⌘Enter — отправить, Enter — строка
                .onKeyPress(.return, phases: .down) { press in
                    if app.prefs.sendWithCommand && slashItems.isEmpty {
                        if press.modifiers.contains(.command) { send(); return .handled }
                        draft += "\n"
                        return .handled
                    }
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    draft += "\n"
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard draft.isEmpty else { return .ignored }
                    if pickedSkill != nil { pickedSkill = nil; return .handled }
                    if mentioned != nil { mentioned = nil; return .handled }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    guard !slashItems.isEmpty else { return .ignored }
                    slashIndex = (slashIndex + 1) % slashItems.count
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !slashItems.isEmpty else { return .ignored }
                    slashIndex = (slashIndex - 1 + slashItems.count) % slashItems.count
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard slashItems.indices.contains(slashIndex) else { return .ignored }
                    pickSlash(slashItems[slashIndex])
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !slashItems.isEmpty else { return .ignored }
                    draft = ""
                    return .handled
                }
            }
                .frame(minHeight: big ? 96 : 48, alignment: .topLeading)
            // один ряд: слева «+», папка и режим, справа модель, «сколько думать» и отправить
            HStack(spacing: 2) {
                leftControls
                Spacer(minLength: 8)
                rightControls
            }
            .frame(height: big ? 32 : 28)
        }
        .padding(big ? 16 : 12)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.xxl))
        // без свечения в фокусе (Рома, 16.10): ровная рамка
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(
            tintBot.map { focused ? BotColor.accent($0.hue).opacity(0.45) : BotColor.soft($0.hue) } ?? (focused ? p.foreground.opacity(0.14) : p.border)))
        .background {
            // у бота — его цвет: лёгкое свечение за полем (и когда бота позвали чипом)
            if let b = tintBot {
                RoundedRectangle(cornerRadius: R.xxl).fill(BotColor.faint(b.hue)).blur(radius: 18).padding(-6).allowsHitTesting(false)
            }
        }
        // меню «/» — плавающим окном: над полем, а у большого поля новой задачи — под ним (сверху заголовок)
        .overlay(alignment: big ? .bottom : .top) {
            if !slashItems.isEmpty {
                slashMenu
                    .alignmentGuide(big ? .bottom : .top) { d in big ? d[.top] - 8 : d[.bottom] + 8 }
                    .transition(.opacity)
            }
        }
        .zIndex(1)
        .onPasteCommand(of: [.fileURL, .png, .tiff, .jpeg]) { providers in app.attach(providers) { attachments.append($0) } }
        // ширина — как у колонки переписки (Рома, 17.10): поле стоит ровно под текстом, с теми же полями по бокам.
        // Без белой полосы-градиента над полем: она закрывала последние строки ответа
        .frame(maxWidth: big ? .infinity : ChatView.columnWidth(app: app, conversation: chat.conversation, agent: agent) - 88)
        .padding(.horizontal, big ? 0 : 44).padding(.bottom, big ? 0 : 20).padding(.top, big ? 0 : 8)
        .frame(maxWidth: .infinity)
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

    /// Слева: «+», папка и режим агента, бот — каждая кнопка во всю подпись
    @ViewBuilder private var leftControls: some View {
        // как в Claude: «+» в левом нижнем углу — картинки и файлы
        PlusMenu(app: app, agent: agent, canPickFolder: agent && chat.conversation == nil, draft: $draft, attachments: $attachments).fixedSize()
        if agent { folderPicker.fixedSize(); modePicker.fixedSize() }
        if let b = currentBot { botChip(b).fixedSize(); botFolderPicker(b).fixedSize(); botEffortPicker(b).fixedSize() }
        ElsewherePill(app: app)
    }

    /// Справа: модель, «сколько думать», отправить
    @ViewBuilder private var rightControls: some View {
        // у бота модель задана в его паспорте
        if !inBot {
            modelPicker.fixedSize()
            effortPicker.fixedSize()
        }
        sendButton.padding(.leading, 4)
    }

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
        // открыто меню «/» — Enter выбирает строку
        if slashItems.indices.contains(slashIndex) { pickSlash(slashItems[slashIndex]); return }
        // идёт ответ — сообщение встаёт в очередь (в группе — сразу в комнату)
        guard canSend, ready else { return }
        var text = draft
        if let sk = pickedSkill { text = "Возьми навык «\(sk.name)»: " + text }
        if let b = mentioned { text = "@\(b.id) " + text }
        // «/что-то», что не наша команда, не уходит в claude командой: там свои навыки Claude Code
        if text.hasPrefix("/") { text = "\u{200B}" + text }
        chat.send(text, attachments: attachments)
        draft = ""
        attachments = []
        mentioned = nil
        pickedSkill = nil
    }

    /// Меню «/»: «Команды» и «Навыки» разделами, значок в квадратике, выбранная строка подсвечена; ↑↓ Tab Enter.
    /// Плавает над полем, не выше 320 и листается — выбранная строка всегда видна
    private var slashMenu: some View {
        let items = slashItems
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        if i == 0 || items[i - 1].kind != it.kind {
                            Text(it.kind == .action ? "Команды" : "Навыки").tw(11, .medium, lh: 14).foregroundStyle(p.mutedFg)
                                .padding(.horizontal, 10).padding(.top, i == 0 ? 4 : 10).padding(.bottom, 4)
                        }
                        Button { pickSlash(it) } label: {
                            HStack(spacing: 10) {
                                Icon(it.icon, 14).foregroundStyle(i == slashIndex ? p.glow : p.mutedFg)
                                    .frame(width: 26, height: 26)
                                    .background(p.foreground.opacity(i == slashIndex ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: R.md))
                                Text("/" + it.id).font(.geist(13, .medium)).foregroundStyle(p.foreground).lineLimit(1).layoutPriority(1)
                                Text(it.note).font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
                                Spacer(minLength: 0)
                                if i == slashIndex { Text("↵").font(.geist(12)).foregroundStyle(p.mutedFg) }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(i == slashIndex ? p.foreground.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(it.id)
                        .onHover { if $0 { slashIndex = i } }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.automatic)
            .frame(height: min(320, CGFloat(items.count) * 33 + CGFloat(Set(items.map(\.kind)).count) * 26 + 12))
            .onChange(of: slashIndex) { _, i in if items.indices.contains(i) { proxy.scrollTo(items[i].id) } }
        }
        .background(p.popover, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.foreground.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    /// `FolderPicker`: папка проекта; у начатой сессии папка уже не меняется
    private var folderPicker: some View {
        let started = chat.conversation != nil
        let current = chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder
        let extra = started ? (chat.conversation?.extraPaths ?? []).map { URL(fileURLWithPath: $0) } : app.agentExtraDirs
        return PickerButton(open: $folderOpen, bordered: big) {
            Icon(big ? "folder-open" : "folder", big ? 16 : 14).foregroundStyle(p.glow)
            Text((current.map(AppModel.folderName) ?? "Мои файлы") + (extra.isEmpty ? "" : " +\(extra.count)")).font(.geist(big ? 14 : 12))
        } panel: {
            PopoverPanel(title: started ? "Где работает задача" : "Где работать", width: 280) {
                if started {
                    // рабочая папка начатой задачи не меняется (в ней сессия claude), но доступ к другим — можно дать
                    PopoverOption(name: current.map(AppModel.folderName) ?? "Мои файлы", note: "рабочая папка — уже не сменить", active: true) {
                        Icon("folder", 16).foregroundStyle(p.glow)
                    } action: { folderOpen = false }
                } else {
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
                }
                if !extra.isEmpty {
                    Text("Ещё доступ").font(.geist(11, .medium)).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.top, 6)
                    ForEach(extra, id: \.self) { d in
                        HStack(spacing: 8) {
                            Icon("folder", 14).foregroundStyle(p.mutedFg)
                            Text(d.lastPathComponent).font(.geist(12)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button { removeExtra(d) } label: { Icon("x", 11).foregroundStyle(p.mutedFg) }.buttonStyle(.plain).help("Убрать доступ")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                }
                Button {
                    folderOpen = false
                    pickPaths()
                } label: {
                    IconLabel(text: "Папки или файлы… (можно несколько)", icon: "plus", size: 12).font(.geist(12)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(chat.busy)
    }

    /// Несколько папок и файлов сразу: папки — доступ агенту (первая у новой задачи — рабочая), файлы — вложениями
    private func pickPaths() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Папки — агент сможет в них работать; файлы — прикрепятся к сообщению"
        guard panel.runModal() == .OK else { return }
        let files = chat.addPaths(panel.urls)
        attachments += files.compactMap(app.importAttachment)
    }

    private func removeExtra(_ d: URL) {
        if var c = chat.conversation {
            c.extraPaths?.removeAll { $0 == d.path }
            chat.setExtraPaths(c.extraPaths ?? [])
        } else {
            app.agentExtraDirs.removeAll { $0 == d }
        }
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
                .frame(maxWidth: 150, alignment: .leading)
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

/// Таблица из ответа: шапка жирным, строки через тонкие линии, ячейки с разметкой; широкая — листается вбок
struct MarkdownTable: View {
    let rows: [[String]]

    @Environment(\.palette) private var p

    var body: some View {
        let cols = rows.map(\.count).max() ?? 0
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { j in
                            Text(RichText.markdown(j < row.count ? row[j] : ""))
                                .chatTw(14, lh: 21).fontWeight(i == 0 ? .semibold : .regular)
                                .textSelection(.enabled)
                                .frame(minWidth: 60, maxWidth: 320, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .background(i == 0 ? p.foreground.opacity(0.04) : .clear)
                    if i < rows.count - 1 { Divider().overlay(p.border).gridCellUnsizedAxes(.horizontal) }
                }
            }
        }
        .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
}

/// Следит за прокруткой переписки (macOS 15+): у низа ли она. Состояние меняется только на границе —
/// иначе переписка перерисовывалась бы на каждом шаге прокрутки и лагала
private struct ScrollTracking: ViewModifier {
    @Binding var atBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                // расстояние до низа; «внизу» с запасом в обе стороны, чтобы на границе не дёргалось туда-сюда
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentSize.height - (g.contentOffset.y + g.containerSize.height)
                } action: { _, gap in
                    if atBottom && gap > 160 { atBottom = false } else if !atBottom && gap < 40 { atBottom = true }
                }
        } else {
            content
        }
    }
}

/// Позванный бот за работой: имя в его цвете, шаги (идущий — с точками и временем) и текст, пока пишется
struct LiveBotWork: View {
    let work: LiveWork
    let bot: Bot?

    @Environment(\.palette) private var p

    var body: some View {
        let tint = bot.map { BotColor.accent($0.hue) } ?? p.glow
        VStack(alignment: .leading, spacing: 12) {
            Text("@\(work.bot)\(bot.map { " · \($0.name)" } ?? "")").tw(12, .medium, lh: 16).foregroundStyle(tint)
            let pieces = AnswerPiece.layout(text: work.text, steps: work.steps)
            if pieces.isEmpty {
                HStack(spacing: 10) {
                    DotsSpinner(color: tint)
                    Text("\(bot?.name ?? "Бот") думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(tint)
                }
            }
            ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                let last = i == pieces.count - 1
                switch piece {
                case .text(let t): RichText(text: t, caret: last)
                case .steps(let s): StepsView(steps: s, live: last ? (work.started, tint) : nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension String {
    /// «Запускает swift test» → «запускает swift test»
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
