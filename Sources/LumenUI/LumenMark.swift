import SwiftUI

/// Знак Люмена — затмение (lumen-theme.css, `.ec`): чёрная Луна, жемчужная корона, на краю — «бриллиант».
/// Большой (приветствие, 78): корона с лучами; «горячий» (поле в фокусе или в нём текст) — на краю мерцает «бриллиант».
/// Малый (рядом с ответом, 24): только корона, Луна и свет по краю; «думает» — свет бежит по кругу, пока нет первого токена.
/// Луна чёрная в обеих темах; корона в светлой нарисована тушью. Слои — Core Animation (Layers.swift).
struct LumenMark: View {
    enum State { case idle, thinking, writing, remember, sleep }

    var state: State = .idle
    var size: CGFloat = 28
    /// Знаки в старых сообщениях стоят: свет бежит только у живого
    var animated = true
    /// Поле ввода в фокусе или в нём уже есть текст
    var hot = false

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    /// Меньше 40 pt — малый знак: детали сводятся к главному
    static func isSmall(_ size: CGFloat) -> Bool { size < 40 }

    var body: some View {
        let small = Self.isSmall(size)
        EclipseLayers(look: EclipseLayers.Look(size: size, small: small, hot: !small && hot,
                                               think: small && animated && state == .thinking,
                                               light: p.isLight, tint: p.markTint, instant: lessMotion))
            .frame(width: size, height: size)
            .opacity(state == .sleep ? 0.7 : 1)
            .overlay { Ring(active: state == .remember, size: size).environment(\.palette, p) }
            .accessibilityHidden(true)
    }
}

/// Кнопка «отправить», когда есть что отправить: маленький шар (radial 34%/28%, `--send-on-bg`);
/// на светлой — #7F9DFF → #3D66F0 → #2546C9
struct MiniOrbFill: View {
    @Environment(\.palette) private var p

    var body: some View {
        let c: [Color] = p.isLight && p.orbSpec ? [Color(hex: 0x7F9DFF), Color(hex: 0x3D66F0), Color(hex: 0x2546C9)]
            : (p.orbSpec ? [Color(hex: 0xA9C0FF), Color(hex: 0x5179F6), Color(hex: 0x2643CC)]
               : [p.glowSoftBase.mixed(with: .white, 0.45), p.glowSoftBase, p.glowSoftBase.mixed(with: .black, 0.35)])
        let at: [Double] = p.isLight && p.orbSpec ? [0, 0.45, 1] : [0, 0.42, 1]
        GeometryReader { g in
            let s = g.size.width
            // farthest-corner от точки (34%, 28%) — до правого нижнего угла
            let r = s * sqrt(0.66 * 0.66 + 0.72 * 0.72)
            Circle().fill(RadialGradient(stops: [.init(color: c[0], location: at[0]), .init(color: c[1], location: at[1]), .init(color: c[2], location: at[2])],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: r))
                .overlay(alignment: .top) {
                    // inset 0 1px 0 rgba(255,255,255,.25): светлая кромка сверху
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12)), lineWidth: 1)
                }
        }
    }
}

/// `.orb-ring`: кольцо света «запомнил» — расходится 0.8 → 2.2 за 1,1 с, вместе со вспышкой
private struct Ring: View {
    let active: Bool
    let size: CGFloat

    @Environment(\.palette) private var p
    @State private var go = false

    var body: some View {
        Circle()
            .strokeBorder(p.glow, lineWidth: 1)
            .frame(width: size * 1.4, height: size * 1.4)
            .scaleEffect(go ? 2.2 : 0.8)
            .opacity(go ? 0 : (active ? 0.9 : 0))
            .allowsHitTesting(false)
            .onChange(of: active) { _, on in
                guard on else { return }
                go = false
                withAnimation(.easeOut(duration: 1.1)) { go = true }
            }
    }
}
