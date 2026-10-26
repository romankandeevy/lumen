import AppKit
import SwiftUI

/// Линия шапки (Рома, 26.10: «чтобы всё было на одном уровне»): кнопки окна, «панель», «поиск», название разговора
/// и кнопки справа стоят центром на одной высоте, а кнопки окна — дальше от края, не впритык
enum TitleBar {
    /// Центр линии от верха окна
    static let lineY: CGFloat = 24
    /// Высота шапки: линия посередине
    static let height: CGFloat = 48
    /// Кнопки окна: левый край первой и шаг между ними (у macOS — 7 и 20)
    static let lightsX: CGFloat = 18
    static let lightsGap: CGFloat = 20
    /// «Панель» и «поиск»: начинаются через 8 pt после кнопок окна (их кнопка 32 pt, значок 16 — по центру)
    static let controlsX: CGFloat = lightsX + lightsGap * 2 + 14 + 8
    /// Сверху до кнопок высотой `side`, чтобы их центр лёг на линию
    static func top(_ side: CGFloat) -> CGFloat { lineY - side / 2 }
}

/// Ставит кнопки окна на линию шапки. macOS раскладывает заголовок заново при каждом изменении окна,
/// поэтому место назначается снова после ресайза, смены фокуса и выхода из полного экрана
struct TrafficLights: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ v: Probe, context: Context) { v.place() }

    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            // ушёл из окна — наблюдатели сняты выше
            guard let w = window else { return }
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                                              NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification]
            for n in names {
                observers.append(NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        /// Заголовок окна выше и кнопки на линии: так они и видны, и нажимаются (вне заголовка клик не дошёл бы)
        func place() {
            guard let w = window, !w.styleMask.contains(.fullScreen),
                  let close = w.standardWindowButton(.closeButton), let bar = close.superview,
                  let container = bar.superview, let frameView = container.superview else { return }
            var f = container.frame
            if abs(f.height - TitleBar.height) > 0.5 || abs(f.maxY - frameView.bounds.maxY) > 0.5 {
                f.size.height = TitleBar.height
                f.origin.y = frameView.isFlipped ? 0 : frameView.bounds.height - TitleBar.height
                container.frame = f
            }
            if bar.frame != container.bounds { bar.frame = container.bounds }
            for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let b = w.standardWindowButton(t) else { continue }
                let h = b.frame.height
                let y = bar.isFlipped ? TitleBar.lineY - h / 2 : bar.bounds.height - TitleBar.lineY - h / 2
                let origin = NSPoint(x: TitleBar.lightsX + TitleBar.lightsGap * CGFloat(i), y: y.rounded())
                if b.frame.origin != origin { b.setFrameOrigin(origin) }
            }
        }
    }
}
