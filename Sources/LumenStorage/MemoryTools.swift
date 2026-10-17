import Foundation
import LumenCore

/// Инструменты памяти для модели: remember и recall (§5.3, §5.6).
/// Одна логика на два движка: `lumen-mcp` (claude) и клиентские инструменты API.
public struct MemoryTools: Sendable {
    public let store: Store
    public let conversationID: String
    public let conversationTitle: String

    /// Навыки: библиотека и какие из неё доступны (nil — все включённые)
    public var skills: SkillLibrary?
    public var allowedSkills: Set<String>?

    public init(store: Store, conversationID: String, conversationTitle: String, skills: SkillLibrary? = nil, allowedSkills: Set<String>? = nil) {
        self.store = store
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.skills = skills
        self.allowedSkills = allowedSkills
    }

    /// Доступные навыки этого разговора
    public var availableSkills: [Skill] { skills?.enabled(only: allowedSkills) ?? [] }

    nonisolated(unsafe) public static let skillDefinitions: [(name: String, description: String, schema: [String: Any])] = [
        ("load_skill",
         "Загрузить инструкции навыка по имени из списка навыков. Используй, когда задача подходит под описание навыка.",
         ["type": "object", "additionalProperties": false, "required": ["name"],
          "properties": ["name": ["type": "string", "description": "Имя навыка"]]]),
        ("read_skill_file",
         "Прочитать файл навыка (references/…, scripts/…), на который ссылаются его инструкции.",
         ["type": "object", "additionalProperties": false, "required": ["name", "path"],
          "properties": ["name": ["type": "string", "description": "Имя навыка"],
                         "path": ["type": "string", "description": "Путь внутри папки навыка"]]]),
    ]

    /// Описания в формате JSON Schema — общие для MCP (`inputSchema`) и API (`input_schema`)
    nonisolated(unsafe) public static let definitions: [(name: String, description: String, schema: [String: Any])] = [
        ("remember",
         "Сохранить в долгую память Lumen один факт о человеке, его проектах, решениях, людях вокруг или о том, как ему удобно. Одна короткая самодостаточная фраза в третьем лице, например «Встаёт в 9 утра».",
         ["type": "object", "additionalProperties": false, "required": ["text", "kind"],
          "properties": [
            "text": ["type": "string", "description": "Факт одной фразой"],
            "kind": ["type": "string", "enum": MemoryKind.allCases.map(\.rawValue),
                     "description": "you — о самом человеке, project — проекты, decision — принятые решения, pref — как ему удобно, people — люди вокруг"],
          ]]),
        ("recall",
         "Найти в памяти Lumen факты по словам: что человек рассказывал раньше, что решили, как зовут людей, детали проектов. Ищет и по прошлым разговорам (в том числе перенесённым из Claude Code).",
         ["type": "object", "additionalProperties": false, "required": ["query"],
          "properties": ["query": ["type": "string", "description": "Слова для поиска"]]]),
    ]

    public static let names: Set<String> = ["remember", "recall"]

    /// Выполнить инструмент. Ответ — текст для модели.
    public func call(_ name: String, _ input: [String: Any]) throws -> String {
        switch name {
        case "remember":
            let text = (input["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "Пустой факт — нечего запоминать." }
            let kind = MemoryKind(rawValue: input["kind"] as? String ?? "") ?? .you
            // такой же факт уже есть — не дублируем (§5.4), но отмечаем, что он прозвучал
            if let same = try store.memories().first(where: { Self.normalized($0.text) == Self.normalized(text) }), let id = same.id {
                try store.logMemoryUse(id, conversationID: conversationID, action: "recall")
                return "Это уже есть в памяти: «\(same.text)»."
            }
            let f = try store.save(MemoryFact(kind: kind, text: text, source: conversationTitle, conversationID: conversationID))
            if let id = f.id { try store.logMemoryUse(id, conversationID: conversationID, action: "remember") }
            return "Запомнил: «\(text)»."
        case "recall":
            let query = input["query"] as? String ?? ""
            let found = try store.searchMemories(query, limit: 8, anyWord: true)
            for f in found { if let id = f.id { try store.logMemoryUse(id, conversationID: conversationID, action: "recall") } }
            // и в прошлых разговорах — своих и импортированных из Claude Code; этот разговор не в счёт
            let hits = ((try? store.searchConversations(query, limit: 6, anyWord: true)) ?? [])
                .filter { $0.conversationID != conversationID }.prefix(4)
            if found.isEmpty && hits.isEmpty { return "В памяти ничего не нашлось по «\(query)»." }
            var out = found.map { "- \($0.text) (\($0.kind.name.lowercased()), \($0.source))" }
            if !hits.isEmpty {
                let f = DateFormatter()
                f.dateFormat = "dd.MM.yyyy"
                out.append("Из прошлых разговоров:")
                out += hits.map { "- «\($0.title)», \(f.string(from: $0.date)): \($0.snippet)" }
            }
            return out.joined(separator: "\n")
        case "load_skill":
            let n = input["name"] as? String ?? ""
            guard let s = availableSkills.first(where: { $0.name == n }) else { return "Нет такого навыка: \(n)." }
            try? store.logSkillUse(n, conversationID: conversationID)
            let files = s.files.isEmpty ? "" : "\n\nФайлы навыка (read_skill_file): " + s.files.joined(separator: ", ")
            return s.body + files
        case "read_skill_file":
            let n = input["name"] as? String ?? ""
            guard availableSkills.contains(where: { $0.name == n }), let text = skills?.read(n, path: input["path"] as? String ?? "") else {
                return "Нет такого файла у навыка."
            }
            return String(text.prefix(60_000))
        default:
            return "Нет такого инструмента: \(name)"
        }
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
