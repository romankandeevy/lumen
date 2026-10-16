import LumenCore
import SwiftUI

/// Чат (`pages/chat-page.tsx`): шапка, переписка, поле ввода — размеры из макета.
/// Чего нет, потому что ещё не работает: «+», голос, песочница и правая панель контекста.
struct ChatView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var draft = ""

    private var chat: ChatController { app.chat }
    private var backend: Backend { chat.conversation?.backend ?? app.prefs.backend }
    private var agent: Bool { chat.conversation.map { $0.kind == .agent } ?? (app.tab == .agent) }
    private var folder: URL? { chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder }

    var body: some View {
        HStack(spacing: 0) {
            content
            if app.prefs.contextOpen { ContextPanel(app: app).transition(.move(edge: .trailing)) }
        }
        .animation(.easeOut(duration: 0.2), value: app.prefs.contextOpen)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if chat.messages.isEmpty && !chat.busy {
                Group {
                    if agent { AgentEmpty(app: app) { draft = $0 } } else { empty }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            Composer(app: app, draft: $draft, backend: backend, agent: agent)
        }
        .foregroundStyle(p.foreground)
    }

    /// h-14 border-b px-5 gap-3: знак 28 со сферой 18, заголовок text-sm medium, подпись text-xs
    private var header: some View {
        HStack(spacing: 12) {
            if agent {
                Icon("folder", 16).foregroundStyle(p.glow)
                    .frame(width: 28, height: 28)
                    .background(p.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: R.lg))
            } else {
                Orb(state: app.orb, size: 18).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let c = chat.conversation {
                    RenamableTitle(app: app, conversation: c)
                } else {
                    Text(agent ? "Новая задача" : "Новый чат").tw(14, .medium, lh: 20).lineLimit(1)
                }
                if agent {
                    HStack(spacing: 6) {
                        Text("Агент в папке \(folder?.lastPathComponent ?? "—")")
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
            IconButton(icon: "panel-right", help: "Контекст: память, окно, расход", active: app.prefs.contextOpen) {
                app.update { $0.contextOpen.toggle() }
            }
        }
        .padding(.horizontal, 20)
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
            // голосовой кнопки и @бота нет, пока они не работают
            FlowChips(items: ["Как прошёл день?", "Объясни, как работает память Lumen", "Запомни, что я встаю в 9"]) { draft = $0 }
                .padding(.top, 24)
        }
        .frame(maxWidth: 704)
        .padding(.horizontal, 24)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
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
                    } else if chat.thinking {
                        HStack(spacing: 12) {
                            Orb(state: .thinking, size: 22)
                            Text("Думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg)
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
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.conversation?.id) { proxy.scrollTo("bottom", anchor: .bottom) }
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
        } else {
            HStack(alignment: .top, spacing: 14) {
                Orb(state: streaming ? .writing : .idle, size: 22, animated: streaming).padding(.top, 2)
                VStack(alignment: .leading, spacing: 12) {
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

    static func markdown(_ s: String) -> AttributedString {
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
    let backend: Backend
    var agent = false

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    @State private var modelOpen = false
    @State private var effortOpen = false
    @State private var folderOpen = false

    private var chat: ChatController { app.chat }
    private var model: ChatModel { chat.conversation?.model ?? (agent ? app.defaultAgentModel : app.prefs.model) }
    private var effort: Effort { chat.conversation?.effort ?? (agent ? .high : app.prefs.effort) }
    /// Агенту без папки отправлять нечего
    private var ready: Bool { !agent || chat.conversation != nil || app.agentFolder != nil }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(agent ? "Что сделать в проекте?" : "Просто напиши", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(14))
                .lineSpacing(3)
                .help("Enter — отправить, ⌥Enter — новая строка")
                .lineLimit(2...12)
                .focused($focused)
                .onSubmit(send)
                .frame(minHeight: 48, alignment: .topLeading)
            HStack(spacing: 2) {
                if agent { folderPicker }
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
                modelPicker
                effortPicker
                sendButton.padding(.leading, 4)
            }
            .frame(height: 28)
        }
        .padding(12)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(focused ? p.glow.opacity(0.35) : p.border))
        .shadow(color: focused ? p.glowSoft : .clear, radius: 16)
        .animation(.easeOut(duration: 0.4), value: focused)
        .frame(maxWidth: app.prefs.chatWidth.points)
        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 4)
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
        chat.send(draft)
        draft = ""
    }

    /// `FolderPicker`: папка проекта; у начатой сессии папка уже не меняется
    private var folderPicker: some View {
        let current = chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder
        return PickerButton(open: $folderOpen) {
            Icon("folder", 14).foregroundStyle(p.glow)
            Text(current?.lastPathComponent ?? "Выбрать папку").font(.geist(12))
        } panel: {
            PopoverPanel(title: "Папка проекта", width: 256) {
                ForEach(app.recentFolders, id: \.self) { f in
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
                ForEach(app.availableModels(for: backend)) { m in
                    PopoverOption(name: m.name, note: m.note, active: m == model) {
                        Icon("sparkles", 16).foregroundStyle(p.mutedFg)
                    } action: {
                        chat.set(model: m)
                        modelOpen = false
                    }
                }
            }
        }
        .disabled(chat.busy)
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
                    .frame(width: 28, height: 28)
                    // как в макете: кнопка всегда светится (bg-glow, тень 16px glow-soft)
                    .background(p.glow, in: Circle())
                    .shadow(color: p.glowSoft, radius: 8)
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
            .padding(.horizontal, 8).frame(height: 28)
            .background(hover ? p.foreground.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
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
