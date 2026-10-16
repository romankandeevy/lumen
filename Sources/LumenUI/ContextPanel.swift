import LumenCore
import SwiftUI

/// Правая панель «Контекст» (`ContextPanel` в макете): сессия агента, память в ответе, окно контекста, расход.
/// «Характер» появится, когда заработает.
struct ContextPanel: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @Environment(\.windowWidth) private var windowWidth

    private var chat: ChatController { app.chat }
    private var conversation: Conversation? { chat.conversation }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let plan = conversation?.plan, !plan.isEmpty {
                    Side(title: "План") { PlanList(items: plan) }
                }
                if conversation?.kind == .agent, let folder = conversation?.folder {
                    Side(title: "Сессия") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label { Text(folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle) }
                                icon: { Icon("folder", 16).foregroundStyle(p.glow) }
                            IconLabel(text: "Этот Мак", icon: "laptop").foregroundStyle(p.mutedFg)
                            IconLabel(text: "push и выкатка — только с твоего OK", icon: "lock").foregroundStyle(p.mutedFg)
                        }
                        .font(.geist(14))
                    }
                }
                Side(title: "Память в этом ответе", link: ("Вся память", { app.page = .memory })) {
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
                }
                Side(title: "Окно контекста") {
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
                        .disabled(chat.running != nil)
                        .help("Старые сообщения пересказываются, место в окне освобождается")
                        .padding(.top, 12)
                    }
                }
                Side(title: "Расход", link: ("Модели и оплата", { app.page = .settings(.models) })) {
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
                }
            }
        }
        .scrollIndicators(.never)
        .frame(width: CGFloat(ResizeHandle.clamp(app.prefs.panelWidth, min: 280, window: Double(windowWidth))))
        .background(p.sidebar.opacity(0.5))
        .overlay(alignment: .leading) { p.border.frame(width: 1) }
        .overlay(alignment: .leading) {
            ResizeHandle(side: .leading, width: $app.prefs.panelWidth, minWidth: 280) { app.update { _ in } }.offset(x: -4)
        }
        .foregroundStyle(p.foreground)
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
