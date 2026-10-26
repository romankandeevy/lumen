import AppKit
import Foundation
import LumenCore
import WebKit

/// Что отправить из браузера в чат
enum SendKind: CaseIterable {
    case link, selection, screenshot, fullPage, text, pdf

    var title: String {
        switch self {
        case .link: "Ссылку на страницу"
        case .selection: "Выделенный текст"
        case .screenshot: "Снимок экрана"
        case .fullPage: "Всю страницу картинкой"
        case .text: "Текст страницы"
        case .pdf: "Страницу как PDF"
        }
    }

    var icon: String {
        switch self {
        case .link: "link"
        case .selection: "type"
        case .screenshot: "image"
        case .fullPage: "layers"
        case .text: "file-text"
        case .pdf: "file"
        }
    }
}

/// Пункт меню с действием
final class ClosureItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}

extension BrowserModel {
    /// Правая кнопка по странице: к обычному меню WebKit добавляется «Отправить в чат»
    func extend(_ menu: NSMenu, for view: WKWebView) {
        guard let tab = tabs.first(where: { $0.web === view }), tab.file == nil, tab.id == activeID else { return }
        menu.addItem(.separator())
        let sub = NSMenu()
        for kind in SendKind.allCases {
            sub.addItem(ClosureItem(kind.title) { [weak self] in self?.onSend?(kind) })
        }
        let item = NSMenuItem(title: "Отправить в чат", action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
    }

    // MARK: что берётся со страницы человека (открытой вкладки)

    func selectedText() async -> String {
        let r = try? await webView.callAsyncJavaScript("return String(getSelection());", contentWorld: .defaultClient)
        return (r as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pageText() async -> String {
        let r = try? await webView.callAsyncJavaScript(Self.textJS, arguments: ["args": [String: Any]()], contentWorld: .defaultClient)
        return r as? String ?? ""
    }

    func visibleImage() async -> NSImage? {
        guard webView.window != nil, webView.bounds.width > 10 else { return nil }
        return try? await webView.takeSnapshot(configuration: WKSnapshotConfiguration())
    }

    func pagePDF() async -> Data? {
        let cfg = WKPDFConfiguration()
        let size = (try? await webView.callAsyncJavaScript("const d = document.documentElement, b = document.body; return [Math.max(d.scrollWidth, b ? b.scrollWidth : 0, innerWidth), Math.max(d.scrollHeight, b ? b.scrollHeight : 0, innerHeight)];",
                                                           contentWorld: .defaultClient)) as? [Double] ?? []
        if size.count == 2 { cfg.rect = CGRect(x: 0, y: 0, width: size[0], height: min(30_000, size[1])) }
        return try? await webView.pdf(configuration: cfg)
    }

    /// Вся страница картинкой — для человека берётся его открытая вкладка
    func fullImageOfActive() async -> NSImage? { await fullPageImage(of: webView) }
}

extension AppModel {
    /// Выделенное в макете — в чат: картинка слоя и строка «Макет «…», выделено: «…» (id …)», дальше человек пишет, что поменять
    func sendDesignSelection() {
        let b = browser
        Task { @MainActor in
            guard let pick = await b.designSelection() else { b.say("Выдели слой в макете — потом «В чат»"); return }
            if let img = pick.image { attachImage(img, name: "Макет — \(pick.file) — выделенное.png") }
            draftInbox += "Макет «\(pick.file)», выделено: " + pick.lines.joined(separator: ", ") + ".\nЧто поменять: "
            b.say("Выделенное отправлено в поле ввода — напиши, что поменять")
        }
    }

    /// Новый макет руками: «Макет 1», «Макет 2»… — открывается в браузере, агент подхватит его по названию
    func newDesign() {
        let b = browser
        let existing = Set(b.designFiles().map { $0.deletingPathExtension().lastPathComponent })
        var n = 1
        while existing.contains("Макет \(n)") { n += 1 }
        openDesign("Макет \(n)")
    }

    func openDesign(_ name: String) {
        let b = browser
        browserOpen = true
        Task { @MainActor in
            do {
                let blank = b.active.file == nil && b.blankPage && b.active.id != b.agentTabID
                _ = try await b.openDesign(name: name, in: blank ? b.active : nil, select: true)
            } catch {
                b.say(error.localizedDescription)
            }
        }
    }

    /// «Отправить в чат» из браузера: ссылка и выделенное — в поле ввода, картинки и файлы — вложениями
    func sendFromBrowser(_ kind: SendKind) {
        let b = browser
        guard b.active.file == nil, !b.blankPage else { b.say("Открой страницу, чтобы отправить её в чат"); return }
        let title = b.title.isEmpty ? (URL(string: b.url)?.host ?? "страница") : b.title
        let safe = title.replacingOccurrences(of: "/", with: "-").prefix(60)
        Task { @MainActor in
            switch kind {
            case .link:
                draftInbox += "\(title) — \(b.url)\n"
                b.say("Ссылка добавлена в поле ввода")
            case .selection:
                let t = await b.selectedText()
                if t.isEmpty { b.say("Выдели текст на странице"); return }
                quoteToChat(t, from: title)
                b.say("Выделенное добавлено в поле ввода")
            case .screenshot:
                guard let img = await b.visibleImage() else { b.say("Снимок не получился"); return }
                attachImage(img, name: "Снимок — \(safe).png")
                b.say("Снимок прикреплён к чату")
            case .fullPage:
                guard let img = await b.fullImageOfActive() else { b.say("Снимок страницы не получился"); return }
                attachImage(img, name: "Страница — \(safe).png")
                b.say("Вся страница прикреплена к чату")
            case .text:
                let t = await b.pageText()
                guard !t.isEmpty else { b.say("На странице нет текста"); return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).md")
                let body = "# \(title)\n\n\(b.url)\n\n\(t)\n"
                guard (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
                attachToChat(url)
                try? FileManager.default.removeItem(at: url)
                b.say("Текст страницы прикреплён к чату")
            case .pdf:
                guard let data = await b.pagePDF() else { b.say("PDF не получился"); return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
                guard (try? data.write(to: url)) != nil else { return }
                attachToChat(url)
                try? FileManager.default.removeItem(at: url)
                b.say("PDF прикреплён к чату")
            }
        }
    }

    /// Файлы, брошенные на страницу, открываются в браузере со своим превью (веб-страницы и папки — как есть)
    func openDropped(_ urls: [URL]) -> Bool {
        var any = false
        for u in urls where !u.hasDirectoryPath && FileKind.of(u) != .other && FileKind.of(u) != .web {
            openFile(u)
            any = true
        }
        return any
    }
}
