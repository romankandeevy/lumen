import AppKit
import LumenCore
import QuartzCore

// Питомец рисуется слоями Core Animation, как сфера (Layers.swift): движение крутит системный сервер отрисовки,
// приложение не перерисовывает кадры. Движения одни на все питомцы: что делает роль, зависит только от настроения.

/// Фигуры питомца поверх прозрачного окна. Поле 100×100 растягивается по меньшей стороне вида
public final class PetView: NSView {
    /// Какой питомец: смена пересобирает слои
    public var spec: PetSpec? {
        didSet { if spec != oldValue { rebuild() } }
    }
    /// Настроение: смена перезапускает движения
    public var mood: PetMood = .idle {
        didSet { if mood != oldValue { restyle() } }
    }
    /// «Меньше движения» и превью в настройках: без движения, поза по настроению
    public var moving = true {
        didSet { if moving != oldValue { restyle() } }
    }
    /// Клик без перетаскивания — «погладить»
    public var onPoke: (() -> Void)?
    /// Перетащили и отпустили — место запоминается
    public var onDragEnd: (() -> Void)?

    /// Фигура на слое: слой и её описание
    private struct PartLayer {
        let layer: CAShapeLayer
        let part: PetPart
    }

    private var parts: [PartLayer] = []
    private var dragged = false

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(true)
        setAccessibilityLabel("Питомец")
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    // MARK: мышь: клик — «погладить», тянешь — переносим окно

    public override func mouseDown(with event: NSEvent) {
        dragged = false
    }

    public override func mouseDragged(with event: NSEvent) {
        // окно переносит система; вернётся, когда кнопку отпустили
        guard !dragged else { return }
        dragged = true
        window?.performDrag(with: event)
        onDragEnd?()
    }

    public override func mouseUp(with event: NSEvent) {
        if !dragged { onPoke?() }
        dragged = false
    }

    // MARK: слои

    private func rebuild() {
        parts.forEach { $0.layer.removeFromSuperlayer() }
        parts = []
        for part in spec?.parts ?? [] {
            let shape = CAShapeLayer()
            shape.fillColor = PetView.cgColor(part.color)
            layer?.addSublayer(shape)
            parts.append(PartLayer(layer: shape, part: part))
        }
        layoutParts()
    }

    /// Фигуры по полю: размер и место в пикселях вида, поворот вокруг центра
    private func layoutParts() {
        let s = min(bounds.width, bounds.height) / 100
        guard s > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in parts {
            let shape = item.layer
            let p = item.part
            let w = p.w * s
            let h = p.h * s
            shape.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            // у слоёв начало снизу, у полей — сверху: y переворачиваем
            shape.position = CGPoint(x: (p.x + p.w / 2) * s, y: bounds.height - (p.y + p.h / 2) * s)
            shape.path = Self.path(p.shape, width: w, height: h, radius: p.radius * s)
            shape.transform = CATransform3DMakeRotation(p.rotation * .pi / 180, 0, 0, 1)
        }
        CATransaction.commit()
        restyle()
    }

    private static func path(_ shape: PetShape, width w: CGFloat, height h: CGFloat, radius: CGFloat) -> CGPath {
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        switch shape {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rect:
            let r = min(radius, w / 2, h / 2)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w / 2, y: h))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            return path
        }
    }

    // MARK: движения

    /// Сбрасывает движения и ставит новые по настроению. Спящий питомец с «меньше движения» остаётся открытым
    private func restyle() {
        layer?.opacity = mood == .sleep ? 0.7 : 1
        for item in parts {
            item.layer.removeAllAnimations()
            guard moving else { continue }
            for animation in motions(for: item.part.role) { item.layer.add(animation, forKey: "pet") }
        }
    }

    private func motions(for role: PetRole) -> [CAAnimation] {
        switch mood {
        case .idle:
            switch role {
            case .body: [wave("transform.scale", from: 1, to: 1.03, period: 3.2)]
            case .tail: [wave("transform.rotation.z", from: -0.3, to: 0.3, period: 1.4, additive: true)]
            case .eye: [blink()]
            default: []
            }
        case .thinking:
            switch role {
            case .head: [wave("transform.rotation.z", from: -0.14, to: 0.14, period: 1.8, additive: true)]
            case .body: [wave("transform.scale", from: 1, to: 1.02, period: 1.8)]
            default: []
            }
        case .writing:
            switch role {
            case .ear: [wave("transform.rotation.z", from: -0.2, to: 0.2, period: 0.45, additive: true)]
            case .body: [wave("transform.translation.y", from: 0, to: 1.5, period: 0.5, additive: true)]
            case .eye: [blink()]
            default: []
            }
        case .happy:
            switch role {
            case .body: [wave("transform.translation.y", from: 0, to: -6, period: 0.5, additive: true)]
            case .tail: [wave("transform.rotation.z", from: -0.5, to: 0.5, period: 0.25, additive: true)]
            default: []
            }
        case .sleep:
            switch role {
            case .body: [wave("transform.scale", from: 1, to: 1.02, period: 5)]
            case .eye: [closed()]
            default: []
            }
        }
    }

    /// Туда-обратно бесконечно, мягко. `additive` — добавляется к повороту или сдвигу из геометрии
    private func wave(_ key: String, from: Double, to: Double, period: Double, additive: Bool = false) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = period / 2
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isAdditive = additive
        a.isRemovedOnCompletion = false
        return a
    }

    /// Глаза моргают раз в 4 с: почти всё время открыты, на миг закрываются
    private func blink() -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [1.0, 1.0, 0.1, 1.0]
        a.keyTimes = [0, 0.94, 0.97, 1] as [NSNumber]
        a.duration = 4
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        return a
    }

    /// Спит: глаза закрыты и остаются закрытыми
    private func closed() -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.scale.y")
        a.fromValue = 1.0
        a.toValue = 0.1
        a.duration = 0.4
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        return a
    }

    private static func cgColor(_ hex: String) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1).cgColor
    }
}
