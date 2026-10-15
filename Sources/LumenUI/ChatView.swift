import LumenCore
import SwiftUI

/// Чат (`pages/chat-page.tsx`): шапка, переписка, поле ввода.
/// Только то, что работает: без вложений, голоса, ботов и боковой панели контекста.
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

    private var header: some View {
        HStack(spacing: 10) {
            Orb(state: app.orb, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.conversation?.title ?? "Новый чат").font(.geist(13.5, .medium)).lineLimit(1)
                Text("Чат — просто разговор, Lumen ничего не трогает · " + (backend == .api ? "через API" : "через подписку"))
                    .font(.geist(11.5)).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Orb(state: app.orb, size: 72)
            Text(app.profile.name.isEmpty ? "О чём поговорим?" : "Привет, \(app.profile.name). О чём поговорим?")
                .font(.geist(24, .semibold)).tracking(-0.5)
                .padding(.top, 32)
            HStack(spacing: 8) {
                ForEach(["Как прошёл день?", "Помоги сформулировать мысль", "Объясни простыми словами"], id: \.self) { idea in
                    Button { draft = idea } label: {
                        Text(idea).font(.geist(13))
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(p.card.opacity(0.5), in: Capsule())
                            .overlay(Capsule().strokeBorder(p.border))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
        }
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
                            Text("Думает…").font(.geist(13.5)).foregroundStyle(p.mutedFg)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24).padding(.vertical, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.conversation?.id) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

/// Одно сообщение: своё — пузырём справа, ответ Lumen — со сферой слева
struct MessageRow: View {
    let message: ChatMessage
    var streaming = false

    @Environment(\.palette) private var p

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .font(.geist(14.5)).lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(p.secondary, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16,
                                                                        bottomTrailingRadius: 6, topTrailingRadius: 16))
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                Orb(state: streaming ? .thinking : .idle, size: 22).padding(.top, 1)
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty {
                        RichText(text: message.text)
                    }
                    if message.stopped {
                        Label("Остановлено", systemImage: "stop.circle").font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    if let error = message.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.geist(13)).foregroundStyle(Palette.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Текст ответа: абзацы с разметкой (жирный, курсив, `код`, ссылки) и блоки кода ```
struct RichText: View {
    let text: String

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.parts(text).enumerated()), id: \.offset) { _, part in
                switch part {
                case .prose(let s):
                    Text(Self.markdown(s)).font(.geist(15)).lineSpacing(5).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let s):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(s).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled).padding(14)
                    }
                    .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.border))
                }
            }
        }
    }

    enum Part { case prose(String), code(String) }

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
                let s = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(.prose(s)) }
            }
        }
        return out
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// Поле ввода (`Composer` в макете): текст, модель, «сколько думать», отправить / «Стоп»
struct Composer: View {
    @Bindable var app: AppModel
    @Binding var draft: String
    let backend: Backend

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    private var chat: ChatController { app.chat }
    private var model: ChatModel { chat.conversation?.model ?? app.prefs.model }
    private var effort: Effort { chat.conversation?.effort ?? app.prefs.effort }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Просто напиши. ⌥↩ — новая строка", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(14.5))
                .lineLimit(1...10)
                .focused($focused)
                .onSubmit(send)
                .frame(minHeight: 40, alignment: .topLeading)
            HStack(spacing: 2) {
                Spacer()
                modelMenu
                effortMenu
                sendButton.padding(.leading, 4)
            }
        }
        .padding(12)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? p.glow.opacity(0.35) : p.border))
        .shadow(color: focused ? p.glowSoft : .clear, radius: 16)
        .animation(.easeOut(duration: 0.3), value: focused)
        .frame(maxWidth: 720)
        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 4)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
    }

    private func send() {
        guard !chat.busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chat.send(draft)
        draft = ""
    }

    private var modelMenu: some View {
        Menu {
            Section("Модель") {
                ForEach(app.availableModels(for: backend)) { m in
                    Button { chat.set(model: m) } label: {
                        Text(m == model ? "✓ \(m.name) — \(m.note)" : "\(m.name) — \(m.note)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(p.glow)
                Text(model.name).font(.geist(12, .medium))
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.visible).fixedSize()
        .padding(.horizontal, 8).frame(height: 28)
        .disabled(chat.busy)
    }

    private var effortMenu: some View {
        Menu {
            Section("Сколько думать") {
                ForEach(Effort.allCases) { e in
                    Button { chat.set(effort: e) } label: {
                        Text(e == effort ? "✓ \(e.name) — \(e.note)" : "\(e.name) — \(e.note)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                EffortBars(level: effort.level)
                Text(effort.name).font(.geist(12))
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.visible).fixedSize()
        .padding(.horizontal, 8).frame(height: 28)
        .disabled(chat.busy)
    }

    @ViewBuilder private var sendButton: some View {
        if chat.busy {
            Button(action: chat.stop) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill").font(.system(size: 9))
                    Text("Стоп").font(.geist(12.5, .medium))
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(p.secondary, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
        } else {
            let can = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(p.glow.opacity(can ? 1 : 0.35), in: Circle())
                    .shadow(color: can ? p.glowSoft : .clear, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(!can)
            .help("Отправить · ↩")
        }
    }
}

/// Пять столбиков, закрашены до уровня — как индикатор сигнала
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
