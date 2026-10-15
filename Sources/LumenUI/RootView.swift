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
            SettingsView(app: app)
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
        .environment(\.palette, p)
        .environment(\.lessMotion, app.prefs.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .preferredColorScheme(.dark)
        .tint(p.glow)
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// Боковая панель (`App.tsx`): сверху знак, внизу разделы и карточка профиля.
/// Чат, Агент, Боты и остальные разделы появятся здесь, когда заработают.
struct Sidebar: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Orb(state: app.orb, size: 18)
                Text("Lumen").font(.geist(14, .semibold))
            }
            .padding(.horizontal, 16).padding(.top, 40)

            Spacer()

            Label { Text("Настройки").font(.geist(13.5)) } icon: { Image(systemName: "gearshape").font(.system(size: 13)) }
                .padding(.horizontal, 10).frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.sidebarAccent, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)

            profile.padding(8)
        }
        .foregroundStyle(p.foreground)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        // панель чуть темнее окна, но прозрачная: свет Люмена проходит сквозь неё
        .background(p.sidebar.opacity(0.45).ignoresSafeArea())
        .overlay(alignment: .trailing) { p.sidebarBorder.frame(width: 1).ignoresSafeArea() }
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
