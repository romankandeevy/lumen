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

private func radial(_ layer: CAGradientLayer, center: CGPoint, radius: CGFloat, stops: [(Color, Double)]) {
    layer.type = .radial
    layer.colors = stops.map { cg($0.0) }
    layer.locations = stops.map { NSNumber(value: $0.1) }
    layer.startPoint = center
    layer.endPoint = CGPoint(x: center.x + radius, y: center.y + radius)
}

// MARK: сфера

/// Слои сферы. Координаты слоёв снизу вверх (macOS), поэтому «сверху 30%» — это y = 0.7.
struct OrbLayers: NSViewRepresentable {
    var state: Orb.State
    var size: CGFloat
    var moving: Bool
    var palette: Palette

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }

    func updateNSView(_ v: OrbLayerView, context: Context) {
        v.apply(state: state, size: size, moving: moving, p: palette)
    }
}

final class OrbLayerView: NSView {
    private let halo = CAGradientLayer()
    private let bodyGroup = CALayer()
    private let glowLayer = CAGradientLayer()
    private let coreLayer = CAGradientLayer()
    private let clip = CALayer()
    private let tint = CALayer()
    private var key = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        clip.masksToBounds = true
        clip.addSublayer(glowLayer)
        clip.addSublayer(coreLayer)
        clip.addSublayer(tint)
        bodyGroup.addSublayer(clip)
        layer?.addSublayer(halo)
        layer?.addSublayer(bodyGroup)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(state: Orb.State, size: CGFloat, moving: Bool, p: Palette) {
        let newKey = "\(state)-\(size)-\(moving)-\(p.isMono)"
        guard newKey != key else { return }
        key = newKey

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let center = CGPoint(x: size / 2, y: size / 2)

        // .orb-halo: inset −60% (−90%, когда пишет), glowSoft → прозрачно на 65% до дальнего угла
        let extra: CGFloat = state == .writing ? 0.9 : 0.6
        let d = size * (1 + extra * 2)
        halo.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        halo.position = center
        radial(halo, center: CGPoint(x: 0.5, y: 0.5), radius: 0.5 * 1.4142 * 0.65, stops: [(p.glowSoft, 0), (.clear, 1)])

        // .orb-body: свечение glow от 50%/55%, блик glowCore от 35%/30%
        bodyGroup.bounds = bounds
        bodyGroup.position = center
        bodyGroup.shadowColor = cg(p.glowSoft)
        bodyGroup.shadowOpacity = 1
        bodyGroup.shadowRadius = size * 0.25
        bodyGroup.shadowOffset = .zero
        bodyGroup.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        clip.frame = bounds
        clip.cornerRadius = size / 2
        glowLayer.frame = bounds
        coreLayer.frame = bounds
        tint.frame = bounds
        radial(glowLayer, center: CGPoint(x: 0.5, y: 0.45), radius: sqrt(0.5 * 0.5 + 0.55 * 0.55),
               stops: [(p.glow, 0), (p.glow.opacity(0.4), 0.55), (.clear, 0.72)])
        radial(coreLayer, center: CGPoint(x: 0.35, y: 0.7), radius: sqrt(0.65 * 0.65 + 0.7 * 0.7),
               stops: [(p.glowCore, 0), (.clear, 0.45)])
        // «яркость»: пишет — светлее, думает — мерцает
        tint.backgroundColor = NSColor.white.cgColor
        tint.opacity = state == .writing ? 0.08 : 0
        layer?.opacity = 1
        bodyGroup.opacity = state == .sleep ? 0.7 : 1
        halo.opacity = state == .sleep ? 0.25 : (moving ? 0.55 : 0.85)
        halo.transform = CATransform3DIdentity
        CATransaction.commit()

        [halo, bodyGroup, tint].forEach { $0.removeAllAnimations() }
        guard moving, state != .sleep else { return }

        let period = state == .writing ? 0.9 : (state == .thinking ? 1.8 : 5.5)
        halo.add(CABasicAnimation.wave("transform.scale", from: 0.85, to: 1.08, period: period), forKey: "breathe")
        halo.add(CABasicAnimation.wave("opacity", from: 0.55, to: 1, period: period), forKey: "glow")
        switch state {
        case .thinking:
            bodyGroup.add(CABasicAnimation.wave("transform.scale", from: 0.9, to: 1.04, period: 1.8), forKey: "think")
            tint.add(CABasicAnimation.wave("opacity", from: 0, to: 0.12, period: 1.8), forKey: "flicker")
        case .idle, .writing:
            // плавает: чуть вправо и вверх за 9 с
            bodyGroup.add(CABasicAnimation.wave("transform.translation.x", from: 0, to: size * 0.015, period: 9), forKey: "dx")
            bodyGroup.add(CABasicAnimation.wave("transform.translation.y", from: 0, to: size * 0.02, period: 9), forKey: "dy")
        default: break
        }
    }
}
