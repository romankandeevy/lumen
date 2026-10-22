import AppKit
import QuartzCore
import SwiftUI

// Знак-затмение на слоях Core Animation (lumen-theme.css, `.ec`): вращение «мысли» и мерцание «бриллианта» крутит системный
// сервер отрисовки, приложение в это время спит (Orb на TimelineView стоил 11% процессора, на слоях — 0%).
// Значения градиентов — ровно из CSS, не «на глаз». Размеры в долях стороны знака s.

extension CABasicAnimation {
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

func cg(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a))
}

/// Радиальный градиент как в CSS: центр (x, y) в долях слоя, y — сверху вниз; радиус — в долях стороны
func radial(_ layer: CAGradientLayer, x: CGFloat, y: CGFloat, radius: CGFloat, stops: [(CGColor, Double)]) {
    layer.type = .radial
    layer.colors = stops.map(\.0)
    layer.locations = stops.map { NSNumber(value: $0.1) }
    // слои на macOS считают снизу вверх
    layer.startPoint = CGPoint(x: x, y: 1 - y)
    layer.endPoint = CGPoint(x: x + radius, y: 1 - y + radius)
}

/// Конический градиент: углы в градусах по часовой от верха, как `conic-gradient(from 0deg, …)`
func conic(_ layer: CAGradientLayer, stops: [(CGColor, Double)]) {
    layer.type = .conic
    layer.colors = stops.map(\.0)
    layer.locations = stops.map { NSNumber(value: min(1, max(0, $0.1 / 360))) }
    layer.startPoint = CGPoint(x: 0.5, y: 0.5)
    layer.endPoint = CGPoint(x: 0.5, y: 1)
}

/// CSS farthest-corner: от точки до дальнего угла квадрата 1×1
func farthest(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    sqrt(pow(max(x, 1 - x), 2) + pow(max(y, 1 - y), 2))
}

/// Маска-радиал «от непрозрачного к прозрачному»: closest-side, доли радиуса
private func radialMask(_ stops: [(Double, Double)]) -> CAGradientLayer {
    let m = CAGradientLayer()
    radial(m, x: 0.5, y: 0.5, radius: 0.5, stops: stops.map { (CGColor(gray: 0, alpha: CGFloat($0.1)), $0.0) })
    return m
}

// MARK: знак-затмение

struct EclipseLayers: NSViewRepresentable {
    struct Look: Equatable {
        var size: CGFloat
        /// Малый знак (рядом с ответом): корона, луна и свет по краю — без лучей и «бриллианта»
        var small: Bool
        /// Поле ввода в фокусе или в нём текст — на краю мерцает «бриллиант» (только большой)
        var hot: Bool
        /// Ждём первый токен: свет бежит по кругу (только малый)
        var think: Bool
        var light: Bool
        /// Цвет темы для короны и лучей (RGB); nil — «Люмен», цвета из CSS
        var tint: UInt32?
        /// «Меньше движения»: без анимаций
        var instant: Bool
    }

    var look: Look

    func makeNSView(context: Context) -> EclipseLayerView { EclipseLayerView() }

    func updateNSView(_ v: EclipseLayerView, context: Context) { v.apply(look) }
}

