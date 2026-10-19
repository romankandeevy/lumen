import AppKit
import LumenCore
import LumenProviders
import SwiftUI

/// Правые панели: ширина фиксированная, только подстраивается под окно (мышью не тянется)
enum RightPanel {
    static func width(_ window: CGFloat) -> CGFloat { min(320, max(260, window * 0.3)) }
}

/// Правая панель «Контекст» (`ContextPanel` в макете): сессия агента, память в ответе, окно контекста, расход.
/// «Характер» появится, когда заработает.
struct ContextPanel: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @Environment(\.windowWidth) private var windowWidth

    private var chat: ChatController { app.chat }
    private var conversation: Conversation? { chat.conversation }

    /// Блоки панели и их названия
    static let names = ["plan": "План", "session": "Сессия", "log": "Журнал Claude Code", "memory": "Память в ответе", "context": "Окно контекста", "usage": "Расход"]

    /// Какие блоки сейчас есть (план и сессия — только у агента с планом / в папке)
    private var available: [String] {
        var all = app.prefs.panelOrder
        for id in ["plan", "session", "log", "memory", "context", "usage"] where !all.contains(id) {
            // журнал — сразу после сессии: его смотрят, когда ход идёт
            if id == "log", let i = all.firstIndex(of: "session") { all.insert(id, at: i + 1) } else { all.append(id) }
        }
        return all.filter { id in
            switch id {
            case "plan": !(conversation?.plan.isEmpty ?? true)
            case "session": conversation?.kind == .agent && conversation?.folder != nil
            case "log": conversation?.usesCLI == true
            default: true
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(available.filter { !app.prefs.panelHidden.contains($0) }, id: \.self) { id in
                    PanelBlock(app: app, id: id, title: Self.names[id] ?? id, link: link(id)) { content(id) }
                }
                let hidden = available.filter { app.prefs.panelHidden.contains($0) }
                if !hidden.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Вернуть блок").font(.geist(11, .medium)).foregroundStyle(p.mutedFg)
                        FlowWrap(spacing: 6) {
                            ForEach(hidden, id: \.self) { id in
                                Button { app.update { $0.panelHidden.removeAll { $0 == id } } } label: {
                                    IconLabel(text: Self.names[id] ?? id, icon: "plus", size: 11).font(.geist(12))
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(p.foreground.opacity(0.05), in: Capsule())
                                        .overlay(Capsule().strokeBorder(p.border))
                                }
                                .buttonStyle(.plain).foregroundStyle(p.mutedFg)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4).padding(.top, 4)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.never)
        .frame(width: RightPanel.width(windowWidth))
        // тот же цвет, что у основной области, и тонкая линия слева (Рома, 19.10)
        .background(p.background)
        .overlay(alignment: .leading) { p.border.frame(width: 1).ignoresSafeArea() }
        .foregroundStyle(p.foreground)
    }

    private func link(_ id: String) -> (String, () -> Void)? {
        switch id {
        case "memory": ("Вся память", { app.page = .memory })
        case "usage": ("Модели и оплата", { app.page = .settings(.models) })
        default: nil
        }
    }

    @ViewBuilder private func content(_ id: String) -> some View {
        switch id {
        case "plan":
            if let plan = conversation?.plan { PlanList(items: plan) }
        case "session":
            if let folder = conversation?.folder {
                VStack(alignment: .leading, spacing: 8) {
                    Label { Text(folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle) }
                        icon: { Icon("folder", 16).foregroundStyle(p.glow) }
                    IconLabel(text: "Этот Мак", icon: "laptop").foregroundStyle(p.mutedFg)
                    IconLabel(text: "push и выкатка — только с твоего OK", icon: "lock").foregroundStyle(p.mutedFg)
                }
                .font(.geist(14))
            }
        case "log":
            ClaudeLogView(chat: chat)
        case "memory":
            if used.isEmpty {
                Text("В последнем ответе Lumen не опирался на память.").font(.geist(12)).foregroundStyle(p.mutedFg)
            } else {
                VStack(spacing: 8) {
                    ForEach(used) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.text).font(.geist(13)).fixedSize(horizontal: false, vertical: true)
                            Text(f.source == "Знакомство" ? "из знакомства, \(RelativeWhen.string(f.createdAt))"
                                                          : "из «\(f.source)», \(RelativeWhen.string(f.createdAt))")
                                .font(.geist(11)).foregroundStyle(p.mutedFg)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.glow.opacity(0.03), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.glow.opacity(0.15)))
                    }
                }
            }
        case "context":
            VStack(alignment: .leading, spacing: 0) {
                if let ctx = chat.lastContext {
                    HStack(spacing: 16) {
                        ContextRing(used: ctx.used, window: ctx.window)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Tokens.short(ctx.used)) из \(Tokens.short(ctx.window))").font(.geist(14, .medium)).monospacedDigit()
                            Legend(color: p.glow, label: "занято", value: Tokens.short(ctx.used))
                            Legend(color: p.muted, label: "свободно", value: Tokens.short(max(0, ctx.window - ctx.used)))
                        }
                    }
                } else {
                    Text("Появится после первого ответа.").font(.geist(12)).foregroundStyle(p.mutedFg)
                }
                if conversation?.usesCLI == true, chat.lastContext != nil {
                    Button { chat.compact() } label: {
                        IconLabel(text: "Сжать разговор", icon: "rotate-ccw", size: 14).font(.geist(12))
                    }
                    .buttonStyle(.plain).foregroundStyle(p.mutedFg)
                    .disabled(chat.busy)
                    .help("Старые сообщения пересказываются, место в окне освобождается")
                    .padding(.top, 12)
                }
            }
        case "usage":
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(app.usage.prefix(2).enumerated()), id: \.offset) { _, w in
                    Meter(label: w.kind == .session ? "Подписка, 5 часов" : "Подписка, неделя", value: w.percent,
                          note: SubscriptionCard.resetNote(w.resetsAt))
                }
                if app.savedKeyTail != nil || app.apiSpentThisMonth > 0 {
                    Meter(label: "API в этом месяце", value: Int(app.apiSpentThisMonth / Double(max(1, app.prefs.monthlyLimit)) * 100),
                          note: "$\(Money.string(app.apiSpentThisMonth)) из $\(app.prefs.monthlyLimit)")
                }
                if app.usage.isEmpty && app.savedKeyTail == nil {
                    Text("Лимиты подписки появятся после входа в Claude Code.").font(.geist(12)).foregroundStyle(p.mutedFg)
                }
            }
        default:
            EmptyView()
        }
    }

    /// Факты последнего ответа: вспомненные и запомненные
    private var used: [MemoryFact] {
        guard let m = chat.messages.last(where: { $0.role == .assistant && $0.note == nil }) else { return [] }
        return (m.recalled + m.remembered).compactMap { app.memory($0) }
    }
}

