import SwiftUI

/// Знак Люмена — стеклянный шар (макет 21.10, `.orb`): три радиальных градиента (тело, отсвет снизу, блик),
/// тень внутри снизу справа, светлая кромка сверху слева, тонкое кольцо и свечение под шаром.
/// Размеры макета: 78 — приветствие, 26 — рядом с ответом, 20 — в шапке; остальные считаются от них.
/// «Горячий» (поле в фокусе или в нём текст) — ярче и светится сильнее. Думает — дышит (1,6 с). Спит — тускнеет.
struct Orb: View {
    enum State { case idle, thinking, writing, remember, sleep }

    var state: State = .idle
    var size: CGFloat = 28
    /// Сферы в старых сообщениях стоят: дыхание только у живой
    var animated = true
    /// Поле ввода в фокусе или в нём уже есть текст
    var hot = false
    /// Ореол за шаром приветствия: 0…1 (nil — без ореола)
    var halo: Double?
    /// Свечение под шаром; у приветствия его нет (Рома, 21.10)
    var glow = true

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        // слои Core Animation (Layers.swift): анимацию крутит система, не наш процесс
        OrbLayers(look: OrbLayers.Look(state: state, size: size, breathing: animated && !lessMotion && state == .thinking,
                                       hot: hot || state == .writing, halo: halo, glow: glow, colors: p.orbColors, instant: lessMotion))
            .frame(width: size, height: size)
            .overlay { Ring(active: state == .remember, size: size).environment(\.palette, p) }
            .accessibilityHidden(true)
    }
}

/// Цвета шара: у «Люмена» — ровно из макета, у других тем — из их света
struct OrbColors: Equatable {
    var hi, mid, deep, deepest, rim, glow, ring: Color

    static let spec = OrbColors(
        hi: Color(hex: 0x86A7FF), mid: Color(hex: 0x4369F2), deep: Color(hex: 0x1D36AC), deepest: Color(hex: 0x0A1452),
        rim: Color(.sRGB, red: 130 / 255, green: 175 / 255, blue: 1, opacity: 0.55),
        glow: Color(.sRGB, red: 55 / 255, green: 95 / 255, blue: 1),
        ring: Color(.sRGB, red: 150 / 255, green: 175 / 255, blue: 1))
}

extension Palette {
    var orbColors: OrbColors {
        if orbSpec { return .spec }
        let c = glowSoftBase
        return OrbColors(hi: c.mixed(with: .white, 0.3), mid: c.mixed(with: .black, 0.15), deep: c.mixed(with: .black, 0.55),
                         deepest: c.mixed(with: .black, 0.85), rim: c.mixed(with: .white, 0.4).opacity(0.55),
                         glow: c.mixed(with: .black, 0.1), ring: c.mixed(with: .white, 0.45))
    }
}

/// Кнопка «отправить», когда есть что отправить: маленький шар (radial 34%/28%: #A9C0FF → #5179F6 → #2643CC)
struct MiniOrbFill: View {
    @Environment(\.palette) private var p

    var body: some View {
        let c = p.orbSpec ? [Color(hex: 0xA9C0FF), Color(hex: 0x5179F6), Color(hex: 0x2643CC)]
            : [p.glowSoftBase.mixed(with: .white, 0.45), p.glowSoftBase, p.glowSoftBase.mixed(with: .black, 0.35)]
        GeometryReader { g in
            let s = g.size.width
            // farthest-corner от точки (34%, 28%) — до правого нижнего угла
            let r = s * sqrt(0.66 * 0.66 + 0.72 * 0.72)
            Circle().fill(RadialGradient(stops: [.init(color: c[0], location: 0), .init(color: c[1], location: 0.42), .init(color: c[2], location: 1)],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: r))
                .overlay(alignment: .top) {
                    // inset 0 1px 0 rgba(255,255,255,.25): светлая кромка сверху
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12)), lineWidth: 1)
                }
        }
    }
}

/// `.orb-ring`: кольцо света «запомнил» — inset −20%, расходится 0.8 → 2.2 за 1,1 с, вместе со вспышкой
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
