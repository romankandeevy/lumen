import Foundation
import LumenCore

/// Навыки на диске: `~/Library/Application Support/Lumen/skills/<имя>/SKILL.md`,
/// откуда и какой хэш — в `skills/.hub/lock.json`. Общая для приложения и lumen-mcp.
public struct SkillLibrary: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var lockURL: URL { root.appendingPathComponent(".hub/lock.json") }

    public func lock() -> [String: SkillInfo] {
        guard let d = try? Data(contentsOf: lockURL) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: SkillInfo].self, from: d)) ?? [:]
    }

    private func saveLock(_ l: [String: SkillInfo]) throws {
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(l).write(to: lockURL, options: .atomic)
    }

    /// Все навыки, по имени
    public func all() -> [Skill] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let l = lock()
        return dirs.compactMap { dir -> Skill? in
            guard let text = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8),
                  let parsed = SkillFormat.parse(text) else { return nil }
            let name = parsed.fields["name"] ?? dir.lastPathComponent
            let info = l[dir.lastPathComponent] ?? SkillInfo(origin: .created, sha256: SkillFormat.sha256(of: dir))
            return Skill(name: name, description: parsed.fields["description"] ?? "", body: parsed.body,
                         files: SkillFormat.files(in: dir).filter { $0 != "SKILL.md" }.sorted(), folder: dir, info: info)
        }
        .sorted { $0.name < $1.name }
    }

    public func skill(_ name: String) -> Skill? { all().first { $0.name == name } }

    /// Включённые навыки; `only` — набор имён (навыки бота)
    public func enabled(only: Set<String>? = nil) -> [Skill] {
        all().filter { $0.info.enabled && (only == nil || only!.contains($0.name)) }
    }

    /// Сохранить свой навык (созданный руками, с Lumen или «сам научился»)
    @discardableResult
    public func save(name: String, description: String, body: String, origin: SkillInfo.Origin) throws -> Skill {
        let problems = SkillFormat.problems(name: name, description: description, body: body)
        guard problems.isEmpty else { throw SkillError.invalid(problems) }
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try SkillFormat.render(name: name, description: description, body: body).write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        var l = lock()
        var info = l[name] ?? SkillInfo(origin: origin)
        info.sha256 = SkillFormat.sha256(of: dir)
        info.warnings = SkillFormat.scan(body)
        l[name] = info
        try saveLock(l)
        return skill(name)!
    }

    /// Поставить скачанную папку. Тот же источник и коммит, или то же содержимое — ничего не делаем.
    public enum InstallResult: Equatable { case installed(String), alreadyInstalled(String), updated(String) }

    public func install(from staged: URL, source: String, commit: String?, origin: SkillInfo.Origin) throws -> InstallResult {
        guard let text = try? String(contentsOf: staged.appendingPathComponent("SKILL.md"), encoding: .utf8),
              let parsed = SkillFormat.parse(text), let name = parsed.fields["name"] else {
            throw SkillError.invalid(["В папке нет правильного SKILL.md"])
        }
        let problems = SkillFormat.problems(name: name, description: parsed.fields["description"] ?? "", body: parsed.body)
        guard problems.isEmpty else { throw SkillError.invalid(problems) }
        let hash = SkillFormat.sha256(of: staged)
        var l = lock()
        if let have = l[name], (have.source == source && commit != nil && have.commit == commit) || have.sha256 == hash {
            return .alreadyInstalled(name)
        }
        let dest = root.appendingPathComponent(name, isDirectory: true)
        let existed = FileManager.default.fileExists(atPath: dest.path)
        if existed { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: staged, to: dest)
        // проверяем всё текстовое: SKILL.md и скрипты
        var warnings: [String] = []
        for f in SkillFormat.files(in: dest) {
            if let t = try? String(contentsOf: dest.appendingPathComponent(f), encoding: .utf8) { warnings += SkillFormat.scan(t) }
        }
        l[name] = SkillInfo(origin: origin, source: source, commit: commit, sha256: hash,
                            enabled: warnings.isEmpty, installedAt: Date(), warnings: Array(Set(warnings)).sorted())
        try saveLock(l)
        return existed ? .updated(name) : .installed(name)
    }

    public func setEnabled(_ name: String, _ on: Bool) throws {
        var l = lock()
        guard var info = l[name] ?? skill(name)?.info else { return }
        info.enabled = on
        l[name] = info
        try saveLock(l)
    }

    public func remove(_ name: String) throws {
        let dir = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        var l = lock()
        l[name] = nil
        try saveLock(l)
    }

    /// Файл навыка — только внутри его папки
    public func read(_ name: String, path: String) -> String? {
        guard let s = skill(name) else { return nil }
        let url = s.folder.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(s.folder.standardizedFileURL.path + "/") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Блок для системного промпта: какие навыки есть и как их брать
    public static func promptBlock(_ skills: [Skill]) -> String? {
        guard !skills.isEmpty else { return nil }
        let list = skills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        return """
        Навыки — проверенные инструкции для отдельных задач. Если задача подходит под описание навыка, сначала загрузи его \
        инструментом load_skill и действуй по нему; файлы навыка — read_skill_file. Не пересказывай навык, просто следуй ему.
        \(list)
        """
    }
}

public enum SkillError: LocalizedError, Equatable {
    case invalid([String])
    case download(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let p): "Навык не подходит: " + p.joined(separator: "; ")
        case .download(let s): s
        }
    }
}