/// Раздел панели (`Side`): border-b px-4 py-4, заголовок text-[13px] medium, ссылка справа
struct Side<Content: View>: View {
    let title: String
    var link: (String, () -> Void)?
    @ViewBuilder let content: Content

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.geist(13, .medium)).foregroundStyle(p.foreground.opacity(0.9))
                Spacer()
                if let link {
                    Button(link.0, action: link.1).buttonStyle(.plain).font(.geist(12))
                        .foregroundStyle(hover ? p.glow : p.mutedFg).onHover { hover = $0 }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }
}

/// Кольцо занятого контекста (`ContextRing`): 76×76, толщина 7, процент в центре
struct ContextRing: View {
    let used: Int
    let window: Int

    @Environment(\.palette) private var p

    private var share: Double { window > 0 ? min(1, Double(used) / Double(window)) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(p.muted, lineWidth: 7)
            Circle().trim(from: 0, to: share).stroke(p.glow, style: StrokeStyle(lineWidth: 7))
                .rotationEffect(.degrees(-90))
            Text("\(Int((share * 100).rounded()))%").font(.geist(13, .semibold)).monospacedDigit()
        }
        .frame(width: 60, height: 60)
        .padding(8)
    }
}

struct Legend: View {
    let color: Color
    let label: String
    let value: String

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(p.mutedFg)
            Text(value).monospacedDigit()
        }
        .font(.geist(12))
    }
}

enum Tokens {
    /// «47 тыс.», «1 млн»
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return (n % 1_000_000 == 0 ? "\(n / 1_000_000)" : String(format: "%.1f", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",")) + " млн" }
        if n >= 1000 { return "\(Int((Double(n) / 1000).rounded())) тыс." }
        return "\(n)"
    }
}

