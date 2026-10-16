import AppKit
import LumenCore
import SwiftUI
import UniformTypeIdentifiers

/// Чат (`pages/chat-page.tsx`): шапка, переписка, поле ввода — размеры из макета.
/// Чего нет, потому что ещё не работает: «+», голос, песочница и правая панель контекста.
struct ChatView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var dropping = false

    private var chat: ChatController { app.chat }
    private var backend: Backend { chat.conversation?.backend ?? app.prefs.backend }
    private var agent: Bool { chat.conversation.map { $0.kind == .agent } ?? (app.tab == .agent) }
    private var folder: URL? { chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder }
    /// Открыт постоянный разговор бота
    private var bot: Bot? { chat.conversation?.kind == .bot ? app.bot(chat.conversation?.botID) : nil }

    var body: some View {
        HStack(spacing: 0) {
            content
            if app.prefs.contextOpen {
                Group {
                    if let bot { BotPassport(app: app, bot: bot) } else { ContextPanel(app: app) }
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
                Group {
                    // новая задача агента — вариант A: поле по центру, своё нижнее поле не нужно
                    if let bot { botEmpty(bot) } else if agent { AgentHome(app: app, draft: $draft, attachments: $attachments, backend: backend) } else { empty }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            if !(agent && chat.messages.isEmpty && !chat.busy) {
                Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: agent)
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
    }

    /// h-14 border-b px-5 gap-3: знак 28 со сферой 18, заголовок text-sm medium, подпись text-xs
    private var header: some View {
        HStack(spacing: 12) {
            if let bot {
                BotAvatar(bot: bot, size: 28)
            } else if agent {
                Icon("folder", 16).foregroundStyle(p.glow)
                    .frame(width: 28, height: 28)
                    .background(p.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: R.lg))
            } else {
                Orb(state: app.orb, size: 18).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let bot {
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
                if bot != nil {
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
            if let bot { IconButton(icon: "pencil", help: "Изменить бота") { app.page = .botEditor(bot.id) } }
            IconButton(icon: "panel-right", help: bot == nil ? "Контекст: память, окно, расход" : "Паспорт бота: что может и что отрезано",
                       active: app.prefs.contextOpen) {
                app.update { $0.contextOpen.toggle() }
            }
        }
        .padding(.horizontal, 20)
        // панель спрятана — слева кнопки окна и «показать панель»
        .padding(.leading, app.prefs.sidebarHidden ? 150 : 0)
        .frame(height: 56)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    /// `ChatEmpty`: сфера 72, «Привет, Рома. О чём поговорим?», сколько фактов помнит, подсказки
    private var empty: some View {
        VStack(spacing: 0) {
            Orb(state: app.orb, size: 72)
            Text(app.profile.name.isEmpty ? "О чём поговорим?" : "Привет, \(app.profile.name). О чём поговорим?")
                .tw(24, .semibold, lh: 32).tracking(-0.48)
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            Text("Помню \(Plural.facts(app.memoryCount)) о тебе, проектах и людях.")
                .tw(14, lh: 20).foregroundStyle(p.mutedFg)
                .padding(.top, 8)
            // Lumen сам предлагает, чем заняться — из памяти и недавних разговоров
            FlowChips(items: app.suggestions) { draft = $0 }
                .padding(.top, 24)
                .animation(.easeOut(duration: 0.3), value: app.suggestions)
                .task { app.refreshSuggestionsIfNeeded() }
        }
        .frame(maxWidth: 704)
        .padding(.horizontal, 24)
    }

    /// Пустой разговор бота: знак, роль, его подсказки
    private func botEmpty(_ b: Bot) -> some View {
        VStack(spacing: 0) {
            BotAvatar(bot: b, size: 64)
            Text(b.name).tw(24, .semibold, lh: 32).tracking(-0.48).padding(.top, 24)
            Text(b.role).tw(14, lh: 20).foregroundStyle(p.mutedFg).multilineTextAlignment(.center).padding(.top, 8)
            Text("Это его единственный разговор. Позвать из любого чата: @\(b.id) и задача.")
                .tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.8)).padding(.top, 4)
            if !b.starters.isEmpty {
                FlowChips(items: b.starters) { draft = $0 }.padding(.top, 24)
            }
        }
        .frame(maxWidth: 704)
        .padding(.horizontal, 24)
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
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(chat.messages) { m in
                        MessageRow(message: m, chat: chat).id(m.id)
                    }
                    if !chat.busy, let last = chat.messages.last, let next = last.next {
                        NextStepCard(next: next) { chat.answer($0, on: last) } close: { chat.dismissNext(last) }
                    }
                    if let s = chat.streaming {
                        MessageRow(message: s, chat: chat, streaming: true)
                    }
                    if let ask = chat.pendingPermission, ask.conversationID == chat.conversation?.id {
                        PermissionCard(chat: chat, ask: ask.request).id("permission-\(ask.request.id)")
                    } else if chat.thinking {
                        HStack(spacing: 12) {
                            if let b = app.bot(chat.turnBot) {
                                BotAvatar(bot: b, size: 22)
                                Text("\(b.name) работает…").tw(14, lh: 20).foregroundStyle(p.mutedFg)
                            } else {
                                Orb(state: .thinking, size: 22)
                                Text("Думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24).padding(.vertical, 32)
                .frame(maxWidth: app.prefs.chatWidth.points)
                .animation(.easeInOut(duration: 0.3), value: app.prefs.chatWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            // к концу — когда страница уже разложена (иначе после смены вкладки переписка оказывалась пустой)
            .onAppear { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.messages.count) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.conversation?.id) { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.pendingPermission?.request.id) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
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

    @Environment(\.palette) private var p

    var body: some View {
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
            if !message.text.isEmpty {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(message.text)
                    .tw(14, lh: 22.75)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(p.secondary, in: UnevenRoundedRectangle(topLeadingRadius: R.xxl, bottomLeadingRadius: R.xxl,
                                                                        bottomTrailingRadius: R.md, topTrailingRadius: R.xxl))
                    .containerRelativeFrame(.horizontal, alignment: .trailing) { w, _ in w * 0.8 }
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            if let via = message.via { ViaChip(via: via, app: chat?.app) }
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
                    if !message.steps.isEmpty {
                        StepsView(steps: message.steps, live: streaming)
                    }
                    // блок «что дальше» пока пишется — не показывать сырым
                    let shown = NextStep.split(message.text).text
                    if !shown.isEmpty {
                        RichText(text: shown, caret: streaming)
                    }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    @State private var modelOpen = false
    @State private var effortOpen = false
    @State private var folderOpen = false
    @State private var modeOpen = false

    private var chat: ChatController { app.chat }
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
        return app.bots.filter { q.isEmpty || $0.id.hasPrefix(q) || $0.name.lowercased().contains(q) }
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
            EffortBars(level: b.effort.level)
            Text(b.effort.name).font(.geist(12))
        } panel: {
            PopoverPanel(title: "Сколько думать") {
                ForEach(Effort.allCases) { e in
                    PopoverOption(name: e.name, note: e.note, active: e == b.effort) { EffortBars(level: e.level) } action: {
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
            if !attachments.isEmpty { AttachmentStrip(items: $attachments) }
            TextField(big ? "Опиши задачу: что сделать, починить или проверить" : (agent ? "Что сделать в проекте?" : (currentBot.map { "Задача для «\($0.name)»" } ?? "Просто напиши")),
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(big ? 15 : 14))
                .lineSpacing(big ? 6 : 3)
                .help("Enter — отправить, ⌥Enter — новая строка")
                .lineLimit(big ? 4...14 : 2...12)
                .focused($focused)
                .onSubmit(send)
                .frame(minHeight: big ? 96 : 48, alignment: .topLeading)
            HStack(spacing: 2) {
                // как в Claude: «+» в левом нижнем углу — картинки и файлы
                IconButton(icon: "plus", help: "Прикрепить картинки и файлы · или перетащи их в поле, или вставь картинку ⌘V") {
                    attachments += app.chooseAttachments()
                }
                if agent { folderPicker; modePicker }
                if let b = currentBot { botChip(b); botFolderPicker(b); botEffortPicker(b) }
                if chat.busyElsewhere, let other = chat.running {
                    Button { app.openChat(other) } label: {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(p.glow)
                            Text("Отвечаю в «\(other.title)»").lineLimit(1)
                        }
                        .font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
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
    }

    private func send() {
        guard chat.running == nil, canSend, ready else { return }
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
            Icon("sparkles", 14).foregroundStyle(p.glow)
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
            EffortBars(level: effort.level)
            Text(effort.name).font(.geist(12))
        } panel: {
            PopoverPanel(title: "Сколько думать") {
                ForEach(Effort.allCases) { e in
                    PopoverOption(name: e.name, note: e.note, active: e == effort) {
                        EffortBars(level: e.level)
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
        if chat.busy {
            Button(action: chat.stop) {
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
        } else {
            Button(action: send) {
                Icon("arrow-up", 16)
                    .foregroundStyle(.black)
                    .frame(width: big ? 32 : 28, height: big ? 32 : 28)
                    // как в макете: кнопка всегда светится (bg-glow, тень 16px glow-soft)
                    .background(currentBot.map { BotColor.accent($0.hue) } ?? p.glow, in: Circle())
                    .shadow(color: currentBot.map { BotColor.soft($0.hue) } ?? p.glowSoft, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!ready || chat.busyElsewhere)
            .help(!ready ? "Сначала выбери папку проекта"
                  : chat.busyElsewhere ? "Lumen ещё отвечает в «\(chat.running?.title ?? "")»" : "Отправить · ↩")
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
