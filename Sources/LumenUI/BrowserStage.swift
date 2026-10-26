import AppKit
import WebKit

/// Закулисье браузера: невидимое окно, где живёт страница, которую сейчас не видно (агент работает в фоновой вкладке,
/// панель закрыта). Страница в окне — значит, WebKit рисует её, снимки не пустые, а нажатия идут настоящими событиями.
@MainActor
final class BrowserStage {
    static let shared = BrowserStage()

    private let window: NSWindow

    private init() {
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary, .fullScreenNone]
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 760))
    }

    /// Поставить страницу за кулисы; размер — как у панели, чтобы вёрстка не прыгала
    func park(_ view: WKWebView, size: CGSize? = nil) {
        guard let content = window.contentView else { return }
        let s = size ?? CGSize(width: max(760, view.bounds.width), height: max(820, view.bounds.height))
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = []
        view.frame = NSRect(origin: .zero, size: s)
        content.addSubview(view)
        window.setContentSize(s)
        Self.keepRendering(view)
    }

    func holds(_ view: WKWebView) -> Bool { view.superview === window.contentView }

    /// Страница рисуется, даже когда её не видно (вкладка агента за кулисами, холст макета): без этого WebKit считает её
    /// скрытой — не создаёт WebGL, не крутит анимации, и снимок выходит пустым. Только для таких вкладок: обычные
    /// фоновые страницы засыпают, как в Safari, и не тратят батарею
    static func keepRendering(_ view: WKWebView, _ on: Bool = true) {
        let sel = Selector(("_setWindowOcclusionDetectionEnabled:"))
        guard view.responds(to: sel) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(view.method(for: sel), to: Setter.self)(view, sel, !on)
    }
}