/// Блок правой панели, как в Claude: карточка; заголовок сворачивает, «×» убирает, тащи — переставишь
struct PanelBlock<Content: View>: View {
    @Bindable var app: AppModel
    let id: String
    let title: String
    var link: (String, () -> Void)?
    @ViewBuilder let content: Content

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var linkHover = false
    @State private var dropTarget = false

    private var collapsed: Bool { app.prefs.panelCollapsed.contains(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button {
                    // прочитать до правки: внутри app.update настройки заняты на запись — чтение там роняет приложение
                    let was = collapsed
                    withAnimation(.easeOut(duration: 0.15)) {
                        app.update { pr in if was { pr.panelCollapsed.removeAll { $0 == id } } else { pr.panelCollapsed.append(id) } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title).font(.geist(13, .medium)).foregroundStyle(p.foreground.opacity(0.9))
                        Icon("chevron-down", 12).foregroundStyle(p.mutedFg).rotationEffect(.degrees(collapsed ? -90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let link, !collapsed {
                    Button(link.0, action: link.1).buttonStyle(.plain).font(.geist(12))
                        .foregroundStyle(linkHover ? p.glow : p.mutedFg).onHover { linkHover = $0 }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { app.update { $0.panelHidden.append(id) } }
                } label: {
                    Icon("x", 12).foregroundStyle(p.mutedFg).frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hover ? 1 : 0)
                .help("Убрать блок — вернуть можно внизу панели")
            }
            if !collapsed { content }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.55), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(dropTarget ? p.glow.opacity(0.5) : p.border))
        .onHover { hover = $0 }
        // перетащить блок: бросаешь на другой — встаёт перед ним
        .draggable(id) {
            Text(title).font(.geist(13, .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                .background(p.popover, in: RoundedRectangle(cornerRadius: R.lg))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first, moved != id, ContextPanel.names[moved] != nil else { return false }
            withAnimation(.easeOut(duration: 0.2)) {
                app.update { pr in
                    var order = pr.panelOrder
                    for x in ContextPanel.names.keys.sorted() where !order.contains(x) { order.append(x) }
                    order.removeAll { $0 == moved }
                    let at = order.firstIndex(of: id) ?? order.count
                    order.insert(moved, at: at)
                    pr.panelOrder = order
                }
            }
            return true
        } isTargeted: { dropTarget = $0 }
    }
}


/// «Журнал Claude Code»: что делает процесс claude, по секундам — думает, ждёт API, вызывает инструменты, ошибки.
/// Сверху — сколько он молчит, если ход идёт: видно, завис или работает.
struct ClaudeLogView: View {
    let chat: ChatController

    @Environment(\.palette) private var p
    @State private var all = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        let lines = chat.openLog
        VStack(alignment: .leading, spacing: 6) {
            if chat.busy {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let s = Int(chat.silence(now: ctx.date) ?? 0)
                    HStack(spacing: 6) {
                        LiveDot(color: s > 30 ? Palette.destructive : p.glow, size: 6)
                        Text(s < 3 ? "Работает" : "Молчит \(s) с — \(s > 90 ? "похоже, завис: «Стоп» и повторить" : "думает или ждёт ответа API")")
                            .font(.geist(12)).foregroundStyle(s > 30 ? Palette.destructive : p.mutedFg)
                    }
                }
            }
            if lines.isEmpty {
                Text("Появится, когда Claude Code начнёт работать.").font(.geist(12)).foregroundStyle(p.mutedFg)
            } else {
                let shown = all ? lines : Array(lines.suffix(40))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(shown) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Self.time.string(from: l.at)).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.mutedFg.opacity(0.7))
                            Text(l.text).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(l.kind))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                HStack(spacing: 12) {
                    if lines.count > 40 {
                        Button(all ? "Только последние" : "Весь журнал (\(lines.count))") { all.toggle() }
                    }
                    Button("Копировать") {
                        let text = lines.map { Self.time.string(from: $0.at) + "  " + $0.text }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                .buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
            }
        }
    }

    private func color(_ k: ClaudeLog.Line.Kind) -> Color {
        switch k {
        case .error: Palette.destructive
        case .done: p.glow
        case .think, .wait: p.mutedFg
        default: p.foreground.opacity(0.85)
        }
    }
}
