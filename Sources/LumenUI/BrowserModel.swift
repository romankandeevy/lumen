import AppKit
import Foundation
import LumenCore
import LumenProviders
import Observation
import WebKit

/// Встроенный браузер (Browser.swift в LumenCore): вкладки WKWebView, которые видит человек в панели сбоку
/// и которыми управляют агенты через lumen-mcp. Входы в аккаунты хранятся в постоянном хранилище WebKit приложения.
/// Умеет то же, что браузер Claude: вкладки, клики любой кнопкой с модификаторами, наведение, перетаскивание,
/// клавиши, увеличенный снимок, загрузку файлов, консоль и сеть, вид телефона/планшета, тёмную схему.
@MainActor @Observable
final class BrowserModel: NSObject {
    /// Вкладка: свой WKWebView, общие входы
    @MainActor @Observable final class Tab: Identifiable {
        let id: Int
        @ObservationIgnored let webView: WKWebView
        var title = ""
        var url = ""
        @ObservationIgnored var observers: [NSKeyValueObservation] = []

        init(id: Int, webView: WKWebView) {
            self.id = id
            self.webView = webView
        }
    }

    enum Viewport: String { case desktop, tablet, mobile
        var size: CGSize? {
            switch self {
            case .desktop: nil
            case .tablet: CGSize(width: 820, height: 1180)
            case .mobile: CGSize(width: 390, height: 844)
            }
        }
    }

    private(set) var tabs: [Tab] = []
    private(set) var activeID = 0
    var active: Tab { tabs.first { $0.id == activeID } ?? tabs[0] }
    var webView: WKWebView { active.webView }

    var url = ""
    var title = ""
    var loading = false
    var canGoBack = false
    var canGoForward = false
    /// Кто сейчас работает в браузере и что делает («@designer · Нажимает «Войти»»); nil — никто
    var activity: String?
    /// Агент открыл страницу — панель должна показаться
    var wantsOpen = 0
    var viewport: Viewport = .desktop
    /// Запущенные на Маке localhost — видны в панели и агентам
    var servers: [LocalServers.Server] = []
    /// nil — как в системе
    var dark: Bool?

    @ObservationIgnored private var activeObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var activityClear: Task<Void, Never>?
    @ObservationIgnored private var nextTabID = 1
    /// Агент сейчас что-то делает: диалоги страницы не ждут человека
    @ObservationIgnored private var acting = 0
    /// Что случилось между действиями (новые вкладки, скачивания, окна страницы) — уходит агенту в следующем ответе
    @ObservationIgnored private var events: [String] = []
    @ObservationIgnored private var downloads: [ObjectIdentifier: URL] = [:]

    /// Как Safari: иначе часть сайтов (Google) не пускает «встроенные браузеры»
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    static let mobileAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let tabletAgent = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    override init() {
        super.init()
        _ = newTab(configuration: nil)
    }

    // MARK: вкладки

