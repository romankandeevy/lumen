import SwiftUI

/// Знак Люмена — светящаяся сфера, точно как `.orb` в макете (`ui/src/index.css`).
/// Покой: медленно дышит (5,5 с) и плавает (9 с). Думает: дышит за 1,8 с.
/// Пишет: разгорается. Запомнил: вспышка и кольцо света. Спит: тускнеет.
struct Orb: View {
    enum State { case idle, thinking, writing, remember, sleep }

    var state: State = .idle
    var size: CGFloat = 28
    /// Сферы в старых сообщениях стоят: анимация 30 кадров в секунду на каждую — лишняя работа
    var animated = true

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: lessMotion || !animated)) { tl in
            let t = lessMotion || !animated ? 2.75 : tl.date.timeIntervalSinceReferenceDate
            ZStack {
                halo(t)
                body(t)
            }
            .frame(width: size, height: size)
        }
        .overlay { Ring(active: state == .remember, size: size).environment(\.palette, p) }
        .accessibilityHidden(true)
    }

    /// 0…1…0 по синусу с периодом
    private func wave(_ t: Double, _ period: Double) -> Double { (1 - cos(t / period * 2 * .pi)) / 2 }

    /// `.orb-halo`: inset −60% (90% когда пишет), radial glowSoft → прозрачно на 65%, дыхание 0.85…1.08
    private func halo(_ t: Double) -> some View {
        let extra: CGFloat = state == .writing ? 0.9 : 0.6
        let d = size * (1 + extra * 2)
        let period = state == .writing ? 0.9 : (state == .thinking ? 1.8 : 5.5)
        let w = wave(t, period)
        let scale = lessMotion ? 1 : 0.85 + 0.23 * w
        var opacity = lessMotion ? 0.8 : 0.55 + 0.45 * w
        if state == .sleep { opacity = 0.25 }
        // круг с farthest-corner: радиус до угла = d/2·√2, 65% от него
        return Circle()
            .fill(RadialGradient(colors: [p.glowSoft, .clear], center: .center, startRadius: 0, endRadius: d / 2 * 1.4142 * 0.65))
            .frame(width: d, height: d)
            .scaleEffect(state == .sleep ? 1 : scale)
            .opacity(opacity)
    }

    /// `.orb-body`: блик glow-core в 35%/30% до 45%, свечение glow в 50%/55% до 72%, тень 0 0 size/2 glowSoft
    private func body(_ t: Double) -> some View {
        let farA = size * sqrt(0.65 * 0.65 + 0.7 * 0.7)   // от 35%/30% до дальнего угла
        let farB = size * sqrt(0.5 * 0.5 + 0.55 * 0.55)   // от 50%/55% до дальнего угла
        let think = state == .thinking ? wave(t, 1.8) : 0
        let drift = state == .idle || state == .writing ? wave(t, 9) : 0
        return ZStack {
            Circle().fill(RadialGradient(stops: [
                .init(color: p.glow, location: 0),
                .init(color: p.glow.opacity(0.4), location: 0.55),
                .init(color: .clear, location: 0.72),
            ], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: farB))
            Circle().fill(RadialGradient(stops: [
                .init(color: p.glowCore, location: 0),
                .init(color: .clear, location: 0.45),
            ], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: farA))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: p.glowSoft, radius: size * 0.25)
        .offset(x: size * 0.015 * drift, y: -size * 0.02 * drift)
        .scaleEffect(state == .thinking && !lessMotion ? 0.9 + 0.14 * think : 1)
        .brightness(state == .writing ? 0.08 : (state == .thinking ? -0.05 + 0.15 * think : 0))
        .saturation(state == .sleep ? 0.4 : 1)
        .opacity(state == .sleep ? 0.7 : 1)
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
