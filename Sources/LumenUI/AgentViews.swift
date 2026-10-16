import LumenCore
import LumenProviders
import SwiftUI

/// Новая задача агента — вариант A «как Claude Code» (mockups/19-agent-new-A…, выбран Ромой 16.10):
/// «Что сделаем в {папка}?», большое поле по центру с папкой внутри, под ним ветка git и незакоммиченное,
/// ниже недавние задачи этой папки.
struct AgentHome: View {
    @Bindable var app: AppModel
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let backend: Backend

    @Environment(\.palette) private var p
    @State private var git: Git.Info?

    private var folder: URL? { app.agentFolder }

    /// Последние задачи агента в выбранной папке
    private var recent: [Conversation] {
        guard let path = folder?.standardizedFileURL.path else { return [] }
        return app.conversations.filter { $0.kind == .agent && $0.folder.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == path }
            .prefix(3).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Orb(state: app.orb, size: 28)
                    if let folder {
                        (AppModel.isHome(folder) ? Text("Что сделаем на Маке?")
                            : Text("Что сделаем в ") + Text(folder.lastPathComponent).foregroundColor(p.glow) + Text("?"))
                            .tw(24, .semibold, lh: 32).tracking(-0.48)
                    } else {
                        Text("Выбери папку проекта").tw(24, .semibold, lh: 32).tracking(-0.48)
                    }
                }
                .padding(.bottom, 24)

                Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: true, big: true)

                // ветка и незакоммиченное — настоящее, из git
                HStack(spacing: 12) {
                    if let git {
                        HStack(spacing: 4) { Icon("git-branch", 14); Text(git.branch) }
                        if git.changed > 0 {
                            Text("\(git.changed) " + Plural.form(git.changed, "изменённый файл", "изменённых файла", "изменённых файлов") + " не закоммичены")
                                .foregroundStyle(p.glow)
                        } else {
                            Text("всё закоммичено")
                        }
                    } else if folder != nil {
                        Text("папка без git — «Изменения» после хода не покажутся")
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 4) { Icon("laptop", 14); Text("этот Мак · push только с твоего OK") }
                }
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                .padding(.horizontal, 4).padding(.top, 12)

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Недавно в этой папке").tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { i, c in
                                if i > 0 { p.border.frame(height: 1) }
                                RecentTaskRow(c: c) { app.openChat(c) }
                            }
                        }
                        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
                        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                    }
                    .padding(.top, 40)
                }
            }
            .frame(maxWidth: Composer.width)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
        }
        .scrollIndicators(.never)
        .foregroundStyle(p.foreground)
        .task(id: folder) {
            git = nil
            if let folder { git = await Git(folder: folder).info() }
        }
    }
}

