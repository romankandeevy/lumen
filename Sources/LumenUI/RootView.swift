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
                case .settings: SettingsView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // свет и фон — одни на всё окно: панель и содержимое переходят друг в друга без ступеньки,
        // и под скрытым заголовком окна нет тёмной полосы
        .background(LumenLight().ignoresSafeArea())
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

/// Боковая панель (`App.tsx`): знак и «новый чат», список разговоров, внизу настройки и профиль.
/// Агент, Боты, Память и остальные разделы появятся здесь, когда заработают.
struct Sidebar: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Orb(state: app.orb, size: 18)
                Text("Lumen").font(.geist(14, .semibold))
                Spacer()
                IconButton(icon: "square.and.pencil", help: "Новый чат · ⌘N") { app.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.top, 40)

            Button { app.newChat() } label: {
                Label { Text("Новый чат").font(.geist(13.5)) } icon: { Image(systemName: "plus").font(.system(size: 12)) }
                    .padding(.horizontal, 10).frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.0) { name, items in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.geist(11.5)).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.bottom, 4)
                            ForEach(items) { c in ChatRow(app: app, c: c) }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 14)
            }
            .scrollIndicators(.never)

            VStack(spacing: 2) {
                NavRow(title: "Настройки", icon: "gearshape", active: { if case .settings = app.page { true } else { false } }()) {
                    app.page = .settings(.look)
                }
            }
            .padding(.horizontal, 8).padding(.top, 6)
            .overlay(alignment: .top) { p.sidebarBorder.frame(height: 1) }

            Button { app.page = .settings(.models) } label: { profile }
                .buttonStyle(.plain)
                .padding(8)
        }
        .foregroundStyle(p.foreground)
        .frame(width: 256)
        .frame(maxHeight: .infinity)
        // панель чуть темнее окна, но прозрачная: свет Люмена проходит сквозь неё
        .background(p.sidebar.opacity(0.45).ignoresSafeArea())
        .overlay(alignment: .trailing) { p.sidebarBorder.frame(width: 1).ignoresSafeArea() }
    }

    /// «Сегодня» и «Раньше», как в макете
    private var groups: [(String, [Conversation])] {
        let today = app.conversations.filter { Calendar.current.isDateInToday($0.updatedAt) }
        let earlier = app.conversations.filter { !Calendar.current.isDateInToday($0.updatedAt) }
        return [("Сегодня", today), ("Раньше", earlier)].filter { !$0.1.isEmpty }
    }

    private var profile: some View {
        HStack(spacing: 10) {
            Text(String(app.profile.name.prefix(1)).uppercased())
                .font(.geist(12, .semibold))
                .frame(width: 30, height: 30)
                .background(p.secondary, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(app.profile.name.isEmpty ? "Без имени" : app.profile.name).font(.geist(13.5, .medium))
                Text(plan).font(.geist(11.5)).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(p.foreground.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
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

/// Строка разговора: заголовок и время, активная — со световой чертой слева
struct ChatRow: View {
    @Bindable var app: AppModel
    let c: Conversation

    @Environment(\.palette) private var p
    @State private var hover = false

    private var active: Bool { app.page == .chat && app.chat.conversation?.id == c.id }

    var body: some View {
        Button { app.openChat(c) } label: {
            HStack(spacing: 8) {
                Text(c.title).font(.geist(13.5)).lineLimit(1)
                    .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                Spacer(minLength: 4)
                Text(when).font(.geist(11)).foregroundStyle(p.mutedFg)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.04) : .clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if active { Capsule().fill(p.glow).frame(width: 2).padding(.vertical, 7).shadow(color: p.glow, radius: 5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Удалить разговор", role: .destructive) { app.deleteChat(c) }
        }
    }

    private var when: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(c.updatedAt) ? "HH:mm" : "d MMM"
        return f.string(from: c.updatedAt)
    }
}

/// Пункт нижнего меню панели
struct NavRow: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label { Text(title).font(.geist(13.5)) } icon: { Image(systemName: icon).font(.system(size: 13)) }
                .padding(.horizontal, 10).frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(active ? p.sidebarAccent : (hover ? p.foreground.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Маленькая кнопка-иконка
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(hover ? p.foreground : p.mutedFg)
                .frame(width: 28, height: 28)
                .background(hover ? p.foreground.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