final class EclipseLayerView: NSView {
    private let glow = CAGradientLayer()
    private let streamerHost = CALayer()
    private let streamers = CAGradientLayer()
    private let fiberHost = CALayer()
    private let fibers = CAGradientLayer()
    private let inner = CAGradientLayer()
    private let orbit = CALayer()
    private let sunGroup = CALayer()
    private let sun = CAGradientLayer()
    private let bloom = CAGradientLayer()
    private let moon = CAGradientLayer()
    private let moonEdge = CAGradientLayer()
    private let dia = CALayer()
    private let twinkle = CAGradientLayer()
    private var last: EclipseLayers.Look?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        streamerHost.addSublayer(streamers)
        fiberHost.addSublayer(fibers)
        sunGroup.addSublayer(sun)
        orbit.addSublayer(sunGroup)
        orbit.addSublayer(bloom)
        dia.addSublayer(twinkle)
        [glow, streamerHost, fiberHost, inner, orbit, moon, moonEdge, dia].forEach { layer?.addSublayer($0) }
        sun.masksToBounds = true
        moon.masksToBounds = true
        moonEdge.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ look: EclipseLayers.Look) {
        guard look != last else { return }
        let sameShape = last.map { $0.size == look.size && $0.small == look.small && $0.light == look.light } ?? false
        let soft = sameShape && !look.instant
        last = look
        if !sameShape { rebuild(look) }
        CATransaction.begin()
        CATransaction.setDisableActions(!soft)
        CATransaction.setAnimationDuration(0.55)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        state(look)
        CATransaction.commit()
    }

    /// Всё, что зависит от размера и света: слои, градиенты, маски
    private func rebuild(_ look: EclipseLayers.Look) {
        let s = look.size, light = look.light, small = look.small
        let c = CGPoint(x: s / 2, y: s / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        func put(_ l: CALayer, _ side: CGFloat, at p: CGPoint? = nil) {
            l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            l.position = p ?? c
            l.cornerRadius = 0
        }
        let ink = (r: 28, g: 38, b: 72)
        // цвет с поправкой на тему: k — какая доля цвета темы подмешана (у «Люмена» ничего не меняется)
        func tc(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1, _ k: Double = 0.5) -> CGColor {
            guard let t = look.tint else { return cg(r, g, b, a) }
            let tr = Double(Int(t >> 16) & 255), tg = Double(Int(t >> 8) & 255), tb = Double(Int(t) & 255)
            return cg(Int(Double(r) * (1 - k) + tr * k), Int(Double(g) * (1 - k) + tg * k), Int(Double(b) * (1 - k) + tb * k), a)
        }

        // рассеянный голубоватый свет неба; у светлой — мягкая тень «тушью»
        glow.isHidden = small
        if !small {
            put(glow, s * (light ? 2.24 : 2.8))
            radial(glow, x: 0.5, y: 0.5, radius: 0.5, stops: light
                   ? [(tc(ink.r, ink.g, ink.b, 0.30), 0), (tc(ink.r, ink.g, ink.b, 0.20), 0.42), (tc(ink.r, ink.g, ink.b, 0.07), 0.68), (.clear, 1)]
                   : [(tc(120, 150, 255, 0.10, 0.9), 0), (tc(120, 150, 255, 0.04, 0.9), 0.45), (.clear, 1)])
        }

        // внешняя корона: лучи = конус по углу × крутой спад по радиусу; светлая — тушью
        streamerHost.isHidden = small
        fiberHost.isHidden = small
        if !small {
            let sw = s * 3.3
            put(streamerHost, sw)
            streamers.frame = CGRect(x: 0, y: 0, width: sw, height: sw)
            let base = light ? (8, 12, 30) : (228, 236, 255)
            let angles: [(Double, Double)] = [
                (0, 0.55), (9, 0.18), (17, 0.7), (28, 0.25), (36, 0.5), (47, 0.12), (60, 0.6), (72, 0.2), (86, 0.9), (95, 0.3), (104, 0.55), (118, 0.15),
                (131, 0.45), (147, 0.2), (160, 0.6), (172, 0.25), (184, 0.5), (197, 0.14), (210, 0.65), (223, 0.22), (240, 0.4), (266, 0.9), (276, 0.3),
                (290, 0.5), (305, 0.12), (320, 0.55), (335, 0.2), (360, 0.55),
            ]
            conic(streamers, stops: angles.map { (tc(base.0, base.1, base.2, $0.1), $0.0) })
            let sm = radialMask([(0, 1), (0.30, 1), (0.36, 0.6), (0.48, 0.24), (0.66, 0.08), (0.84, 0.02), (1, 0)])
            sm.frame = streamers.bounds
            streamers.mask = sm
            streamerHost.transform = CATransform3DConcat(CATransform3DMakeScale(1.3, 0.86, 1), CATransform3DMakeRotation(16 * .pi / 180, 0, 0, 1))

            // тонкие нити
            let fw = s * 2.4
            put(fiberHost, fw)
            fibers.frame = CGRect(x: 0, y: 0, width: fw, height: fw)
            let fc = light ? tc(ink.r, ink.g, ink.b, 0.14) : tc(255, 255, 255, 0.16)
            let none = light ? tc(ink.r, ink.g, ink.b, 0) : tc(255, 255, 255, 0)
            var stops: [(CGColor, Double)] = []
            var a = 0.0
            while a < 360 {
                stops += [(fc, a), (fc, min(360, a + 1.1)), (none, min(360, a + 1.1)), (none, min(360, a + 3.3))]
                a += 3.3
            }
            conic(fibers, stops: stops)
            let fm = radialMask([(0, 1), (0.40, 1), (0.52, 0.35), (0.72, 0.08), (1, 0)])
            fm.frame = fibers.bounds
            fibers.mask = fm
            fiberHost.transform = CATransform3DConcat(CATransform3DMakeScale(1.2, 0.9, 1), CATransform3DMakeRotation(16 * .pi / 180, 0, 0, 1))
            fiberHost.opacity = light ? 0.7 : 0.8
        }

        // внутренняя корона: ярче всего у самого края Луны, круто спадает
        let innerSide = s * (small ? (light ? 1.6 : 1.44) : 1.6)
        put(inner, innerSide)
        if small && light {
            radial(inner, x: 0.5, y: 0.5, radius: 0.5, stops: [
                (tc(255, 255, 255), 0), (tc(255, 255, 255), 0.64), (tc(255, 255, 255, 0.9), 0.68), (tc(ink.r, ink.g, ink.b, 0.26), 0.74),
                (tc(ink.r, ink.g, ink.b, 0.10), 0.86), (.clear, 1),
            ])
        } else if light {
            radial(inner, x: 0.5, y: 0.5, radius: 0.5, stops: [
                (tc(255, 255, 255), 0), (tc(255, 255, 255), 0.60), (tc(255, 255, 255, 0.95), 0.63), (tc(246, 249, 255, 0.7), 0.69),
                (tc(236, 242, 255, 0.28), 0.80), (tc(236, 242, 255, 0.06), 0.92), (.clear, 1),
            ])
        } else {
            radial(inner, x: 0.5, y: 0.5, radius: 0.5, stops: [
                (tc(243, 246, 255), 0), (tc(243, 246, 255), 0.60), (tc(236, 242, 255, 0.9), 0.63), (tc(214, 226, 255, 0.45), 0.69),
                (tc(190, 208, 255, 0.16), 0.80), (tc(170, 195, 255, 0.04), 0.92), (.clear, 1),
            ])
        }

        // фотосфера Солнца — прячется за Луной; при «мысли» выглядывает тонким серпом и бежит по кругу
        put(orbit, s)
        put(sunGroup, s, at: c)
        sun.frame = CGRect(x: 0, y: 0, width: s, height: s)
        sun.cornerRadius = s / 2
        radial(sun, x: 0.5, y: 0.5, radius: 0.7071, stops: [(cg(255, 255, 255), 0), (cg(244, 247, 255), 0.72), (cg(221, 231, 255), 1)])
        sunGroup.shadowOffset = .zero
        sunGroup.shadowRadius = s * 0.06
        sunGroup.shadowColor = light ? cg(ink.r, ink.g, ink.b) : cg(225, 235, 255)
        // всплеск света: справа от диска
        bloom.bounds = CGRect(x: 0, y: 0, width: s * 0.34, height: s * 0.72)
        bloom.position = CGPoint(x: s * 0.83 + s * 0.17, y: s * 0.5)
        radial(bloom, x: 0.5, y: 0.5, radius: 0.5, stops: [(cg(255, 255, 255, 0.85), 0), (cg(228, 237, 255, 0.38), 0.38), (cg(190, 210, 255, 0), 1)])

        // Луна чуть больше Солнца — потому и полное затмение; чёрная в обеих темах
        put(moon, s * 1.05)
        moon.cornerRadius = s * 1.05 / 2
        radial(moon, x: 0.42, y: 0.38, radius: farthest(0.42, 0.38),
               stops: [(cg(12, 14, 21), 0), (cg(5, 6, 8), 0.55), (cg(2, 2, 3), 1)])
        put(moonEdge, s * 1.05)
        moonEdge.cornerRadius = s * 1.05 / 2
        radial(moonEdge, x: 0.5, y: 0.5, radius: 0.5, stops: [(.clear, 0), (.clear, 0.9), (CGColor(gray: 0, alpha: 0.8), 1)])

        // «бриллиант»: одна бусина фотосферы сквозь лунную долину, на краю сверху справа
        dia.isHidden = small
        if !small {
            put(dia, s * 0.9, at: CGPoint(x: s * (0.371 + 0.45), y: s - s * (-0.333 + 0.45)))
            twinkle.frame = CGRect(x: 0, y: 0, width: s * 0.9, height: s * 0.9)
            radial(twinkle, x: 0.5, y: 0.5, radius: 0.5, stops: [
                (cg(255, 255, 255), 0), (cg(255, 255, 255, 0.95), 0.06), (cg(236, 242, 255, 0.55), 0.14), (cg(200, 215, 255, 0.18), 0.34),
                (cg(170, 195, 255, 0.05), 0.60), (.clear, 1),
            ])
        }
    }

    /// Состояние: покой, «горячо» (поле в фокусе) или «думает»
    private func state(_ look: EclipseLayers.Look) {
        let s = look.size, light = look.light
        // лучи при «горячо» притухают
        streamerHost.opacity = look.hot ? (light ? 0.26 : 0.55) : (light ? 0.42 : 1)
        dia.opacity = look.hot ? 1 : 0
        dia.transform = look.hot ? CATransform3DIdentity : CATransform3DMakeScale(0.4, 0.4, 1)

        sunGroup.position = CGPoint(x: s / 2 + (look.think ? s * 0.05 : 0), y: s / 2)
        bloom.opacity = look.think ? 1 : 0
        sunGroup.shadowOpacity = look.think ? (light ? 0.18 : 0.5) : 0

        if look.hot && !look.instant {
            if twinkle.animation(forKey: "twinkle") == nil {
                let o = CAKeyframeAnimation(keyPath: "opacity")
                o.values = [1, 0.6, 0.92, 1]
                let k = CAKeyframeAnimation(keyPath: "transform.scale")
                k.values = [1, 0.84, 0.96, 1]
                [o, k].forEach {
                    $0.keyTimes = [0, 0.45, 0.62, 1]
                    $0.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
                    $0.duration = 1.3
                }
                let g = CAAnimationGroup()
                g.animations = [o, k]
                g.duration = 1.3
                g.repeatCount = .infinity
                twinkle.add(g, forKey: "twinkle")
            }
        } else {
            twinkle.removeAnimation(forKey: "twinkle")
        }

        if look.think && !look.instant {
            if orbit.animation(forKey: "orbit") == nil {
                let a = CABasicAnimation(keyPath: "transform.rotation.z")
                a.fromValue = 0
                a.toValue = -2 * Double.pi   // по часовой, как rotate(360deg) в CSS
                a.duration = 2.6
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                orbit.add(a, forKey: "orbit")
            }
        } else {
            orbit.removeAnimation(forKey: "orbit")
        }
    }
}
