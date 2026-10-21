import AppKit
import QuartzCore
import SwiftUI

// Долгие украшающие анимации — на Core Animation: их крутит системный сервер отрисовки, приложение
// в это время спит. SwiftUI TimelineView перерисовывает вид в нашем процессе каждый кадр:
// одна сфера в покое так стоила 11% процессора, на слоях — 0% (замер 16.10, MacBook).

private extension CABasicAnimation {
    /// Туда-обратно бесконечно, мягко
    static func wave(_ key: String, from: Double, to: Double, period: Double, phase: Double = 0) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = period / 2
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.timeOffset = phase * period
        a.isRemovedOnCompletion = false
        return a
    }
}

private func cg(_ c: Color) -> CGColor { NSColor(c).cgColor }

/// Радиальный градиент как в CSS: центр (x, y) в долях слоя сверху вниз, радиус — в долях стороны
private func radial(_ layer: CAGradientLayer, x: CGFloat, y: CGFloat, radius: CGFloat, stops: [(Color, Double)]) {
    layer.type = .radial
    layer.colors = stops.map { cg($0.0) }
    layer.locations = stops.map { NSNumber(value: $0.1) }
    // слои на macOS считают снизу вверх
    layer.startPoint = CGPoint(x: x, y: 1 - y)
    layer.endPoint = CGPoint(x: x + radius, y: 1 - y + radius)
}

/// CSS farthest-corner: от точки до дальнего угла квадрата 1×1
private func farthest(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    sqrt(pow(max(x, 1 - x), 2) + pow(max(y, 1 - y), 2))
}

// MARK: сфера

/// Слои шара (Orb.swift)
struct OrbLayers: NSViewRepresentable {
    struct Look: Equatable {
        var state: Orb.State
        var size: CGFloat
        var breathing: Bool
        var hot: Bool
        var halo: Double?
        var glow: Bool
        var colors: OrbColors
        /// «Меньше движения»: без переходов
        var instant: Bool
    }

    var look: Look

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }

    func updateNSView(_ v: OrbLayerView, context: Context) { v.apply(look) }
}

