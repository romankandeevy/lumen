import LumenCore
import SwiftUI

/// Пустой экран агента (`AgentEmpty`): «Что сделать?», папка, подсказки.
/// «Где» (облако через API) появится, когда заработает.
struct AgentEmpty: View {
    @Bindable var app: AppModel
    let pick: (String) -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Что сделать?").font(.geist(24, .semibold)).tracking(-0.48)
            Text("Агент работает в папке проекта: читает, правит, собирает. Push и выкатка — только с твоего OK.")
                .font(.geist(14)).foregroundStyle(p.mutedFg).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            Text("Папка").font(.geist(12)).foregroundStyle(p.mutedFg).padding(.top, 24).padding(.bottom, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(app.recentFolders.prefix(7), id: \.self) { f in
                    FolderTile(name: f.lastPathComponent, active: f.standardizedFileURL.path == app.agentFolder?.standardizedFileURL.path) { app.agentFolder = f }
                }
                FolderTile(name: "Другая папка…", active: false, muted: true) { app.chooseFolder() }
            }
            FlowChips(items: ["Найди и почини падение", "Собери и проверь сборку", "Объясни, как устроен проект"], pick: pick)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(p.foreground)
        .frame(maxWidth: 704, alignment: .leading)
        .padding(.horizontal, 24)
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
                Image(systemName: muted ? "folder.badge.plus" : "folder").font(.system(size: 14))
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
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                    Text(summary).font(.geist(12))
                    if live { ProgressView().controlSize(.mini).tint(p.glow) }
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
                            Image(systemName: Self.icon(s.kind)).font(.system(size: 11)).frame(width: 14)
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
        case .search: "magnifyingglass"
        case .web: "globe"
        case .think: "brain"
        case .other: "wrench.and.screwdriver"
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
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 13)).foregroundStyle(p.mutedFg)
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
                LButton(title: "Откатить", icon: "arrow.uturn.backward", kind: .ghost, size: .sm) { act { await chat.revert(message) } }
                    .disabled(changes.state != .applied || busy)
                    .help("Вернуть файлы как были до этого хода. Новые файлы уйдут в Корзину.")
                Spacer()
                LButton(title: "Разница", icon: "eye", kind: .outline, size: .sm) {
                    Task {
                        diffText = await chat.diff(message)
                        diffOpen = true
                    }
                }
                LButton(title: "Закоммитить", icon: "checkmark.circle", kind: .primary, size: .sm) { act { await chat.commit(message) } }
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
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(p.background)
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
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(p.mutedFg) }
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