/// Строка «Недавно в этой папке»: часы, название, когда
struct RecentTaskRow: View {
    let c: Conversation
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon("clock", 14).foregroundStyle(p.mutedFg)
                Text(c.title).tw(14, lh: 20).lineLimit(1)
                Spacer(minLength: 8)
                Text(RelativeWhen.string(c.updatedAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(hover ? p.foreground.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Плитка папки: rounded-xl border px-3 py-2.5 text-sm, выбранная светится
struct FolderTile: View {
    let name: String
    let active: Bool
    var muted = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(muted ? "folder-plus" : "folder", 16)
                    .foregroundStyle(active ? p.glow : p.mutedFg)
                Text(name).font(.geist(14)).lineLimit(1).foregroundStyle(muted ? p.mutedFg : p.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(active ? p.glow.opacity(0.06) : (hover ? p.card : p.card.opacity(0.4)), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(active ? p.glow.opacity(0.5) : p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Шаги агента (`msg.steps` в макете): «▸ 5 шагов: читал, правил, запускал», по нажатию — список
struct StepsView: View {
    let steps: [AgentStep]
    var live = false

    @Environment(\.palette) private var p
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Icon(open ? "chevron-down" : "chevron-right", 12)
                    Text(summary).font(.geist(12))
                    if live { LiveDot(color: p.glow, size: 6) }
                }
                .foregroundStyle(p.mutedFg)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || live {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((open ? steps : Array(steps.suffix(3))).enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 8) {
                            Icon(Self.icon(s.kind), 14)
                            Text(s.text).font(.geist(12)).lineLimit(1)
                        }
                    }
                }
                .foregroundStyle(p.mutedFg)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { p.border.frame(width: 1) }
            }
        }
    }

    private var summary: String {
        let n = steps.count
        var kinds: [String] = []
        if steps.contains(where: { $0.kind == .read || $0.kind == .search }) { kinds.append("читал") }
        if steps.contains(where: { $0.kind == .edit }) { kinds.append("правил") }
        if steps.contains(where: { $0.kind == .run }) { kinds.append("запускал") }
        if steps.contains(where: { $0.kind == .web }) { kinds.append("искал в интернете") }
        return "\(n) " + Plural.form(n, "шаг", "шага", "шагов") + (kinds.isEmpty ? "" : ": " + kinds.joined(separator: ", "))
    }

    static func icon(_ k: AgentStep.Kind) -> String {
        switch k {
        case .read: "eye"
        case .edit: "pencil"
        case .run: "terminal"
        case .search: "search"
        case .web: "globe"
        case .think: "brain"
        case .other: "wrench"
        }
    }
}

/// Карточка «Изменения» (`ChangeCard`): файлы с +/−, «Откатить», «Разница», «Закоммитить».
/// Push здесь нет: его делает человек.
struct ChangeCard: View {
    let message: ChatMessage
    let changes: ChangeSet
    let chat: ChatController

    @Environment(\.palette) private var p
    @State private var diffOpen = false
    @State private var diffText = ""
    @State private var busy = false

    private var added: Int { changes.files.reduce(0) { $0 + $1.added } }
    private var removed: Int { changes.files.reduce(0) { $0 + $1.removed } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon("git-commit-horizontal", 16).foregroundStyle(p.mutedFg)
                Text("Изменения").font(.geist(14, .medium))
                Text("\(changes.files.count) " + Plural.form(changes.files.count, "файл", "файла", "файлов") + ", +\(added) −\(removed)")
                    .font(.geist(12)).foregroundStyle(p.mutedFg)
                Spacer()
                Text(stateName).font(.geist(12))
                    .padding(.horizontal, 8).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }

            VStack(spacing: 4) {
                ForEach(changes.files, id: \.path) { f in
                    HStack(spacing: 8) {
                        Text(f.status).foregroundStyle(p.mutedFg)
                        Text(f.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("+\(f.added)").foregroundStyle(Color(hex: 0x6EE7B7).opacity(0.9))
                        Text("−\(f.removed)").foregroundStyle(Palette.destructive.opacity(0.9))
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let id = message.id, let err = chat.changeError[id] {
                Text(err).font(.geist(12)).foregroundStyle(Palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
            }

            HStack(spacing: 8) {
                LButton(title: "Откатить", icon: "undo-2", kind: .ghost, size: .sm) { act { await chat.revert(message) } }
                    .disabled(changes.state != .applied || busy)
                    .help("Вернуть файлы как были до этого хода. Новые файлы уйдут в Корзину.")
                Spacer()
                LButton(title: "Разница", icon: "eye", kind: .outline, size: .sm) {
                    Task {
                        diffText = await chat.diff(message)
                        diffOpen = true
                    }
                }
                LButton(title: "Закоммитить", icon: "circle-check", kind: .primary, size: .sm) { act { await chat.commit(message) } }
                    .disabled(changes.state != .applied || busy)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .top) { p.border.frame(height: 1) }
        }
        .background(p.card, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .sheet(isPresented: $diffOpen) {
            DiffSheet(text: diffText) { diffOpen = false }.environment(\.palette, p)
        }
    }

    private var stateName: String {
        switch changes.state {
        case .applied: "применено"
        case .committed: "закоммичено"
        case .reverted: "откачено"
        }
    }

    private func act(_ f: @escaping () async -> Void) {
        busy = true
        Task {
            await f()
            busy = false
        }
    }
}

/// Разница до и после: строки с + зелёные, с − красные
struct DiffSheet: View {
    let text: String
    let close: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Разница").font(.geist(16, .semibold))
                Spacer()
                LButton(title: "Готово", kind: .primary, size: .sm, action: close).keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4000).enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : String(line))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(color(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(bg(line))
                    }
                }
                .textSelection(.enabled)
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(p.popover)
        .foregroundStyle(p.foreground)
        .preferredColorScheme(.dark)
    }

    private func color(_ l: Substring) -> Color {
        if l.hasPrefix("+++") || l.hasPrefix("---") || l.hasPrefix("diff ") || l.hasPrefix("index ") { return p.mutedFg }
        if l.hasPrefix("+") { return Color(hex: 0x6EE7B7) }
        if l.hasPrefix("-") { return Palette.destructive }
        if l.hasPrefix("@@") { return p.glow }
        return p.foreground.opacity(0.8)
    }

    private func bg(_ l: Substring) -> Color {
        if l.hasPrefix("+") && !l.hasPrefix("+++") { return Color(hex: 0x6EE7B7).opacity(0.06) }
        if l.hasPrefix("-") && !l.hasPrefix("---") { return Palette.destructive.opacity(0.06) }
        return .clear
    }
}

/// План работы (`PlanList`): сделано — галочка, сейчас — крутится, дальше — пунктир; сверху «N из M»
struct PlanList: View {
    let items: [PlanItem]

    @Environment(\.palette) private var p

    var body: some View {
        let done = items.filter { $0.state == .done }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.foreground.opacity(0.1))
                        Capsule().fill(p.glow).frame(width: g.size.width * CGFloat(done) / CGFloat(max(items.count, 1)))
                            .animation(.easeOut(duration: 0.5), value: done)
                    }
                }
                .frame(height: 4)
                Text("\(done) из \(items.count)").font(.geist(11)).foregroundStyle(p.mutedFg).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .top, spacing: 10) {
                        PlanMark(state: it.state).padding(.top, 1)
                        Text(it.text)
                            .font(.geist(13, it.state == .doing ? .medium : .regular))
                            .foregroundStyle(it.state == .done ? p.mutedFg : (it.state == .doing ? p.foreground : p.foreground.opacity(0.75)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct PlanMark: View {
    let state: PlanItem.State

    @Environment(\.palette) private var p
    @State private var spin = false

    var body: some View {
        switch state {
        case .done:
            Icon("check", 12).foregroundStyle(p.background)
                .frame(width: 17, height: 17).background(p.foreground.opacity(0.7), in: Circle())
        case .doing:
            Circle().stroke(p.foreground.opacity(0.15), lineWidth: 2)
                .overlay(Circle().trim(from: 0, to: 0.25).stroke(p.glow, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
                .frame(width: 15, height: 15).padding(1)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true } }
        case .todo:
            Circle().strokeBorder(p.foreground.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                .frame(width: 17, height: 17)
        }
    }
}

/// Карточка «что дальше» (`NextStep`): итог, вопрос, главная кнопка с ⌘↵, вторая — альтернатива, крестик — убрать
struct NextStepCard: View {
    let next: NextStep
    let answer: (NextStep.Choice) -> Void
    let close: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(next.recap).font(.geist(15)).lineSpacing(5).foregroundStyle(p.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true).padding(.trailing, 28)
            if let ask = next.ask, !ask.isEmpty {
                Text(ask).font(.geist(15)).fixedSize(horizontal: false, vertical: true)
            }
            if next.primary != nil || next.secondary != nil {
                HStack(spacing: 8) {
                    if let primary = next.primary {
                        Button { answer(primary) } label: {
                            HStack(spacing: 6) {
                                Text(primary.label).font(.geist(14, .medium))
                                HStack(spacing: 2) { Kbd("⌘"); Kbd("↵") }
                            }
                            .foregroundStyle(p.background)
                            .padding(.leading, 14).padding(.trailing, 6).frame(height: 36)
                            .background(p.foreground, in: RoundedRectangle(cornerRadius: R.xl))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    if let secondary = next.secondary {
                        Button { answer(secondary) } label: {
                            Text(secondary.label).font(.geist(14, .medium))
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(p.secondary, in: RoundedRectangle(cornerRadius: R.xl))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.7), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.border))
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Icon("x", 14).foregroundStyle(p.mutedFg) }
                .buttonStyle(.plain).help("Убрать").padding(14)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private struct Kbd: View {
        let s: String
        init(_ s: String) { self.s = s }
        @Environment(\.palette) private var p
        var body: some View {
            Text(s).font(.geist(12)).frame(width: 24, height: 24)
                .background(p.background.opacity(0.1), in: RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.background.opacity(0.2)))
        }
    }
}

/// Агент спрашивает «можно?» — как запрос разрешения в Claude Code. Для готового плана — свой вид.
struct PermissionCard: View {
    let chat: ChatController
    let ask: ClaudeEvent.PermissionRequest

    @Environment(\.palette) private var p
    @State private var note = ""
    @State private var revising = false

    var body: some View {
        if ask.tool == "ExitPlanMode" { plan } else { permission }
    }

    // MARK: разрешение

    private var permission: some View {
        let step = ask.step
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Icon("hand", 15).foregroundStyle(p.glow)
                Text("Можно?").tw(13, .medium, lh: 18)
                Text(step.text).tw(13, lh: 18).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            if let detail {
                ScrollView {
                    Text(detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            }
            HStack(spacing: 8) {
                LButton(title: "Разрешить", icon: "check", kind: .primary, small: true) { chat.answerPermission(allow: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                LButton(title: "Разрешать до конца разговора", kind: .outline, small: true) { chat.answerPermission(allow: true, always: true) }
                LButton(title: "Отклонить", kind: .ghost, small: true) { chat.answerPermission(allow: false) }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer(minLength: 0)
                Text("⌘↵ — разрешить · Esc — отклонить").tw(11, lh: 14).foregroundStyle(p.mutedFg)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.3)))
    }

    /// Что именно: команда, файл и правка
    private var detail: String? {
        let i = ask.input
        switch ask.tool {
        case "Bash": return i["command"] as? String
        case "Write":
            let text = (i["content"] as? String ?? "").prefix(1200)
            return "\(i["file_path"] as? String ?? "")\n\n\(text)"
        case "Edit":
            let old = (i["old_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "- " + $0 }
            let new = (i["new_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "+ " + $0 }
            return "\(i["file_path"] as? String ?? "")\n\n" + (old + new).joined(separator: "\n")
        case "WebFetch": return i["url"] as? String
        default:
            let json = ask.inputJSON
            return json == "{}" ? nil : String(json.prefix(800))
        }
    }

    // MARK: план готов

    private var plan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Icon("list-checks", 15).foregroundStyle(p.glow)
                Text("План готов — выполнить?").tw(13, .medium, lh: 18)
            }
            RichText(text: ask.input["plan"] as? String ?? "")
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            if revising {
                HStack(spacing: 8) {
                    GlowField(placeholder: "Что поменять в плане", text: $note) { chat.answerPlan(run: nil, note: note) }
                    LButton(title: "Отправить", kind: .outline, small: true) { chat.answerPlan(run: nil, note: note) }
                }
            }
            HStack(spacing: 8) {
                LButton(title: "Выполнить · принимать правки", icon: "check", kind: .primary, small: true) { chat.answerPlan(run: .acceptEdits) }
                    .keyboardShortcut(.return, modifiers: .command)
                LButton(title: "Авто", kind: .outline, small: true) { chat.answerPlan(run: .auto) }
                LButton(title: "Спрашивать каждый шаг", kind: .outline, small: true) { chat.answerPlan(run: .manual) }
                LButton(title: "Доработать", kind: .ghost, small: true) { revising = true }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.3)))
    }
}
