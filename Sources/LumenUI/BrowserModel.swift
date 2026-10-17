import AppKit
import Foundation
import LumenCore
import Observation
import WebKit

/// Встроенный браузер (Browser.swift в LumenCore): одна страница WKWebView, которую видит человек в панели сбоку
/// и которой управляют агенты через lumen-mcp. Входы в аккаунты хранятся в постоянном хранилище WebKit приложения.
@MainActor @Observable
final class BrowserModel: NSObject {
    @ObservationIgnored let webView: WKWebView
    var url = ""
    var title = ""
    var loading = false
    var canGoBack = false
    var canGoForward = false
    /// Кто сейчас работает в браузере и что делает («@designer · Нажимает «Войти»»); nil — никто
    var activity: String?
    /// Агент открыл страницу — панель должна показаться
    var wantsOpen = 0

    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var activityClear: Task<Void, Never>?

    /// Как Safari: иначе часть сайтов (Google) не пускает «встроенные браузеры»
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        observers = [
            webView.observe(\.url) { [weak self] w, _ in MainActor.assumeIsolated { self?.url = w.url?.absoluteString ?? "" } },
            webView.observe(\.title) { [weak self] w, _ in MainActor.assumeIsolated { self?.title = w.title ?? "" } },
            webView.observe(\.isLoading) { [weak self] w, _ in MainActor.assumeIsolated { self?.loading = w.isLoading } },
            webView.observe(\.canGoBack) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoForward = w.canGoForward } },
        ]
    }

    /// Адрес из строки: «kandeev.com» → https://kandeev.com, «/Users/…» → файл, слова — поиск
    nonisolated static func address(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("/") || t.hasPrefix("~") { return URL(fileURLWithPath: (t as NSString).expandingTildeInPath) }
        if let u = URL(string: t), let s = u.scheme, ["http", "https", "file", "about", "data"].contains(s.lowercased()) { return u }
        if t.hasPrefix("localhost") || t.hasPrefix("127.0.0.1") { return URL(string: "http://" + t) }
        if t.contains("."), !t.contains(" ") { return URL(string: "https://" + t) }
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: t)]
        return c.url
    }

    func open(_ u: URL) {
        if u.isFileURL {
            // макету рядом нужны его картинки и стили — даём читать всю его папку
            webView.loadFileURL(u, allowingReadAccessTo: u.hasDirectoryPath ? u : u.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: u))
        }
    }

    // MARK: действия агентов (по очереди: два агента не жмут одновременно)

    func handle(tool: String, args: [String: Any], who: String) async -> BrowserTools.Reply {
        let previous = tail
        let task = Task<BrowserTools.Reply, Never> { @MainActor in
            await previous?.value
            return await self.perform(tool: tool, args: args, who: who)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func show(_ who: String, _ what: String) {
        activity = "\(who) · \(what)"
        wantsOpen += 1
        activityClear?.cancel()
        activityClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.activity = nil }
        }
    }

    private func perform(tool: String, args: [String: Any], who: String) async -> BrowserTools.Reply {
        func s(_ k: String) -> String { (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func n(_ k: String) -> Double? { (args[k] as? Double) ?? (args[k] as? Int).map(Double.init) }
        switch tool {
        case "browser_navigate":
            let target = s("url")
            switch target.lowercased() {
            case "back": show(who, "Назад"); webView.goBack()
            case "forward": show(who, "Вперёд"); webView.goForward()
            case "reload": show(who, "Обновляет"); webView.reload()
            default:
                guard let u = Self.address(target) else { return .init(text: "Пустой адрес.", error: true) }
                show(who, "Открывает \(u.host ?? u.lastPathComponent)")
                open(u)
            }
            await settle(started: true)
            return await snapshot(header: true, interactive: true)
        case "browser_show":
            let p = s("path")
            guard let u = Self.address(p) else { return .init(text: "Пустой путь.", error: true) }
            if u.isFileURL, !FileManager.default.fileExists(atPath: u.path) { return .init(text: "Нет такого файла: \(u.path)", error: true) }
            show(who, "Показывает \(u.isFileURL ? u.lastPathComponent : (u.host ?? p))")
            open(u)
            await settle(started: true)
            return .init(text: "Открыто в браузере сбоку: \(u.isFileURL ? u.path : u.absoluteString). Человек это видит.")
        case "browser_read_page":
            show(who, "Читает страницу")
            return await snapshot(header: true, interactive: s("filter") == "interactive")
        case "browser_find":
            show(who, "Ищет «\(s("query").prefix(30))»")
            return await js(Self.findJS, ["query": s("query")])
        case "browser_click":
            show(who, "Нажимает")
            var a: [String: Any] = ["ref": s("ref")]
            if let x = n("x"), let y = n("y") { a["x"] = x; a["y"] = y }
            let r = await js(Self.clickJS, a)
            if r.error { return r }
            show(who, "Нажал \(r.text)")
            await settle(started: false)
            return await snapshot(header: true, interactive: true, prefix: "Нажато: \(r.text)")
        case "browser_type":
            show(who, "Печатает")
            let r = await js(Self.typeJS, ["ref": s("ref"), "text": args["text"] as? String ?? "", "submit": args["submit"] as? Bool ?? false])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(header: true, interactive: true, prefix: r.text)
        case "browser_select":
            show(who, "Выбирает")
            let r = await js(Self.selectJS, ["ref": s("ref"), "value": s("value")])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(header: true, interactive: true, prefix: r.text)
        case "browser_key":
            show(who, "Клавиша \(s("key"))")
            let r = await js(Self.keyJS, ["key": s("key")])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(header: true, interactive: true, prefix: r.text)
        case "browser_scroll":
            show(who, "Прокручивает")
            let r = await js(Self.scrollJS, ["ref": s("ref"), "direction": s("direction").isEmpty ? "down" : s("direction"), "amount": n("amount") ?? 1])
            if r.error { return r }
            return await snapshot(header: true, interactive: true, prefix: r.text)
        case "browser_screenshot":
            show(who, "Смотрит")
            return await screenshot()
        case "browser_text":
            show(who, "Читает текст")
            return await js("return (document.title ? document.title + '\\n\\n' : '') + (document.body ? document.body.innerText : '').slice(0, 40000);", [:])
        case "browser_js":
            show(who, "Выполняет скрипт")
            let code = args["code"] as? String ?? ""
            let body = code.contains("return") ? code : "return eval(\(Self.quoted(code)));"
            return await js("const __r = await (async () => { \(body) })(); return typeof __r === 'string' ? __r : JSON.stringify(__r, null, 1);",
                            [:], world: .page)
        case "browser_wait":
            let text = s("text")
            show(who, text.isEmpty ? "Ждёт" : "Ждёт «\(text.prefix(30))»")
            let limit = Date().addingTimeInterval(min(n("seconds") ?? (text.isEmpty ? 2 : 10), 20))
            while Date() < limit {
                if !text.isEmpty, (try? await webView.callAsyncJavaScript("return document.body ? document.body.innerText.includes(t) : false",
                                                                         arguments: ["t": text], in: nil, contentWorld: .defaultClient)) as? Bool == true {
                    return await snapshot(header: true, interactive: true, prefix: "Появилось «\(text)».")
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            return text.isEmpty ? await snapshot(header: true, interactive: true) : .init(text: "Текст «\(text)» не появился.", error: true)
        default:
            return .init(text: "Нет такого действия браузера: \(tool)", error: true)
        }
    }

    /// Дождаться, пока страница загрузится: после перехода — до 15 с, после нажатия — если переход начался
    private func settle(started: Bool) async {
        try? await Task.sleep(for: .milliseconds(started ? 150 : 250))
        let limit = Date().addingTimeInterval(15)
        while webView.isLoading && Date() < limit { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func snapshot(header: Bool, interactive: Bool, prefix: String? = nil) async -> BrowserTools.Reply {
        var r = await js(Self.snapshotJS, ["interactive": interactive, "max": 14000])
        if !r.error {
            var head = header ? "Страница: \(title.isEmpty ? "без названия" : title)\nАдрес: \(url)\n" : ""
            if let prefix { head = prefix + "\n" + head }
            r.text = head + (r.text.isEmpty ? "(пусто)" : r.text)
        }
        return r
    }

    private func js(_ body: String, _ args: [String: Any], world: WKContentWorld = .defaultClient) async -> BrowserTools.Reply {
        do {
            let v = try await webView.callAsyncJavaScript(body, arguments: ["args": args], in: nil, contentWorld: world)
            if let s = v as? String {
                if s.hasPrefix("ERR:") { return .init(text: String(s.dropFirst(4)), error: true) }
                return .init(text: s)
            }
            if let v { return .init(text: "\(v)") }
            return .init(text: "")
        } catch {
            return .init(text: "Ошибка на странице: \(error.localizedDescription)", error: true)
        }
    }

    private func screenshot() async -> BrowserTools.Reply {
        guard webView.bounds.width > 10 else { return .init(text: "Браузер свёрнут — открой панель, чтобы снять экран.", error: true) }
        do {
            let image = try await webView.takeSnapshot(configuration: nil)
            // не больше 1280 точек в ширину — дешевле для модели, читается так же
            let scale = min(1, 1280 / max(image.size.width, 1))
            let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                return .init(text: "Снимок не получился.", error: true)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { return .init(text: "Снимок не получился.", error: true) }
            return .init(text: "Снимок: \(title) — \(url). Точки x, y для browser_click — в масштабе страницы × \(String(format: "%.2f", scale)).", image: png)
        } catch {
            return .init(text: "Снимок не получился: \(error.localizedDescription)", error: true)
        }
    }

    nonisolated static func quoted(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }
}

extension BrowserModel: WKUIDelegate, WKNavigationDelegate {
    /// Ссылки «в новом окне» открываются здесь же — окно одно, его видит человек
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let a = NSAlert()
        a.messageText = message
        a.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Отмена")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Загрузка файлов — в «Загрузки»
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

extension BrowserModel: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var url = dir.appendingPathComponent(suggestedFilename)
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\((suggestedFilename as NSString).deletingPathExtension) \(i).\((suggestedFilename as NSString).pathExtension)")
            i += 1
        }
        return url
    }
}