    private func configuration() -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        return cfg
    }

    /// Новая вкладка; `configuration` — от WebKit, когда страница открывает окно
    @discardableResult
    func newTab(configuration given: WKWebViewConfiguration?, select: Bool = true) -> Tab {
        let cfg = given ?? configuration()
        // журнал консоли и сети — до кода страницы
        if !cfg.userContentController.userScripts.contains(where: { $0.source == Self.captureJS }) {
            cfg.userContentController.addUserScript(WKUserScript(source: Self.captureJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.customUserAgent = agent
        w.allowsBackForwardNavigationGestures = true
        w.allowsMagnification = true
        if let dark { w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        if #available(macOS 13.3, *) { w.isInspectable = true }
        w.uiDelegate = self
        w.navigationDelegate = self
        let tab = Tab(id: nextTabID, webView: w)
        nextTabID += 1
        tab.observers = [
            w.observe(\.title) { [weak tab] v, _ in MainActor.assumeIsolated { tab?.title = v.title ?? "" } },
            w.observe(\.url) { [weak tab] v, _ in MainActor.assumeIsolated { tab?.url = v.url?.absoluteString ?? "" } },
        ]
        tabs.append(tab)
        if select { self.select(tab.id) }
        return tab
    }

    func select(_ id: Int) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        let w = webView
        activeObservers = [
            w.observe(\.url, options: [.initial]) { [weak self] v, _ in MainActor.assumeIsolated { self?.url = v.url?.absoluteString ?? "" } },
            w.observe(\.title, options: [.initial]) { [weak self] v, _ in MainActor.assumeIsolated { self?.title = v.title ?? "" } },
            w.observe(\.isLoading, options: [.initial]) { [weak self] v, _ in MainActor.assumeIsolated { self?.loading = v.isLoading } },
            w.observe(\.canGoBack, options: [.initial]) { [weak self] v, _ in MainActor.assumeIsolated { self?.canGoBack = v.canGoBack } },
            w.observe(\.canGoForward, options: [.initial]) { [weak self] v, _ in MainActor.assumeIsolated { self?.canGoForward = v.canGoForward } },
        ]
    }

    func close(_ id: Int) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].webView.stopLoading()
        tabs.remove(at: i)
        if tabs.isEmpty { _ = newTab(configuration: nil) } else if activeID == id { select(tabs[max(0, i - 1)].id) }
    }

    private var agent: String {
        switch viewport {
        case .desktop: Self.userAgent
        case .tablet: Self.tabletAgent
        case .mobile: Self.mobileAgent
        }
    }

    func setViewport(_ v: Viewport) {
        guard v != viewport else { return }
        viewport = v
        for t in tabs { t.webView.customUserAgent = agent }
        webView.reload()
    }

    func refreshServers() async {
        let list = await LocalServers.scan()
        if list != servers { servers = list }
    }

    func setDark(_ d: Bool?) {
        dark = d
        for t in tabs { t.webView.appearance = d.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil }
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
        nonisolated(unsafe) let a = args
        let task = Task<BrowserTools.Reply, Never> { @MainActor in
            await previous?.value
            self.acting += 1
            defer { self.acting -= 1 }
            var r = await self.perform(tool: tool, args: a, who: who)
            r.text += self.footer()
            return r
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    /// Вкладки (если их больше одной) и события с прошлого действия
    private func footer() -> String {
        var lines: [String] = []
        if tabs.count > 1 {
            lines.append("Вкладки: " + tabs.map { "[\($0.id)\($0.id == activeID ? ", открыта" : "")] \($0.title.isEmpty ? $0.url : $0.title)" }.joined(separator: "; "))
        }
        lines += events
        events.removeAll()
        return lines.isEmpty ? "" : "\n\n" + lines.joined(separator: "\n")
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
        func n(_ k: String) -> Double? { (args[k] as? Double) ?? (args[k] as? Int).map(Double.init) ?? (args[k] as? String).flatMap(Double.init) }
        func point() -> CGPoint? { n("x").flatMap { x in n("y").map { CGPoint(x: x, y: $0) } } }
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
            return await snapshot(["filter": "interactive"])
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
            return await snapshot(["filter": s("filter").isEmpty ? "visible" : s("filter"), "depth": n("depth") ?? 40, "root": s("ref")])
        case "browser_find":
            show(who, "Ищет «\(s("query").prefix(30))»")
            return await js(Self.findJS, ["query": s("query")])
        case "browser_click":
            let button = s("button").isEmpty ? "left" : s("button")
            let clicks = Int(n("clicks") ?? 1)
            show(who, clicks == 2 ? "Дважды нажимает" : (button == "right" ? "Правый клик" : "Нажимает"))
            let r = await pointer(ref: s("ref"), at: point(), button: button, clicks: clicks, modifiers: s("modifiers"))
            if r.error { return r }
            show(who, "Нажал \(r.text)")
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: "Нажато: \(r.text)")
        case "browser_hover":
            show(who, "Наводит")
            let r = await pointer(ref: s("ref"), at: point(), button: "none", clicks: 0, modifiers: "")
            if r.error { return r }
            try? await Task.sleep(for: .milliseconds(300))
            return await snapshot(["filter": "visible"], prefix: "Наведено на \(r.text)")
        case "browser_drag":
            show(who, "Перетаскивает")
            let r = await drag(fromRef: s("from_ref"), from: n("from_x").flatMap { x in n("from_y").map { CGPoint(x: x, y: $0) } },
                               toRef: s("to_ref"), to: n("to_x").flatMap { x in n("to_y").map { CGPoint(x: x, y: $0) } })
            if r.error { return r }
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: r.text)
        case "browser_type":
            show(who, "Печатает")
            let r = await js(Self.typeJS, ["ref": s("ref"), "text": args["text"] as? String ?? "", "submit": args["submit"] as? Bool ?? false,
                                           "clear": args["clear"] as? Bool ?? !s("ref").isEmpty])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: r.text)
        case "browser_select":
            show(who, "Выбирает")
            let r = await js(Self.selectJS, ["ref": s("ref"), "value": "\(args["value"] ?? "")"])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: r.text)
        case "browser_key":
            let keys = s("key")
            show(who, "Клавиша \(keys)")
            let r = await js(Self.keyJS, ["keys": keys, "repeat": max(1, min(100, Int(n("repeat") ?? 1)))])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: r.text)
        case "browser_scroll":
            show(who, "Прокручивает")
            var a: [String: Any] = ["ref": s("ref"), "direction": s("direction").isEmpty ? "down" : s("direction"), "amount": n("amount") ?? 1]
            if let p = point() { a["x"] = p.x; a["y"] = p.y }
            let r = await js(Self.scrollJS, a)
            if r.error { return r }
            return await snapshot(["filter": "visible"], prefix: r.text)
        case "browser_screenshot":
            show(who, "Смотрит")
            var r = await screenshot(region: nil)
            if let png = r.image, !s("save_to").isEmpty {
                let path = (s("save_to") as NSString).expandingTildeInPath
                do {
                    try png.write(to: URL(fileURLWithPath: path))
                    r.text += " Сохранено: \(path)"
                } catch { r.text += " Сохранить в \(path) не вышло: \(error.localizedDescription)" }
            }
            return r
        case "browser_zoom":
            show(who, "Рассматривает")
            let reg = (args["region"] as? [Any])?.compactMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? []
            guard reg.count == 4, reg[2] > reg[0], reg[3] > reg[1] else { return .init(text: "region — [x0, y0, x1, y1] в точках страницы.", error: true) }
            return await screenshot(region: CGRect(x: reg[0], y: reg[1], width: reg[2] - reg[0], height: reg[3] - reg[1]))
        case "browser_text":
            show(who, "Читает текст")
            return await js(Self.textJS, [:])
        case "browser_upload":
            show(who, "Загружает файлы")
            let paths = (args["paths"] as? [String] ?? [s("path")]).filter { !$0.isEmpty }.map { ($0 as NSString).expandingTildeInPath }
            var files: [[String: String]] = []
            var total = 0
            for p in paths {
                let name = (p as NSString).lastPathComponent.lowercased()
                if name.hasPrefix(".env") || [".pem", ".key", ".p12"].contains(where: name.hasSuffix) || p.contains("/.ssh/") {
                    return .init(text: "\(name) похож на ключ или пароль — такое не загружаю.", error: true)
                }
                guard let d = FileManager.default.contents(atPath: p) else { return .init(text: "Нет такого файла: \(p)", error: true) }
                total += d.count
                guard total <= 10_000_000 else { return .init(text: "Больше 10 МБ за раз не загружаю.", error: true) }
                let ext = (p as NSString).pathExtension
                let mime = UTTypeMime.mime(ext)
                files.append(["name": (p as NSString).lastPathComponent, "type": mime, "b64": d.base64EncodedString()])
            }
            guard !files.isEmpty else { return .init(text: "Укажи paths — пути к файлам.", error: true) }
            let r = await js(Self.uploadJS, ["ref": s("ref"), "files": files])
            if r.error { return r }
            await settle(started: false)
            return await snapshot(["filter": "interactive"], prefix: r.text)
        case "browser_console":
            show(who, "Смотрит консоль")
            return await js(Self.consoleJS, ["pattern": s("pattern"), "errors": args["only_errors"] as? Bool ?? false], world: .page)
        case "browser_network":
            show(who, "Смотрит запросы")
            return await js(Self.networkJS, ["pattern": s("pattern")], world: .page)
        case "browser_js":
            show(who, "Выполняет скрипт")
            let code = args["code"] as? String ?? ""
            let body = code.contains("return") ? code : "return eval(\(Self.quoted(code)));"
            return await js("const __r = await (async () => { \(body) })(); return typeof __r === 'string' ? __r : JSON.stringify(__r, null, 1);",
                            [:], world: .page)
        case "browser_wait":
            let text = s("text")
            show(who, text.isEmpty ? "Ждёт" : "Ждёт «\(text.prefix(30))»")
            let limit = Date().addingTimeInterval(min(n("seconds") ?? (text.isEmpty ? 2 : 10), 30))
            while Date() < limit {
                if !text.isEmpty, (try? await webView.callAsyncJavaScript("return document.body ? document.body.innerText.includes(t) : false",
                                                                         arguments: ["t": text], in: nil, contentWorld: .defaultClient)) as? Bool == true {
                    return await snapshot(["filter": "interactive"], prefix: "Появилось «\(text)».")
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            return text.isEmpty ? await snapshot(["filter": "interactive"]) : .init(text: "Текст «\(text)» не появился.", error: true)
        case "browser_tabs":
            let action = s("action").isEmpty ? "list" : s("action")
            switch action {
            case "new":
                show(who, "Новая вкладка")
                newTab(configuration: nil)
                if let u = Self.address(s("url")) { open(u); await settle(started: true) }
            case "switch":
                guard let id = n("tab").map(Int.init), tabs.contains(where: { $0.id == id }) else { return .init(text: "Нет вкладки \(s("tab")).", error: true) }
                show(who, "Переходит на вкладку")
                select(id)
            case "close":
                let id = n("tab").map(Int.init) ?? activeID
                guard tabs.contains(where: { $0.id == id }) else { return .init(text: "Нет вкладки \(id).", error: true) }
                show(who, "Закрывает вкладку")
                close(id)
            default: break
            }
            return .init(text: "Вкладки:\n" + tabs.map { "[\($0.id)]\($0.id == activeID ? " (открыта)" : "") \($0.title.isEmpty ? "без названия" : $0.title) — \($0.url)" }.joined(separator: "\n"))
        case "browser_resize":
            let preset = Viewport(rawValue: s("preset")) ?? viewport
            show(who, ["mobile": "Вид телефона", "tablet": "Вид планшета", "desktop": "Вид компьютера"][preset.rawValue] ?? "Размер")
            setViewport(preset)
            switch s("color_scheme") {
            case "dark": setDark(true)
            case "light": setDark(false)
            case "system": setDark(nil)
            default: break
            }
            await settle(started: true)
            let size = preset.size.map { "\(Int($0.width))×\(Int($0.height))" } ?? "во всю панель"
            return .init(text: "Вид: \(preset.rawValue) (\(size)), схема: \(dark.map { $0 ? "тёмная" : "светлая" } ?? "как в системе").")
        case "browser_servers":
            show(who, "Смотрит запущенные серверы")
            await refreshServers()
            if servers.isEmpty { return .init(text: "Локальных серверов сейчас нет.") }
            return .init(text: "Запущено на этом Маке:\n" + servers.map {
                "http://localhost:\($0.port) — \($0.process)\($0.title.map { $0.isEmpty ? "" : ", «\($0)»" } ?? ", не веб-страница")"
            }.joined(separator: "\n"))
        case "browser_batch":
            let steps = args["actions"] as? [[String: Any]] ?? []
            guard !steps.isEmpty else { return .init(text: "actions — список {tool, args}.", error: true) }
            var out: [String] = []
            var last = BrowserTools.Reply(text: "")
            for (i, st) in steps.enumerated() {
                let t = st["tool"] as? String ?? ""
                let name = t.hasPrefix("browser_") ? t : "browser_" + t
                guard name != "browser_batch", BrowserTools.names.contains(name) else {
                    out.append("\(i + 1). \(t): нет такого действия"); last.error = true; break
                }
                last = await perform(tool: name, args: st["args"] as? [String: Any] ?? [:], who: who)
                out.append("\(i + 1). \(name): " + (i == steps.count - 1 || last.error ? last.text : String(last.text.split(separator: "\n").first ?? "")))
                if last.error {
                    out.append("Остальное не выполнено: предыдущее действие не удалось.")
                    break
                }
            }
            return .init(text: out.joined(separator: "\n"), image: last.image, error: last.error)
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

    private func snapshot(_ a: [String: Any], prefix: String? = nil) async -> BrowserTools.Reply {
        var args = a
        args["max"] = 14000
        if args["depth"] == nil { args["depth"] = 40 }
        if args["root"] == nil { args["root"] = "" }
        var r = await js(Self.snapshotJS, args)
        if !r.error {
            var head = "Страница: \(title.isEmpty ? "без названия" : title)\nАдрес: \(url)\n"
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

    // MARK: мышь — настоящими событиями macOS, если панель видна (страница считает их действиями человека)

    /// Точка элемента (центр, после прокрутки к нему) или сама точка
    private func target(ref: String, at p: CGPoint?) async -> (CGPoint, String)? {
        if !ref.isEmpty {
            let r = await js(Self.locateJS, ["ref": ref])
            guard !r.error, let d = try? JSONSerialization.jsonObject(with: Data(r.text.utf8)) as? [String: Any],
                  let x = d["x"] as? Double, let y = d["y"] as? Double else { return nil }
            return (CGPoint(x: x, y: y), d["name"] as? String ?? ref)
        }
        return p.map { ($0, "точку \(Int($0.x)), \(Int($0.y))") }
    }

    /// Панель на экране, и страница в настоящем масштабе: тогда события идут в WebKit как от мыши
    private var native: Bool {
        webView.window != nil && webView.bounds.width > 50 && webView.bounds.height > 50 && webView.magnification == 1
    }

    private func nsEvent(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        guard let window = webView.window else { return nil }
        let inView = webView.isFlipped ? p : CGPoint(x: p.x, y: webView.bounds.height - p.y)
        return NSEvent.mouseEvent(with: type, location: webView.convert(inView, to: nil), modifierFlags: modifiers,
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp || type == .rightMouseUp ? 0 : 1)
    }

    static func modifierFlags(_ s: String) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        for part in s.lowercased().split(whereSeparator: { $0 == "+" || $0 == " " }) {
            switch part {
            case "shift": f.insert(.shift)
            case "ctrl", "control": f.insert(.control)
            case "alt", "option", "opt": f.insert(.option)
            case "cmd", "command", "meta", "super": f.insert(.command)
            default: break
            }
        }
        return f
    }

    private func pointer(ref: String, at p: CGPoint?, button: String, clicks: Int, modifiers: String) async -> BrowserTools.Reply {
        guard let (pt, name) = await target(ref: ref, at: p) else {
            return .init(text: "Нет элемента \(ref) — метки меняются после перехода, прочитай страницу заново (browser_read_page).", error: true)
        }
        if native {
            let mods = Self.modifierFlags(modifiers)
            guard let move = nsEvent(.mouseMoved, pt, clicks: 0, modifiers: mods) else { return .init(text: "Нет окна.", error: true) }
            webView.mouseMoved(with: move)
            // WebKit не всегда принимает движение мыши, пока окно не в фокусе, — наведение дублируем событиями страницы
            if clicks == 0 { _ = await js(Self.clickJS, ["x": pt.x, "y": pt.y, "button": "none", "clicks": 0, "modifiers": ""]) }
            if clicks > 0 {
                for c in 1...max(1, min(3, clicks)) {
                    switch button {
                    case "right":
                        if let d = nsEvent(.rightMouseDown, pt, clicks: c, modifiers: mods), let u = nsEvent(.rightMouseUp, pt, clicks: c, modifiers: mods) {
                            webView.rightMouseDown(with: d); webView.rightMouseUp(with: u)
                        }
                    case "middle":
                        if let d = nsEvent(.otherMouseDown, pt, clicks: c, modifiers: mods), let u = nsEvent(.otherMouseUp, pt, clicks: c, modifiers: mods) {
                            webView.otherMouseDown(with: d); webView.otherMouseUp(with: u)
                        }
                    default:
                        if let d = nsEvent(.leftMouseDown, pt, clicks: c, modifiers: mods), let u = nsEvent(.leftMouseUp, pt, clicks: c, modifiers: mods) {
                            webView.mouseDown(with: d); webView.mouseUp(with: u)
                        }
                    }
                }
            }
            return .init(text: name)
        }
        // панель свёрнута — те же события из скрипта
        let r = await js(Self.clickJS, ["x": pt.x, "y": pt.y, "button": button, "clicks": clicks, "modifiers": modifiers.lowercased()])
        return r.error ? r : .init(text: name)
    }

    private func drag(fromRef: String, from: CGPoint?, toRef: String, to: CGPoint?) async -> BrowserTools.Reply {
        guard let (a, an) = await target(ref: fromRef, at: from), let (b, bn) = await target(ref: toRef, at: to) else {
            return .init(text: "Нужны from_ref или from_x/from_y и to_ref или to_x/to_y.", error: true)
        }
        if native, let d = nsEvent(.leftMouseDown, a, clicks: 1, modifiers: []) {
            webView.mouseDown(with: d)
            for i in 1...12 {
                let t = Double(i) / 12
                if let m = nsEvent(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), clicks: 1, modifiers: []) {
                    webView.mouseDragged(with: m)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if let u = nsEvent(.leftMouseUp, b, clicks: 1, modifiers: []) { webView.mouseUp(with: u) }
        } else {
            let r = await js(Self.dragJS, ["ax": a.x, "ay": a.y, "bx": b.x, "by": b.y])
            if r.error { return r }
        }
        return .init(text: "Перетащено: \(an) → \(bn).")
    }

    private func screenshot(region: CGRect?) async -> BrowserTools.Reply {
        guard webView.bounds.width > 10 else { return .init(text: "Браузер свёрнут — открой панель, чтобы снять экран.", error: true) }
        do {
            let cfg = WKSnapshotConfiguration()
            if let region {
                cfg.rect = region
                // кусок — крупнее: до 1280 точек в ширину
                cfg.snapshotWidth = NSNumber(value: Double(min(1280, region.width * 3)))
            }
            let image = try await webView.takeSnapshot(configuration: cfg)
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
            let note = region == nil
                ? "Точки x, y для действий — в масштабе страницы: координата на снимке ÷ \(String(format: "%.2f", scale))."
                : "Увеличенный кусок \(Int(region!.minX)),\(Int(region!.minY))–\(Int(region!.maxX)),\(Int(region!.maxY))."
            return .init(text: "Снимок: \(title) — \(url). \(note) Снимок виден человеку в чате.", image: png)
        } catch {
            return .init(text: "Снимок не получился: \(error.localizedDescription)", error: true)
        }
    }

    nonisolated static func quoted(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }
}

/// MIME по расширению — для загрузки файлов на страницу
enum UTTypeMime {
    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        case "pdf": "application/pdf"
        case "txt", "md": "text/plain"
        case "csv": "text/csv"
        case "json": "application/json"
        case "html", "htm": "text/html"
        case "zip": "application/zip"
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        case "mp3": "audio/mpeg"
        default: "application/octet-stream"
        }
    }
}

extension BrowserModel: WKUIDelegate, WKNavigationDelegate {
    /// Страница открывает окно — новая вкладка, как в обычном браузере (агент узнает об этом в следующем ответе)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let tab = newTab(configuration: configuration)
        events.append("Страница открыла новую вкладку [\(tab.id)] — она теперь открыта: \(navigationAction.request.url?.absoluteString ?? "")")
        wantsOpen += 1
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let t = tabs.first(where: { $0.webView === webView }) { close(t.id) }
    }

    // Окна страницы: пока работает агент — не ждут человека (иначе агент встанет), ответ — осторожный
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        if acting > 0 { events.append("Страница показала сообщение: «\(message.prefix(300))» — закрыто."); return }
        let a = NSAlert()
        a.messageText = message
        a.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        if acting > 0 {
            events.append("Страница спросила: «\(message.prefix(300))» — отвечено «Отмена». Если нужно «OK» — спроси человека.")
            return false
        }
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Отмена")
        return a.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        if acting > 0 { events.append("Страница попросила ввести: «\(prompt.prefix(300))» — отменено."); return nil }
        let a = NSAlert()
        a.messageText = prompt
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Отмена")
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Загрузка файлов — в «Загрузки»
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
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
        downloads[ObjectIdentifier(download)] = url
        events.append("Скачивается: \(suggestedFilename)")
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        let url = downloads.removeValue(forKey: ObjectIdentifier(download))
        events.append("Скачано: \(url?.path ?? "в «Загрузки»")")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        events.append("Скачать не вышло: \(error.localizedDescription)")
    }
}
