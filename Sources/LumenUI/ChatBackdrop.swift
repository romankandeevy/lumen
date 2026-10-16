import SwiftUI

/// Живой фон чата: тёплый свет Люмена медленно перетекает по окну, как северное сияние под стеклом.
/// Сетка градиентов 4×4 (считает видеокарта, один слой — дёшево). Отзывается на сферу:
/// думает — течёт быстрее и ярче, пишет — светится сильнее всего, запоминает — короткая вспышка.
/// В покое 20 кадров в секунду, во время ответа 30, при «Меньше движения» стоит на месте.
struct ChatBackdrop: View {
    var state: Orb.State = .idle

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion
    /// Плавный переход яркости между состояниями
    @State private var level: Double = 1

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                TimelineView(.animation(minimumInterval: state == .idle ? 1 / 20 : 1 / 30, paused: lessMotion)) { tl in
                    Mesh(t: lessMotion ? 40 : tl.date.timeIntervalSinceReferenceDate,
                         speed: speed, level: level, p: p)
                }
            } else {
                LumenLight(level: 1.2 + level * 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { level = target }
        .onChange(of: state) { withAnimation(.easeInOut(duration: 1.4)) { level = target } }
    }

    private var target: Double {
        switch state {
        case .thinking: 1.5
        case .writing: 1.8
        case .remember: 1.7
        default: 1
        }
    }

    private var speed: Double {
        switch state {
        case .thinking: 2.2
        case .writing: 1.5
        default: 1
        }
    }
}

@available(macOS 15.0, *)
private struct Mesh: View, Animatable {
    var t: Double
    var speed: Double
    var level: Double
    let p: Palette

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        // фаза бежит со скоростью состояния; смена скорости не даёт рывка — время просто течёт быстрее
        let ph = t * speed
        func w(_ phase: Double, _ amp: Double, _ period: Double) -> Float {
            Float(sin(ph * 2 * .pi / period + phase) * amp)
        }
        // края закреплены, внутренние узлы плавают
        let pts: [SIMD2<Float>] = [
            [0, 0], [0.33 + w(0, 0.08, 23), 0], [0.66 + w(1, 0.08, 29), 0], [1, 0],
            [0, 0.33 + w(2, 0.1, 31)], [0.33 + w(0.5, 0.14, 19), 0.33 + w(1.7, 0.12, 27)],
            [0.66 + w(2.4, 0.13, 21), 0.33 + w(0.3, 0.14, 25)], [1, 0.33 + w(1.1, 0.1, 33)],
            [0, 0.66 + w(3.0, 0.1, 28)], [0.33 + w(1.9, 0.13, 24), 0.66 + w(2.8, 0.12, 20)],
            [0.66 + w(0.9, 0.14, 26), 0.66 + w(2.2, 0.13, 22)], [1, 0.66 + w(0.4, 0.1, 30)],
            [0, 1], [0.33 + w(2.6, 0.08, 27), 1], [0.66 + w(1.4, 0.08, 25), 1], [1, 1],
        ]
        // пятна света «дышат» вразнобой: каждое со своим периодом
        func glow(_ phase: Double, _ period: Double, _ peak: Double) -> Color {
            let breathe = 0.55 + 0.45 * (sin(ph * 2 * .pi / period + phase) + 1) / 2
            let a = min(0.5, peak * level * breathe * (p.isMono ? 0.55 : 1))
            return p.glowSoftBase.opacity(a).over(p.background)
        }
        let deep = p.glowSoftBase.opacity(0.03 * level).over(p.background)
        let colors: [Color] = [
            glow(0, 11, 0.20), glow(1.2, 13, 0.10), deep, glow(2.1, 17, 0.08),
            glow(0.7, 15, 0.09), glow(2.5, 9, 0.17), glow(4.0, 12, 0.07), deep,
            deep, glow(3.3, 14, 0.06), glow(1.6, 10, 0.15), glow(5.0, 16, 0.09),
            glow(2.9, 18, 0.05), deep, glow(0.4, 13, 0.07), p.background,
        ]
        return MeshGradient(width: 4, height: 4, points: pts, colors: colors, smoothsColors: true)
    }
}

private extension Color {
    /// Полупрозрачный цвет поверх непрозрачного: сетка градиентов плавнее с готовыми цветами
    func over(_ base: Color) -> Color {
        let top = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let bottom = NSColor(base).usingColorSpace(.sRGB) ?? .black
        let a = top.alphaComponent
        return Color(.sRGB,
                     red: Double(top.redComponent * a + bottom.redComponent * (1 - a)),
                     green: Double(top.greenComponent * a + bottom.greenComponent * (1 - a)),
                     blue: Double(top.blueComponent * a + bottom.blueComponent * (1 - a)))
    }
}
