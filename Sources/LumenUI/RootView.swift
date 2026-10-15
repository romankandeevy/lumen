import LumenCore
import SwiftUI

/// Окно Lumen: боковая панель и содержимое. Знакомство — поверх, при первом запуске.
public struct RootView: View {
    @Bindable var app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        let p = Palette.of(app.prefs.theme)
        HStack(spacing: 0) {
            Sidebar(app: app)
            Group {
                switch app.page {
                case .chat: ChatView(app: app)
                case .memory: MemoryView(app: app)
                case .settings: SettingsView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // `.lumen-light` на всём окне: панель полупрозрачная, свет проходит сквозь неё
        .background(LumenLight(level: app.orb == .thinking ? 1.9 : 1).ignoresSafeArea())
        .overlay {
            if !app.prefs.onboarded {
                OnboardingView(app: app).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.prefs.onboarded)
        .background(p.background.ignoresSafeArea())
        // чат по подписке должен знать, где claude и есть ли вход
        .task { if app.claude == .checking { await app.refreshClaude() } }
        .environment(\.palette, p)
        .environment(\.lessMotion, app.prefs.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .preferredColorScheme(.dark)
        .tint(p.glow)
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// Боковая панель (`Shell` в App.tsx): знак, список, внизу разделы и профиль.
/// Вкладки, поиск и разделы, которые ещё не работают, не показываем.
struct Sidebar: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // место под кнопки окна macOS — в браузерном макете их нет
            Color.clear.frame(height: 28)
            HStack(spacing: 10) {
                Orb(state: app.orb, size: 22)
                Text("Lumen").font(.geist(15, .semibold)).tracking(-0.15)
                Spacer()
                IconButton(icon: "square.and.pencil", help: "Новый чат · ⌘N") { app.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            TabSwitch(app: app).padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if app.tab == .chat {
                        NewButton(title: "Новый чат") { app.newChat() }
                            .padding(.bottom, 12)
                        ForEach(groups, id: \.0) { name, items in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(name).font(.geist(12)).foregroundStyle(p.mutedFg)
                                    .padding(.horizontal, 10).padding(.bottom, 4)
                                ForEach(items) { c in ChatRow(app: app, c: c) }
                            }
                            .padding(.bottom, 12)
                        }
                    } else {
                        NewButton(title: "Новая задача") { app.newAgentTask() }
                            .padding(.bottom, 12)
                        if !sessions.isEmpty {
                            Text("Сессии").font(.geist(12)).foregroundStyle(p.mutedFg)
                                .padding(.horizontal, 10).padding(.bottom, 4)
                            ForEach(sessions) { c in ChatRow(app: app, c: c) }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            VStack(spacing: 2) {
                NavRow(title: "Память", icon: "brain", active: app.page == .memory, trailing: "\(app.memoryCount)") {
                    app.page = .memory
                }
                NavRow(title: "Настройки", icon: "gearshape", active: { if case .settings = app.page { true } else { false } }()) {
                    app.page = .settings(.look)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .top) { p.border.frame(height: 1) }

            Button { app.page = .settings(.models) } label: { profile }
                .buttonStyle(.plain)
                .padding([.horizontal, .bottom], 12)
        }
        .foregroundStyle(p.foreground)
        .frame(width: 256)
        .frame(maxHeight: .infinity)
        // bg-sidebar/70 + backdrop-blur-sm
        .background(p.sidebar.opacity(0.7).ignoresSafeArea())
        .overlay(alignment: .trailing) { p.border.frame(width: 1).ignoresSafeArea() }
    }

    private var sessions: [Conversation] { app.conversations.filter { $0.kind == .agent } }

    /// «Сегодня» и «Раньше», как в макете
    private var groups: [(String, [Conversation])] {
        let chats = app.conversations.filter { $0.kind == .chat }
        let today = chats.filter { Calendar.current.isDateInToday($0.updatedAt) }
        let earlier = chats.filter { !Calendar.current.isDateInToday($0.updatedAt) }
        return [("Сегодня", today), ("Раньше", earlier)].filter { !$0.1.isEmpty }
    }

    private var profile: some View {
        ProfileCard(name: app.profile.name, plan: plan)
    }

    private var plan: String {
        switch app.prefs.backend {
        case .api: return "Anthropic API · ключ"
        case .subscription:
            if case .signedIn(_, let a) = app.claude { return "Claude \(a.planName ?? "") · подписка" }
            return "Claude Code · подписка"
        }
    }
}

/// Карточка профиля внизу панели: m-3 rounded-xl border bg-card/40 px-2.5 py-2
struct ProfileCard: View {
    let name: String
    let plan: String

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(String(name.prefix(1)).uppercased())
                .font(.geist(12, .medium))
                .frame(width: 28, height: 28)
                .background(p.foreground.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(name.isEmpty ? "Без имени" : name).font(.geist(14)).lineLimit(1)
                Text(plan).font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hover ? p.card : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Две вкладки, как Chat / Code в Claude (`tablist` в макете): mx-3 rounded-xl bg-foreground/[0.05] p-0.5.
/// «Боты» появятся, когда заработают.
struct TabSwitch: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 2) {
            tab(.chat, "Чат", "message")
            tab(.agent, "Агент", "terminal")
        }
        .padding(2)
        .background(p.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
    }

    private func tab(_ t: AppModel.Tab, _ name: String, _ icon: String) -> some View {
        let active = app.tab == t
        return Button {
            guard app.tab != t else { return }
            app.tab = t
            // открыть последний разговор этой вкладки или пустой
            if let last = app.conversations.first(where: { $0.kind == (t == .agent ? .agent : .chat) }) {
                app.openChat(last)
            } else {
                app.chat.startNew()
                app.page = .chat
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(active ? p.glow : p.mutedFg)
                Text(name).font(.geist(13))
            }
            .foregroundStyle(active ? p.foreground : p.mutedFg)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(active ? p.background : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? p.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// «+ Новый чат»: h-8 rounded-lg bg-foreground/[0.06] px-2.5 text-sm
struct NewButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14))
                Text(title).font(.geist(14))
            }
            .padding(.horizontal, 10).frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.foreground.opacity(hover ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: R.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Строка разговора (`Row`): px-2.5 py-1.5 text-sm text-foreground/80, активная — bg-foreground/[0.07] и световая черта
struct ChatRow: View {
    @Bindable var app: AppModel
    let c: Conversation

    @Environment(\.palette) private var p
    @State private var hover = false

    private var active: Bool { app.page == .chat && app.chat.conversation?.id == c.id }
    private var running: Bool { app.chat.conversation?.id == c.id && app.chat.busy }

    var body: some View {
        Button { app.openChat(c) } label: {
            HStack(alignment: c.kind == .agent ? .top : .center, spacing: 8) {
                if c.kind == .agent {
                    // как в макете: ноутбук (на этом Маке) или крутилка, пока работает
                    Group {
                        if running { ProgressView().controlSize(.mini).tint(p.glow) } else { Image(systemName: "laptopcomputer").font(.system(size: 12)) }
                    }
                    .foregroundStyle(p.mutedFg).frame(width: 20, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(.geist(14)).lineLimit(1)
                            .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                        Text(URL(fileURLWithPath: c.folder ?? "").lastPathComponent).font(.geist(11)).foregroundStyle(p.mutedFg).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(when).font(.geist(11)).foregroundStyle(p.mutedFg)
                } else {
                    Text(c.title).font(.geist(14)).lineLimit(1)
                        .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                    Spacer(minLength: 4)
                    if running {
                        ProgressView().controlSize(.mini).tint(p.glow)
                    } else {
                        Text(when).font(.geist(11)).foregroundStyle(p.mutedFg)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) {
                if active { GlowBar() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Удалить разговор", role: .destructive) { app.deleteChat(c) }
        }
    }

    /// «сейчас», «2 ч», «12 окт» — как в макете
    private var when: String { RelativeWhen.string(c.updatedAt) }
}

enum RelativeWhen {
    static func string(_ d: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "сейчас" }
        if s < 3600 { return "\(Int(s / 60)) мин" }
        if Calendar.current.isDateInToday(d) { return "\(Int(s / 3600)) ч" }
        if Calendar.current.isDateInYesterday(d) { return "вчера" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// Световая черта слева у активного пункта: top-1.5 bottom-1.5 w-[2px] bg-glow, свечение 10px
struct GlowBar: View {
    @Environment(\.palette) private var p

    var body: some View {
        Capsule().fill(p.glow).frame(width: 2).padding(.vertical, 6).shadow(color: p.glow, radius: 5)
    }
}

/// Пункт нижнего меню (`NavItem`): h-8 gap-2.5 px-2.5 text-sm text-foreground/75
struct NavRow: View {
    let title: String
    let icon: String
    let active: Bool
    var trailing: String?
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(active ? p.glow : p.mutedFg).frame(width: 16)
                Text(title).font(.geist(14))
                Spacer(minLength: 0)
                if let trailing { Text(trailing).font(.geist(12)).foregroundStyle(p.mutedFg).monospacedDigit() }
            }
            .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.75))
            .padding(.horizontal, 10).frame(height: 32)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) { if active { GlowBar() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Кнопка-иконка 28×28 rounded-lg, иконка 16, приглушённая
struct IconButton: View {
    let icon: String
    let help: String
    var active = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(hover || active ? p.foreground : p.mutedFg)
                .frame(width: 28, height: 28)
                .background(active ? p.secondary : (hover ? p.foreground.opacity(0.05) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
