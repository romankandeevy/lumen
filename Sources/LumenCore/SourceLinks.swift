import Foundation

/// Источник ответа: страница, на которую сослался Lumen или которую открыл по ходу (поиск в сети, ресерч)
public struct SourceLink: Equatable, Sendable, Identifiable {
    /// Адрес как написан в ответе (или открыт шагом)
    public let url: String
    /// Название, если ссылка была оформлена «[название](адрес)»
    public let title: String?

    public var id: String { SourceLinks.key(url) }

    /// Сайт без «www.»: «gamedeveloper.com»
    public var host: String {
        guard let h = URL(string: url)?.host else { return url }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

public enum SourceLinks {
    /// Один и тот же адрес с хвостами («/», «#…», utm_*) — один источник
    public static func key(_ url: String) -> String {
        guard var c = URLComponents(string: url) else { return url.lowercased() }
        c.fragment = nil
        c.queryItems = c.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var s = (c.string ?? url).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        if let r = s.range(of: "://www.") { s.replaceSubrange(r, with: "://") }
        return s
    }

    /// Источники ответа по порядку появления: ссылки из текста (markdown и голые адреса), потом открытые страницы из шагов.
    /// Пока Lumen в сети не был (шагов «web» нет) и ссылок меньше трёх — ответ не про источники, пусто.
    public static func extract(text: String, steps: [AgentStep]) -> [SourceLink] {
        let clean = stripCode(text)
        var found: [SourceLink] = []
        var seen = Set<String>()
        func add(_ link: SourceLink) {
            guard isWeb(link.url), seen.insert(link.id).inserted else { return }
            found.append(link)
        }
        // и markdown-ссылки, и голые адреса — по порядку в тексте (номер у ссылки в тексте идёт слева направо)
        var positioned: [(Int, SourceLink)] = []
        var bare = clean
        if let md = try? NSRegularExpression(pattern: #"\[([^\]\n]{1,160})\]\((https?://[^\s)]+)\)"#) {
            let ns = clean as NSString
            for m in md.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
                guard let t = Range(m.range(at: 1), in: clean), let u = Range(m.range(at: 2), in: clean) else { continue }
                positioned.append((m.range.location, SourceLink(url: trim(String(clean[u])), title: String(clean[t]))))
                // место ссылки в «голой» копии заменяем пробелами той же длины — позиции остаются верными
                bare = (bare as NSString).replacingCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
        }
        if let re = try? NSRegularExpression(pattern: #"https?://[^\s<>\]\)"'«»]+"#) {
            for m in re.matches(in: bare, range: NSRange(location: 0, length: (bare as NSString).length)) {
                if let r = Range(m.range, in: bare) { positioned.append((m.range.location, SourceLink(url: trim(String(bare[r]))))) }
            }
        }
        positioned.sort { $0.0 < $1.0 }
        positioned.forEach { add($0.1) }
        // страницы, которые Lumen открыл сам (WebFetch, браузер): их адрес — в подробностях шага
        let fetched = steps.filter { $0.kind == .web }.compactMap { s -> SourceLink? in
            guard let d = s.detail, d.hasPrefix("http") else { return nil }
            return SourceLink(url: d)
        }
        let usedWeb = steps.contains { $0.kind == .web }
        guard usedWeb || found.count >= 3 else { return [] }
        fetched.forEach(add)
        return found
    }

    /// Ответ кончается списком «Источники: • ссылка¹ • ссылка²» — те же страницы уже показаны карточками под ответом,
    /// поэтому список из текста убирается (Рома, 26.10). Режется только хвост: заголовок «Источники» (или Sources, Ссылки),
    /// а под ним одни пункты со ссылками. Всё остальное остаётся как написано.
    public static func withoutListing(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        var i = lines.count
        var items = 0
        while i > 0 {
            let t = lines[i - 1].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i -= 1; continue }
            guard isListItem(t), t.contains("http") else { break }
            items += 1
            i -= 1
        }
        guard items > 0, i > 0 else { return text }
        // над списком — заголовок («Источники:», «**Источники**», «## Источники»)
        var h = i
        while h > 0, lines[h - 1].trimmingCharacters(in: .whitespaces).isEmpty { h -= 1 }
        guard h > 0, isSourcesHeading(lines[h - 1]) else { return text }
        var kept = Array(lines[0..<(h - 1)])
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty { kept.removeLast() }
        return kept.joined(separator: "\n")
    }

    private static func isListItem(_ t: String) -> Bool {
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") || t.hasPrefix("+ ") { return true }
        // «1. », «2) »
        var digits = 0
        for ch in t {
            if ch.isNumber { digits += 1; continue }
            return digits > 0 && digits <= 3 && (ch == "." || ch == ")") && t.dropFirst(digits + 1).first == " "
        }
        return false
    }

    private static func isSourcesHeading(_ line: String) -> Bool {
        var t = line.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "*_: \t"))
        let low = t.lowercased()
        return ["источники", "источники и ссылки", "ссылки", "ссылки на источники", "sources", "references", "links"].contains(low)
    }

    private static func isWeb(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host, host.contains(".") else { return false }
        return ["http", "https"].contains(u.scheme?.lowercased() ?? "")
    }

    /// Хвостовая пунктуация после адреса в тексте («…site.com/a.» «…site.com/a,»)
    private static func trim(_ s: String) -> String {
        var t = s
        while let last = t.last, ".,;:!?»”".contains(last) { t.removeLast() }
        return t
    }

    private static func stripCode(_ text: String) -> String {
        text.components(separatedBy: "```").enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined(separator: "\n")
    }
}
