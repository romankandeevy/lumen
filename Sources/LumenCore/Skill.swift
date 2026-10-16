import CryptoKit
import Foundation

/// Навык (техплан §8, формат agentskills.io): папка `имя/` с `SKILL.md` (фронтматтер name + description и инструкции)
/// и необязательными `scripts/`, `references/`, `assets/`. Модель видит только имя и описание всех включённых навыков,
/// тело подгружает сама, когда навык к месту (`load_skill` в lumen-mcp).
public struct Skill: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var description: String
    /// Тело SKILL.md без фронтматтера
    public var body: String
    /// Остальные файлы папки (относительные пути)
    public var files: [String]
    public var folder: URL
    public var info: SkillInfo

    public init(name: String, description: String, body: String, files: [String] = [], folder: URL, info: SkillInfo) {
        self.name = name
        self.description = description
        self.body = body
        self.files = files
        self.folder = folder
        self.info = info
    }
}

/// Черновик навыка: из «Создать навык» или предложенный после задачи («сам научился»)
public struct SkillDraft: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var description: String
    public var body: String
    /// Пара просьб, на которых навык стоит попробовать
    public var tests: [String]

    public init(name: String, description: String, body: String, tests: [String] = []) {
        self.name = name
        self.description = description
        self.body = body
        self.tests = tests
    }

    public var problems: [String] { SkillFormat.problems(name: name, description: description, body: body) }
}

/// Откуда навык и в каком он состоянии (`.hub/lock.json`)
public struct SkillInfo: Codable, Sendable, Equatable, Hashable {
    public enum Origin: String, Codable, Sendable { case created, learned, github, catalog }
    public var origin: Origin
    /// `github:owner/repo/path@ref`
    public var source: String?
    /// Коммит источника при установке — «уже скачано, не качать»
    public var commit: String?
    /// Хэш всего содержимого папки
    public var sha256: String
    public var enabled: Bool
    public var installedAt: Date
    /// Что нашла проверка при установке (пусто — чисто)
    public var warnings: [String]

    public init(origin: Origin, source: String? = nil, commit: String? = nil, sha256: String = "", enabled: Bool = true,
                installedAt: Date = Date(), warnings: [String] = []) {
        self.origin = origin
        self.source = source
        self.commit = commit
        self.sha256 = sha256
        self.enabled = enabled
        self.installedAt = installedAt
        self.warnings = warnings
    }
}

public enum SkillFormat {
    /// Имя по спецификации: 1–64 знака, a-z 0-9 и дефис, без «--» и дефиса по краям
    public static func isValidName(_ s: String) -> Bool {
        s.range(of: #"^[a-z0-9](?:[a-z0-9]|-(?!-)){0,62}[a-z0-9]$|^[a-z0-9]$"#, options: .regularExpression) != nil
    }

    /// Разобрать SKILL.md: фронтматтер `---` … `---` и тело
    public static func parse(_ text: String) -> (fields: [String: String], body: String)? {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard t.hasPrefix("---\n") else { return nil }
        let rest = t.dropFirst(4)
        guard let end = rest.range(of: "\n---") else { return nil }
        let head = rest[..<end.lowerBound]
        var body = String(rest[end.upperBound...])
        while body.hasPrefix("\n") { body.removeFirst() }
        var fields: [String: String] = [:]
        var lastKey: String?
        for line in head.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(line)
            // продолжение многострочного значения (отступ)
            if l.hasPrefix(" ") || l.hasPrefix("\t"), let k = lastKey {
                fields[k, default: ""] += (fields[k]?.isEmpty == false ? " " : "") + l.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = l.firstIndex(of: ":") else { continue }
            let key = l[..<colon].trimmingCharacters(in: .whitespaces)
            var value = l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value == "|" || value == ">" || value == ">-" || value == "|-" { value = "" }
            if value.count >= 2, let f = value.first, f == value.last, f == "\"" || f == "'" { value = String(value.dropFirst().dropLast()) }
            fields[key] = value
            lastKey = key
        }
        return (fields, body)
    }

    /// Что не так с навыком по спецификации; пусто — всё хорошо
    public static func problems(name: String, description: String, body: String, folderName: String? = nil) -> [String] {
        var out: [String] = []
        if !isValidName(name) { out.append("Имя «\(name)»: только латиница в нижнем регистре, цифры и дефис, до 64 знаков") }
        if let folderName, folderName != name { out.append("Имя не совпадает с папкой «\(folderName)»") }
        if description.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Нет описания: когда применять навык") }
        if description.count > 1024 { out.append("Описание длиннее 1024 знаков") }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("Пустые инструкции") }
        if body.split(separator: "\n", omittingEmptySubsequences: false).count > 500 { out.append("Инструкции длиннее 500 строк — вынеси подробности в references/") }
        return out
    }

    /// SKILL.md из полей
    public static func render(name: String, description: String, body: String) -> String {
        let desc = description.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "\\\"")
        return "---\nname: \(name)\ndescription: \"\(desc)\"\n---\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Хэш папки: отсортированные пути и байты (без служебных файлов)
    public static func sha256(of folder: URL) -> String {
        var hasher = SHA256()
        for path in files(in: folder).sorted() {
            hasher.update(data: Data(path.utf8))
            if let d = try? Data(contentsOf: folder.appendingPathComponent(path)) { hasher.update(data: d) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Все файлы папки навыка (относительные пути)
    public static func files(in folder: URL) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        let base = folder.standardizedFileURL.path
        for case let url as URL in e where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let p = url.standardizedFileURL.path
            if p.hasPrefix(base + "/") { out.append(String(p.dropFirst(base.count + 1))) }
        }
        return out
    }

    /// Проверка на подозрительное (§8.3): сеть + секреты, «скачай и выполни», удаление всего, длинный base64, невидимые символы
    public static func scan(_ text: String) -> [String] {
        var out: [String] = []
        let checks: [(String, String)] = [
            (#"curl[^\n|]*\|\s*(ba|z)?sh"#, "скачивает и сразу выполняет скрипт (curl | sh)"),
            (#"wget[^\n|]*\|\s*(ba|z)?sh"#, "скачивает и сразу выполняет скрипт (wget | sh)"),
            (#"rm\s+-rf\s+(/|~|\$HOME)"#, "удаляет домашнюю папку или диск (rm -rf)"),
            (#"\.ssh/|id_rsa|id_ed25519"#, "читает SSH-ключи"),
            (#"\.aws/credentials|keychain|security\s+find-generic-password"#, "лезет в пароли и ключи"),
            (#"[A-Za-z0-9+/]{400,}={0,2}"#, "длинный закодированный блок (base64)"),
        ]
        for (pattern, why) in checks where text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            out.append(why)
        }
        if text.unicodeScalars.contains(where: { [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x202E].contains($0.value) }) {
            out.append("невидимые символы в тексте")
        }
        return out
    }
}
