import Foundation
import LumenCore
import LumenStorage

/// Lumen достраивает себя (Рома, 16.10): смотрит, создаёт, находит на skills.sh и ставит навыки прямо из разговора.
/// Один код для всех движков: lumen-mcp (Claude Code, ChatGPT) и цикл инструментов API.
public enum SkillAdmin {
    public static let names: Set<String> = ["list_skills", "create_skill", "find_skills", "install_skill"]

    nonisolated(unsafe) public static let definitions: [(name: String, description: String, schema: [String: Any])] = [
        ("list_skills", "Список навыков Lumen: имя, когда брать, включён ли.", ["type": "object", "properties": [String: Any]()]),
        ("create_skill", "Создать навык Lumen (SKILL.md). Используй, когда просят научиться чему-то, сделать навык или когда приём явно повторяется. \(SkillFormat.authoringRules)",
         ["type": "object", "additionalProperties": false, "required": ["name", "description", "body"],
          "properties": ["name": ["type": "string", "description": "латиница-через-дефис"],
                         "description": ["type": "string", "description": "что делает и когда брать"],
                         "body": ["type": "string", "description": "инструкции в markdown"],
                         "replace": ["type": "boolean", "description": "заменить навык с таким именем"]]]),
        ("find_skills", "Найти готовые навыки в каталоге skills.sh (тот же, что у npx skills).",
         ["type": "object", "additionalProperties": false, "required": ["query"],
          "properties": ["query": ["type": "string", "description": "что ищем, лучше по-английски, от двух букв"]]]),
        ("install_skill", "Поставить навык из skills.sh по id из find_skills (owner/repo/skill). Подозрительный ставится выключенным.",
         ["type": "object", "additionalProperties": false, "required": ["id"],
          "properties": ["id": ["type": "string", "description": "owner/repo/skill"]]]),
    ]

    /// Вход инструмента (JSON) — передаётся между потоками как есть
    public struct Args: @unchecked Sendable {
        public let value: [String: Any]
        public init(_ value: [String: Any]) { self.value = value }
    }

    public static func call(_ name: String, _ input: Args, library lib: SkillLibrary, session: URLSession = .shared) async -> String {
        let args = input.value
        switch name {
        case "list_skills":
            let all = lib.all()
            if all.isEmpty { return "Навыков пока нет." }
            return all.map { "- \($0.name)\($0.info.enabled ? "" : " (выключен)"): \($0.description)" }.joined(separator: "\n")
        case "create_skill":
            let n = (args["name"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            if lib.skill(n) != nil && args["replace"] as? Bool != true { return "Навык «\(n)» уже есть. Выбери другое имя или передай replace: true." }
            do {
                let s = try lib.save(name: n, description: args["description"] as? String ?? "", body: args["body"] as? String ?? "", origin: .created)
                let warn = s.info.warnings.isEmpty ? "" : " Внимание: проверка нашла подозрительное — \(s.info.warnings.joined(separator: ", "))."
                return "Навык «\(n)» создан и включён, его видно в Lumen → Навыки.\(warn)"
            } catch {
                return error.localizedDescription
            }
        case "find_skills":
            let q = args["query"] as? String ?? ""
            let found = (try? await SkillsDirectory(session: session).search(q)) ?? []
            if found.isEmpty { return "На skills.sh ничего не нашлось по «\(q)»." }
            return found.prefix(12).map { "- \($0.source)/\($0.skillID) — \($0.installs) установок" }.joined(separator: "\n")
        case "install_skill":
            let parts = (args["id"] as? String ?? "").split(separator: "/").map(String.init)
            guard parts.count >= 3 else { return "Нужен id вида owner/repo/skill." }
            let entry = SkillsDirectory.Entry(source: parts.dropLast().joined(separator: "/"), skillID: parts.last!, name: parts.last!, installs: 0)
            do {
                switch try await SkillsDirectory(session: session).install(entry, into: lib) {
                case .alreadyInstalled(let n): return "«\(n)» уже стоит."
                case .updated(let n): return "«\(n)» обновлён."
                case .installed(let n):
                    let s = lib.skill(n)
                    if let w = s?.info.warnings, !w.isEmpty { return "«\(n)» поставлен, но выключен: проверка нашла подозрительное — \(w.joined(separator: ", ")). Включить может человек в Навыках." }
                    return "«\(n)» поставлен и включён: \(s?.description ?? "")"
                }
            } catch {
                return error.localizedDescription
            }
        default:
            return "Нет такого инструмента."
        }
    }
}
