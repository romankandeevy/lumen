import SwiftUI

/// Настройки — панель поверх главного окна, как в Claude (Рома, 25.10): окно под ней приглушено и чуть размыто,
/// чат остаётся на месте. Закрывается крестиком, Esc, ⌘W или щелчком мимо панели.
struct SettingsSheet: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        GeometryReader { g in
            ZStack {
                // подложка: приглушает окно; щелчок по ней закрывает
                Rectangle()
                    .fill(.black.opacity(p.isLight ? 0.18 : 0.42))
                    .background(.ultraThinMaterial.opacity(0.6))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { app.closeSettings() }
                    .transition(.opacity)

                SettingsView(app: app, inSheet: true)
                    .frame(width: min(1120, g.size.width - 96), height: min(780, g.size.height - 72))
                    .background(p.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.border))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        IconButton(icon: "x", help: "Закрыть · Esc", side: 32, iconSize: 17) { app.closeSettings() }
                            .padding(14)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
                    .transition(lessMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onExitCommand { app.closeSettings() }
        .background {
            Button("") { app.closeSettings() }.keyboardShortcut("w", modifiers: .command).opacity(0)
        }
    }
}
