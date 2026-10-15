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

    var body: some View {
        VStack(spacing: 0) {
            header
            if chat.messages.isEmpty && !chat.busy {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            Composer(app: app, draft: $draft, backend: backend)
        }
        .foregroundStyle(p.foreground)
    }

    /// h-14 border-b px-5 gap-3: знак 28 со сферой 18, заголовок text-sm medium, подпись text-xs
    private var header: some View {
        HStack(spacing: 12) {
            Orb(state: app.orb, size: 18).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.conversation?.title ?? "Новый чат").font(.geist(14, .medium)).lineLimit(1)
                Text("Чат — просто разговор, Lumen ничего не трогает" + (backend == .api ? " · через API" : ""))
                    .font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer()
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
                .font(.geist(24, .semibold)).tracking(-0.48)
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            Text("Помню \(Plural.facts(app.memoryCount)) о тебе, проектах и людях.")
                .font(.geist(14)).foregroundStyle(p.mutedFg)
                .padding(.top, 8)
            FlowChips(items: ["Как прошёл день?", "Объясни, как работает память Lumen", "Помоги сформулировать мысль"]) { draft = $0 }
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
                        MessageRow(message: m).id(m.id)
                    }
                    if let s = chat.streaming {
                        MessageRow(message: s, streaming: true)
                    } else if chat.thinking {
                        HStack(spacing: 12) {
                            Orb(state: .thinking, size: 22)
                            Text("Думает…").font(.geist(14)).foregroundStyle(p.mutedFg)
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
                Text(text).font(.geist(14))
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
    var streaming = false

    @Environment(\.palette) private var p

    var body: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(message.text)
                    .font(.geist(14)).lineSpacing(6)
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
                    if !message.text.isEmpty {
                        RichText(text: message.text)
                    }
                    if message.stopped {
                        Label("Остановлено", systemImage: "stop.circle").font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    if let error = message.error {
                        Label(error, systemImage: "exclamationmark.triangle")
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

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.parts(text).enumerated()), id: \.offset) { _, part in
                switch part {
                case .prose(let s):
                    Text(Self.markdown(s)).font(.geist(15)).lineSpacing(6.5).textSelection(.enabled)
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

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    @State private var modelOpen = false
    @State private var effortOpen = false

    private var chat: ChatController { app.chat }
    private var model: ChatModel { chat.conversation?.model ?? app.prefs.model }
    private var effort: Effort { chat.conversation?.effort ?? app.prefs.effort }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Просто напиши. ⌥↩ — новая строка", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(14))
                .lineSpacing(3)
                .lineLimit(2...12)
                .focused($focused)
                .onSubmit(send)
                .frame(minHeight: 48, alignment: .topLeading)
            HStack(spacing: 2) {
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
        guard !chat.busy, canSend else { return }
        chat.send(draft)
        draft = ""
    }

    /// `ModelPicker`: Sparkles text-glow + название text-xs medium + стрелка
    private var modelPicker: some View {
        PickerButton(open: $modelOpen) {
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(p.glow)
            Text(model.name).font(.geist(12, .medium))
        } panel: {
            PopoverPanel(title: "Модель") {
                ForEach(app.availableModels(for: backend)) { m in
                    PopoverOption(name: m.name, note: m.note, active: m == model) {
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(p.mutedFg)
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
                    Image(systemName: "square.fill").font(.system(size: 10))
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
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(p.glow.opacity(canSend ? 1 : 0.35), in: Circle())
                    .shadow(color: canSend ? p.glowSoft : .clear, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Отправить · ↩")
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
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.5)
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
