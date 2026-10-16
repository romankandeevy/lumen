import Foundation
import LumenCore
import LumenStorage

/// Навыки с GitHub (§8.2–8.3): каталог Anthropic (github.com/anthropics/skills) и установка по ссылке.
/// Запросов к API GitHub на установку два (коммит и дерево файлов), файлы качаются с raw.githubusercontent.com —
/// без токена лимит API 60 в час, этого хватает.
public struct GitHubSkills: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Где лежит навык: репозиторий, путь к папке, ветка или коммит
    public struct Location: Sendable, Equatable {
        public var owner: String
        public var repo: String
        public var path: String
        public var ref: String

        public init(owner: String, repo: String, path: String, ref: String = "main") {
            self.owner = owner
            self.repo = repo
            self.path = path
            self.ref = ref
        }

        /// `github:owner/repo/path@ref` — так источник записан в lock.json
        public var source: String { "github:\(owner)/\(repo)/\(path)@\(ref)" }

        /// Понимает ссылки на папку (`/tree/ref/path`), на SKILL.md (`/blob/ref/path/SKILL.md`), raw-ссылки и `github:…`
        public init?(link: String) {
            var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("github:") {
                s = String(s.dropFirst(7))
                var ref = "main"
                if let at = s.lastIndex(of: "@") { ref = String(s[s.index(after: at)...]); s = String(s[..<at]) }
                let parts = s.split(separator: "/").map(String.init)
                guard parts.count >= 2 else { return nil }
                self.init(owner: parts[0], repo: parts[1], path: parts.dropFirst(2).joined(separator: "/"), ref: ref)
                return
            }
            guard let url = URL(string: s), let host = url.host else { return nil }
            var parts = url.path.split(separator: "/").map(String.init)
            if host == "raw.githubusercontent.com" {
                guard parts.count >= 3 else { return nil }
                if parts.last == "SKILL.md" { parts.removeLast() }
                self.init(owner: parts[0], repo: parts[1], path: parts.dropFirst(3).joined(separator: "/"), ref: parts[2])
                return
            }
            guard host.hasSuffix("github.com"), parts.count >= 2 else { return nil }
            let owner = parts[0], repo = parts[1].replacingOccurrences(of: ".git", with: "")
            if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
                if parts.last == "SKILL.md" { parts.removeLast() }
                self.init(owner: owner, repo: repo, path: parts.dropFirst(4).joined(separator: "/"), ref: parts[3])
            } else {
                self.init(owner: owner, repo: repo, path: "", ref: "main")
            }
        }
    }

    /// Строка каталога
    public struct Entry: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let description: String
        public let location: Location
    }

    public static let catalog = Location(owner: "anthropics", repo: "skills", path: "skills")

    /// Навыки из каталога Anthropic: список папок (1 запрос к API) и описания из их SKILL.md
    public func catalogEntries(_ at: Location = GitHubSkills.catalog) async throws -> [Entry] {
        let list = try await api("repos/\(at.owner)/\(at.repo)/contents/\(at.path)?ref=\(at.ref)")
        guard let items = list as? [[String: Any]] else { throw SkillError.download("Каталог не открылся") }
        let dirs = items.filter { $0["type"] as? String == "dir" }.compactMap { $0["name"] as? String }
        return await withTaskGroup(of: Entry?.self) { group in
            for d in dirs {
                group.addTask {
                    let loc = Location(owner: at.owner, repo: at.repo, path: at.path + "/" + d, ref: at.ref)
                    guard let text = try? await raw(loc, "SKILL.md"), let parsed = SkillFormat.parse(text) else { return nil }
                    return Entry(name: parsed.fields["name"] ?? d, description: parsed.fields["description"] ?? "", location: loc)
                }
            }
            var out: [Entry] = []
            for await e in group { if let e { out.append(e) } }
            return out.sorted { $0.name < $1.name }
        }
    }

    /// Последний коммит, менявший папку навыка
    public func commit(_ at: Location) async throws -> String {
        let list = try await api("repos/\(at.owner)/\(at.repo)/commits?sha=\(at.ref)&path=\(at.path)&per_page=1")
        guard let sha = (list as? [[String: Any]])?.first?["sha"] as? String else { throw SkillError.download("Не нашёл навык по ссылке") }
        return sha
    }

    /// Поставить навык. Тот же источник и коммит уже стоят — ничего не качаем.
    public func install(_ at: Location, into library: SkillLibrary, origin: SkillInfo.Origin) async throws -> SkillLibrary.InstallResult {
        let sha = try await commit(at)
        if let (name, _) = library.lock().first(where: { $0.value.source == at.source && $0.value.commit == sha }) {
            return .alreadyInstalled(name)
        }
        let tree = try await api("repos/\(at.owner)/\(at.repo)/git/trees/\(sha)?recursive=1")
        let prefix = at.path.isEmpty ? "" : at.path + "/"
        let files = ((tree as? [String: Any])?["tree"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "blob" }
            .compactMap { $0["path"] as? String }
            .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
        guard files.contains("SKILL.md") else { throw SkillError.download("По ссылке нет SKILL.md") }
        guard files.count <= 200 else { throw SkillError.download("В навыке слишком много файлов (\(files.count))") }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let pinned = Location(owner: at.owner, repo: at.repo, path: at.path, ref: sha)
        for f in files {
            let data = try await rawData(pinned, f)
            let dest = stage.appendingPathComponent(f)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }
        return try library.install(from: stage, source: at.source, commit: sha, origin: origin)
    }

    // MARK: сеть

    private func api(_ path: String) async throws -> Any {
        var req = URLRequest(url: URL(string: "https://api.github.com/" + path)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Lumen", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 || code == 429 { throw SkillError.download("GitHub просит подождать: лимит запросов без входа — 60 в час") }
        if code == 404 { throw SkillError.download("На GitHub такого нет — проверь ссылку") }
        guard code == 200 else { throw SkillError.download("GitHub ответил \(code)") }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func rawData(_ at: Location, _ file: String) async throws -> Data {
        let path = [at.path, file].filter { !$0.isEmpty }.joined(separator: "/")
        let url = URL(string: "https://raw.githubusercontent.com/\(at.owner)/\(at.repo)/\(at.ref)/" +
                      (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))!
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw SkillError.download("Не скачался \(file)") }
        return data
    }

    private func raw(_ at: Location, _ file: String) async throws -> String {
        String(decoding: try await rawData(at, file), as: UTF8.self)
    }
}
