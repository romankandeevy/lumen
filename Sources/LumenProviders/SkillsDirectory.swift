import Foundation
import LumenCore
import LumenStorage

/// Каталог навыков skills.sh (Vercel, «The Open Agent Skills Ecosystem») — тот же, что у `npx skills`.
/// Рейтинг берётся со страниц сайта (`/`, `/trending`, `/hot` — данные лежат в странице), поиск — `api/search`,
/// навык целиком — `api/download/<owner>/<repo>/<skill>` (файлы и хэш; лимитов GitHub нет).
public struct SkillsDirectory: Sendable {
    public var session: URLSession
    public static let base = URL(string: "https://skills.sh")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public enum View: String, Sendable, CaseIterable {
        case allTime = "", trending = "trending", hot = "hot"
    }

    public struct Entry: Sendable, Equatable, Identifiable, Hashable {
        public var id: String { "\(source)/\(skillID)" }
        /// owner/repo
        public let source: String
        public let skillID: String
        public let name: String
        public let installs: Int
        /// Установки по неделям за 8 недель — для линии активности
        public let weekly: [Int]
        public let official: Bool

        public init(source: String, skillID: String, name: String, installs: Int, weekly: [Int] = [], official: Bool = false) {
            self.source = source
            self.skillID = skillID
            self.name = name
            self.installs = installs
            self.weekly = weekly
            self.official = official
        }

        /// Источник в lock.json
        public var lockSource: String { "skills.sh:\(source)/\(skillID)" }
        public var page: URL { SkillsDirectory.base.appendingPathComponent("\(source)/\(skillID)") }
    }

    public struct Board: Sendable, Equatable {
        public let entries: [Entry]
        /// Сколько навыков в каталоге и сколько всего установок (для «За всё время (…)»)
        public let totalSkills: Int?
        public let allTimeTotal: Int?
    }

    /// Рейтинг: за всё время, тренды за 24 часа или «горячее»
    public func board(_ view: View) async throws -> Board {
        let url = view == .allTime ? Self.base : Self.base.appendingPathComponent(view.rawValue)
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw SkillError.download("skills.sh не открылся") }
        return try Self.parseBoard(String(decoding: data, as: UTF8.self))
    }

    /// Достать рейтинг из страницы: потоки `self.__next_f.push([1,"…"])` → массив `"initialSkills":[…]` и итоги
    static func parseBoard(_ html: String) throws -> Board {
        var payload = ""
        let pattern = try NSRegularExpression(pattern: #"self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)"#, options: [.dotMatchesLineSeparators])
        for m in pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html),
                  let s = try? JSONSerialization.jsonObject(with: Data(("\"" + html[r] + "\"").utf8), options: [.fragmentsAllowed]) as? String else { continue }
            payload += s
        }
        guard let start = payload.range(of: "\"initialSkills\":") else { throw SkillError.download("На skills.sh поменялась страница — рейтинг не прочитался") }
        // массив до парной скобки
        var depth = 0, inString = false, escaped = false
        var end = start.upperBound
        var i = start.upperBound
        while i < payload.endIndex {
            let ch = payload[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" { inString = true }
            else if ch == "[" { depth += 1 }
            else if ch == "]" { depth -= 1; if depth == 0 { end = payload.index(after: i); break } }
            i = payload.index(after: i)
        }
        let arrayText = payload[start.upperBound..<end]
        guard let items = try JSONSerialization.jsonObject(with: Data(arrayText.utf8)) as? [[String: Any]] else {
            throw SkillError.download("Рейтинг skills.sh не прочитался")
        }
        let entries = items.compactMap { o -> Entry? in
            guard let source = o["source"] as? String, let id = o["skillId"] as? String else { return nil }
            return Entry(source: source, skillID: id, name: o["name"] as? String ?? id, installs: o["installs"] as? Int ?? 0,
                         weekly: o["weeklyInstalls"] as? [Int] ?? [], official: o["isOfficial"] as? Bool ?? false)
        }
        func number(_ key: String) -> Int? {
            guard let r = payload[end...].range(of: "\"\(key)\":") else { return nil }
            return Int(payload[r.upperBound...].prefix { $0.isNumber })
        }
        return Board(entries: entries, totalSkills: number("totalSkills"), allTimeTotal: number("allTimeTotal"))
    }

    /// Поиск (как `npx skills find`): от двух букв, по числу установок
    public func search(_ query: String) async throws -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(url: Self.base.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "50")]
        let (data, resp) = try await session.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = obj["skills"] as? [[String: Any]] else { throw SkillError.download("Поиск skills.sh не ответил") }
        return skills.compactMap { o in
            guard let source = o["source"] as? String, let id = o["skillId"] as? String else { return nil }
            return Entry(source: source, skillID: id, name: o["name"] as? String ?? id, installs: o["installs"] as? Int ?? 0)
        }
        .sorted { $0.installs > $1.installs }
    }

    /// Файлы навыка и хэш снимка
    public func download(_ e: Entry) async throws -> (files: [(path: String, contents: String)], hash: String?) {
        let url = Self.base.appendingPathComponent("api/download/\(e.source)/\(e.skillID)")
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { throw SkillError.download("Навык «\(e.name)» не скачался") }
        return (files.compactMap { f in (f["path"] as? String).map { ($0, f["contents"] as? String ?? "") } }, obj["hash"] as? String)
    }

    /// Только SKILL.md — чтобы показать описание до установки
    public func skillText(_ e: Entry) async throws -> String? {
        try await download(e).files.first { $0.path.lowercased() == "skill.md" }?.contents
    }

    /// Поставить навык. Тот же снимок уже стоит (по хэшу skills.sh или по содержимому) — ничего не меняем.
    public func install(_ e: Entry, into library: SkillLibrary) async throws -> SkillLibrary.InstallResult {
        let (files, hash) = try await download(e)
        if let hash, let (name, _) = library.lock().first(where: { $0.value.source == e.lockSource && $0.value.commit == hash }) {
            return .alreadyInstalled(name)
        }
        guard files.contains(where: { $0.path.lowercased() == "skill.md" }) else { throw SkillError.download("В навыке нет SKILL.md") }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        for f in files {
            // пути только внутри папки навыка
            guard !f.path.hasPrefix("/"), !f.path.split(separator: "/").contains("..") else { continue }
            let dest = stage.appendingPathComponent(f.path.lowercased() == "skill.md" ? "SKILL.md" : f.path)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(f.contents.utf8).write(to: dest)
        }
        return try library.install(from: stage, source: e.lockSource, commit: hash, origin: .catalog)
    }
}
