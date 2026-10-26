import AppKit
import Foundation
import Observation
import WebKit

/// Страница, на которой побывал человек или агент
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { url }
    let url: String
    var title: String
    var visited: Date
    var count: Int
}

/// История браузера: последние 1500 страниц. Лежит в базе Lumen (`browser.history`), в запросы к модели не попадает
@MainActor @Observable
final class BrowserHistory {
    private(set) var entries: [HistoryEntry] = []
    @ObservationIgnored var persist: ([HistoryEntry]) -> Void = { _ in }
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let limit = 1500

    func load(_ list: [HistoryEntry]) { entries = list }

    /// Записать посещение (только http и https, без пустых адресов)
    func visit(url: String, title: String) {
        guard let u = URL(string: url), ["http", "https"].contains(u.scheme ?? ""), u.host != nil else { return }
        let key = Self.key(url)
        if let i = entries.firstIndex(where: { Self.key($0.url) == key }) {
            var e = entries.remove(at: i)
            e.visited = Date()
            e.count += 1
            if !title.isEmpty { e.title = title }
            entries.insert(e, at: 0)
        } else {
            entries.insert(HistoryEntry(url: url, title: title, visited: Date(), count: 1), at: 0)
            if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        }
        scheduleSave()
    }

    /// Название пришло после загрузки — подставить в уже записанное посещение
    func retitle(_ url: String, _ title: String) {
        let key = Self.key(url)
        guard let i = entries.firstIndex(where: { Self.key($0.url) == key }), entries[i].title != title else { return }
        entries[i].title = title
        scheduleSave()
    }

    func remove(_ url: String) {
        entries.removeAll { $0.url == url }
        scheduleSave()
    }

    func clear() {
        entries = []
        scheduleSave()
    }

    /// Адрес без «#якоря» и последнего «/» — одна и та же страница не двоится
    static func key(_ s: String) -> String {
        var t = s
        if let h = t.firstIndex(of: "#") { t = String(t[..<h]) }
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// Подсказки в адресной строке: сначала то, что начинается с набранного, потом то, что содержит; чаще посещаемое выше
    func suggestions(for text: String, limit: Int = 6) -> [HistoryEntry] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        func short(_ e: HistoryEntry) -> String {
            var s = e.url.lowercased()
            for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
            if s.hasPrefix("www.") { s.removeFirst(4) }
            return s
        }
        let starts = entries.filter { short($0).hasPrefix(q) }.sorted { $0.count > $1.count }
        let has = entries.filter { !short($0).hasPrefix(q) && (short($0).contains(q) || $0.title.lowercased().contains(q)) }
        return Array((starts + has).prefix(limit))
    }

    /// Свежие, по дням — для страницы «История»
    func recent(_ n: Int = 200) -> [HistoryEntry] { Array(entries.prefix(n)) }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.persist(self.entries)
        }
    }
}

/// Значки сайтов для вкладок: берутся со страницы (`<link rel=icon>` или /favicon.ico) и держатся в памяти
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private var images: [String: NSImage] = [:]
    private var loading: Set<String> = []

    func image(for host: String) -> NSImage? { images[host] }

    nonisolated static func isPrivate(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.isEmpty || h == "localhost" || h.hasSuffix(".localhost") || h.hasSuffix(".local") || h.hasSuffix(".internal") || h.contains(":") { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (0, _), (169, 254), (192, 168): return true
        case (172, 16...31), (100, 64...127): return true
        default: return false
        }
    }

    /// Скрипт возвращает адрес значка; загрузка один раз на сайт
    func fetch(host: String, from webView: WKWebView, done: @escaping @MainActor () -> Void) {
        guard images[host] == nil, !loading.contains(host), let base = webView.url else { return }
        loading.insert(host)
        Task { @MainActor in
            defer { loading.remove(host) }
            let js = """
            const l = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')]
              .map(e => ({href: e.href, size: parseInt((e.sizes && e.sizes[0] || '').split('x')[0]) || 0}))
              .sort((a, b) => Math.abs(a.size - 32) - Math.abs(b.size - 32));
            return l.length ? l[0].href : '';
            """
            let href = (try? await webView.callAsyncJavaScript(js, contentWorld: .defaultClient)) as? String ?? ""
            let candidates = [URL(string: href), URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL].compactMap { $0 }.filter { !$0.absoluteString.isEmpty }
            // только публичные сайты: страница не должна заставить Lumen стучаться в локальную сеть
            for u in candidates where ["http", "https"].contains(u.scheme ?? "") && !Self.isPrivate(u.host ?? "") {
                var req = URLRequest(url: u)
                req.timeoutInterval = 6
                if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
                   data.count < 400_000, let img = NSImage(data: data), img.size.width > 1 {
                    images[host] = img
                    done()
                    return
                }
            }
        }
    }
}
