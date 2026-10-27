import AppKit
import SwiftUI

/// Стекло (Рома, 27.10): под цветом панели или основной области — размытый рабочий стол, цвет делается прозрачнее ползунком
/// «Настройки → Окно → Прозрачность» (отдельно для левой панели и для основной области). Нужно окно без сплошной подложки — `WindowGlass`
struct GlassBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Подложка-стекло: размытый рабочий стол, поверх него цвет, который тает быстрее ползунка (степень 1,6), и блик сверху
struct GlassFill<Tint: View>: View {
    let amount: Double
    @ViewBuilder var tint: () -> Tint

    var body: some View {
        ZStack {
            GlassBlur()
            tint().opacity(pow(1 - amount, 1.6))
            LinearGradient(colors: [Color.white.opacity(0.10 * amount), .clear], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Окно перестаёт быть сплошным, пока панель стеклянная: иначе размывать нечего. Всё, кроме панели, закрашено своим цветом
struct WindowGlass: NSViewRepresentable {
    let on: Bool

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ v: Probe, context: Context) { v.on = on; v.apply() }

    final class Probe: NSView {
        var on = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let w = window else { return }
            w.isOpaque = !on
            w.backgroundColor = on ? .clear : .windowBackgroundColor
            w.invalidateShadow()
        }
    }
}
