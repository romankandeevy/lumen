import AppKit
import LumenCore
import SwiftUI
import WebKit

/// Живая картинка прямо в переписке: блок ```visual из ответа (HTML или SVG) рисуется на месте — график, схема,
/// интерактивная штука. Цвета — из темы Lumen, высота — по содержимому, прокрутка переписки сквозь неё не ломается.
/// В сеть картинка не ходит, кроме библиотек с cdn.jsdelivr.net (Chart.js, D3, Mermaid).
struct VisualBlock: View {
    let code: String
    /// Блок закрыт — ответ дописал его до конца; пока нет — «Рисую…»
    let done: Bool

    @Environment(\.palette) private var p
    @State private var height: CGFloat = 160
    @State private var hover = false
    @State private var showCode = false

    var body: some View {
        if !done {
            HStack(spacing: 10) {
                DotsSpinner(color: p.glow, plain: true)
                Text("Рисую…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(p.foreground)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(p.foreground.opacity(0.03), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                VisualWeb(html: Self.page(code, palette: p), height: $height)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if hover {
                            HStack(spacing: 2) {
                                IconButton(icon: "code-xml", help: showCode ? "Спрятать код" : "Показать код", active: showCode) { showCode.toggle() }
                                IconButton(icon: "external-link", help: "Открыть в браузере сбоку — крупнее") { openAside() }
                            }
                            .padding(3)
                            .background(p.popover.opacity(0.92), in: RoundedRectangle(cornerRadius: R.lg))
                            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                            .padding(6)
                            .transition(.opacity)
                        }
                    }
                if showCode { CodeBlock(code: code, lang: "html") }
            }
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        }
    }

    /// Та же картинка в браузере сбоку: файл в run/, браузер открывает его
    private func openAside() {
        let dir = AppPaths.standard.run.appendingPathComponent("visuals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("visual-\(abs(code.hashValue)).html")
        try? Data(Self.page(code, palette: p, standalone: true).utf8).write(to: url)
        NotificationCenter.default.post(name: .lumenOpenInBrowser, object: url)
    }

    /// Страница вокруг блока: цвета темы переменными, шрифт системы, прозрачный фон, запрет сети (кроме CDN)
    static func page(_ code: String, palette p: Palette, standalone: Bool = false) -> String {
        let accent2 = p.isLight ? "#2F6FD0" : "#6FB1FF"
        let accent3 = p.isLight ? "#2E8A57" : "#5FD49A"
        return """
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; \
            style-src 'unsafe-inline' https://cdn.jsdelivr.net; img-src data: blob:; font-src data: https://cdn.jsdelivr.net; connect-src 'none'">
            <style>
            :root{--fg:\(p.foreground.hexString);--muted:\(p.mutedFg.hexString);--accent:\(p.glow.hexString);--accent-2:\(accent2);\
            --accent-3:\(accent3);--card:\(p.card.hexString);--border:\(p.foreground.mixed(with: p.background, 0.86).hexString);\
            --bg:\(p.background.hexString);color-scheme:\(p.isLight ? "light" : "dark")}
            html,body{margin:0;padding:0;background:\(standalone ? "var(--bg)" : "transparent");color:var(--fg);
            font:14px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;-webkit-font-smoothing:antialiased}
            body{padding:\(standalone ? "24px" : "2px 1px")}
            *{box-sizing:border-box}
            svg{max-width:100%;height:auto}
            .card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:14px 16px}
            .muted{color:var(--muted)} .row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
            .grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(160px,1fr))}
            button{font:inherit;color:var(--fg);background:var(--card);border:1px solid var(--border);border-radius:9px;padding:6px 12px;cursor:pointer}
            input,select{font:inherit;color:var(--fg);background:var(--card);border:1px solid var(--border);border-radius:8px;padding:5px 8px}
            input[type=range]{accent-color:var(--accent);padding:0}
            a{color:var(--accent)}
            </style>
            <script>
            // Chart.js, когда загрузится: цвета темы по умолчанию и сразу нарисован (без анимации — картинка не мигает)
            (function(){var C;Object.defineProperty(window,'Chart',{configurable:true,get:function(){return C},set:function(v){C=v;
              try{var s=getComputedStyle(document.documentElement);v.defaults.animation=false;
                v.defaults.color=s.getPropertyValue('--muted').trim();v.defaults.borderColor=s.getPropertyValue('--border').trim();
                v.defaults.font.family='-apple-system,BlinkMacSystemFont,sans-serif';}catch(e){}}});})();
            </script>
            </head><body>
            \(code)
            <script>
            (function(){
              function send(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);
                try{window.webkit.messageHandlers.size.postMessage(h)}catch(e){}}
              new ResizeObserver(send).observe(document.documentElement);
              window.addEventListener('load',send);setTimeout(send,50);setTimeout(send,600);
            })();
            </script></body></html>
            """
    }
}

extension Notification.Name {
    /// Открыть файл в браузере сбоку (живая картинка «крупнее»)
    static let lumenOpenInBrowser = Notification.Name("lumenOpenInBrowser")
}

/// WKWebView для живой картинки: высота — по содержимому, колесо мыши уходит переписке, ссылки — в браузер системы
struct VisualWeb: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PassThroughWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "size")
        cfg.websiteDataStore = .nonPersistent()
        let v = PassThroughWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        v.navigationDelegate = context.coordinator
        context.coordinator.loaded = html
        v.loadHTMLString(html, baseURL: URL(string: "https://lumen.visual/"))
        return v
    }

    func updateNSView(_ v: PassThroughWebView, context: Context) {
        context.coordinator.parent = self
        // тема поменялась (или блок дописан) — перерисовать
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            v.loadHTMLString(html, baseURL: URL(string: "https://lumen.visual/"))
        }
    }

    static func dismantleNSView(_ v: PassThroughWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "size")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: VisualWeb
        var loaded = ""
        init(_ p: VisualWeb) { parent = p }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = message.body as? Double ?? (message.body as? Int).map(Double.init) else { return }
            let clamped = CGFloat(min(1400, max(40, h)))
            if abs(clamped - parent.height) > 1 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }

        /// Сама страница грузится, а переходы по ссылкам — в обычный браузер
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated, let u = a.request.url {
                // в браузер сбоку, как и остальные ссылки из переписки
                NotificationCenter.default.post(name: .lumenOpenInBrowser, object: u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Колесо мыши над картинкой листает переписку, а не саму картинку (у неё высота по содержимому)
final class PassThroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