final class OrbLayerView: NSView {
    private let halo = CAGradientLayer()
    /// Тело с тенью-свечением под ним; дышит целиком
    private let bodyGroup = CALayer()
    private let ring = CALayer()
    private let clip = CALayer()
    private let base = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let spec = CAGradientLayer()
    /// Свечение под шаром — градиентом, не тенью слоя: дешевле и видно на снимках
    private let glow = CAGradientLayer()
    private let darkInner = CAGradientLayer()
    private let lightInner = CAGradientLayer()
    private let bright = CALayer()
    private var last: OrbLayers.Look?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        clip.masksToBounds = true
        [base, rim, spec, darkInner, lightInner, bright].forEach(clip.addSublayer)
        bodyGroup.addSublayer(glow)
        bodyGroup.addSublayer(clip)
        bodyGroup.addSublayer(ring)
        layer?.addSublayer(halo)
        layer?.addSublayer(bodyGroup)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ look: OrbLayers.Look) {
        guard look != last else { return }
        // поменялось только «горячо» или ореол — плавно (.4–.45 с), остальное — сразу
        var still = look
        still.hot = last?.hot ?? look.hot
        still.halo = last?.halo ?? look.halo
        let soft = last != nil && still == last && !look.instant
        last = look

        CATransaction.begin()
        CATransaction.setDisableActions(!soft)
        CATransaction.setAnimationDuration(0.42)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        let s = look.size, c = look.colors, hot = look.hot
        let bounds = CGRect(x: 0, y: 0, width: s, height: s)
        let center = CGPoint(x: s / 2, y: s / 2)

        // ореол за шаром приветствия: inset −70px, rgba(70,110,255,.24) → прозрачно на 62%
        let hd = s + 140
        halo.bounds = CGRect(x: 0, y: 0, width: hd, height: hd)
        halo.position = center
        radial(halo, x: 0.5, y: 0.5, radius: farthest(0.5, 0.5),
               stops: [(c.glow.mixed(with: .white, 0.08).opacity(0.24), 0), (.clear, 0.62)])
        halo.opacity = Float(look.halo ?? 0)

        bodyGroup.bounds = bounds
        bodyGroup.position = center
        // свечение под шаром: у большого 0 22px 60px (горячий — 90px и ярче), у маленьких — как в макете
        let k = s / 78
        let (dy, blur, alpha): (CGFloat, CGFloat, Double) =
            s >= 40 ? (22 * k, (hot ? 90 : 60) * k, hot ? 0.55 : 0.28) : (s >= 24 ? (6, 16, 0.25) : (4, 12, 0.22))
        // размытый круг: CSS-размытие blur ≈ σ = blur/2; профиль — как у гауссова края диска
        let sigma = blur / 2, rDisk = s / 2, g = 2 * (rDisk + 3 * sigma)
        glow.frame = CGRect(x: (s - g) / 2, y: (s - g) / 2 - dy, width: g, height: g)
        glow.isHidden = !look.glow
        let gc = hot ? c.glow.mixed(with: .white, 0.1) : c.glow
        let at = { (d: CGFloat) in Double(max(0, min(1, d / (g / 2)))) }
        radial(glow, x: 0.5, y: 0.5, radius: 0.5, stops: [
            (gc.opacity(alpha * 0.9), 0), (gc.opacity(alpha * 0.8), at(max(0, rDisk - sigma))), (gc.opacity(alpha * 0.5), at(rDisk)),
            (gc.opacity(alpha * 0.18), at(rDisk + sigma)), (gc.opacity(alpha * 0.04), at(rDisk + 2 * sigma)), (gc.opacity(0), 1),
        ])
        bodyGroup.opacity = look.state == .sleep ? 0.7 : 1

        // кольцо 1px снаружи: rgba(150,175,255,.14), горячий — .22
        ring.frame = bounds.insetBy(dx: -1, dy: -1)
        ring.cornerRadius = (s + 2) / 2
        ring.borderWidth = 1
        ring.borderColor = cg(c.ring.opacity(hot ? 0.22 : 0.14))

        clip.frame = bounds
        clip.cornerRadius = s / 2
        [base, rim, spec, darkInner, lightInner, bright].forEach { $0.frame = bounds }
        // тело: 42%/38% — #86A7FF, #4369F2 36%, #1D36AC 68%, #0A1452
        radial(base, x: 0.42, y: 0.38, radius: farthest(0.42, 0.38),
               stops: [(c.hi, 0), (c.mid, 0.36), (c.deep, 0.68), (c.deepest, 1)])
        // отсвет снизу справа: 72%/80%, rgba(130,175,255,.55) → 0 на 42%
        radial(rim, x: 0.72, y: 0.8, radius: farthest(0.72, 0.8), stops: [(c.rim, 0), (.clear, 0.42)])
        // блик сверху слева: 31%/27%, белый .95 → .55 на 7% → 0 на 21%
        radial(spec, x: 0.31, y: 0.27, radius: farthest(0.31, 0.27),
               stops: [(.white.opacity(0.95), 0), (.white.opacity(0.55), 0.07), (.white.opacity(0), 0.21)])

        // тени внутри: тёмная снизу справа (inset −10 −12 22), светлая кромка сверху слева (inset 5 6 12)
        inner(darkInner, dx: -0.128, dy: -0.154, blur: 0.28,
              color: Color(.sRGB, red: 3 / 255, green: 6 / 255, blue: 35 / 255), opacity: hot ? 0.55 : 0.62)
        inner(lightInner, dx: 0.064, dy: 0.077, blur: 0.154, color: .white, opacity: hot ? 0.18 : 0.14)

        // brightness(1.12) saturate(1.12) у горячего — лёгкий белый поверх
        bright.backgroundColor = NSColor.white.cgColor
        bright.opacity = hot ? 0.07 : 0
        CATransaction.commit()

        // дышит, пока ждём первый токен: scale 1 → 1.05 → 1 за 1,6 с
        if look.breathing {
            if bodyGroup.animation(forKey: "think") == nil {
                bodyGroup.add(CABasicAnimation.wave("transform.scale", from: 1, to: 1.05, period: 1.6), forKey: "think")
            }
        } else {
            bodyGroup.removeAnimation(forKey: "think")
        }
    }

    /// Тень внутри круга (CSS inset, доли стороны; dx, dy — как в CSS, вниз — плюс): темно там, куда не достаёт круг,
    /// сдвинутый на смещение тени, с мягким краем σ = blur/2. Градиентом — от центра сдвинутого круга
    private func inner(_ l: CAGradientLayer, dx: CGFloat, dy: CGFloat, blur: CGFloat, color: Color, opacity: Double) {
        let sigma = blur / 2, R: CGFloat = 0.85
        let at = { (d: CGFloat) in Double(max(0, min(1, d / R))) }
        radial(l, x: 0.5 + dx, y: 0.5 + dy, radius: R, stops: [
            (color.opacity(0), 0), (color.opacity(0), at(0.5 - 1.5 * sigma)), (color.opacity(opacity * 0.2), at(0.5 - 0.6 * sigma)),
            (color.opacity(opacity * 0.5), at(0.5)), (color.opacity(opacity * 0.85), at(0.5 + sigma)), (color.opacity(opacity), 1),
        ])
    }
}
