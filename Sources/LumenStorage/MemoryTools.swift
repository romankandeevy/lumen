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
    /// Папки Lumen: где PROJECT.md у проекта без своей папки. Нет — add_to_project недоступен
    public var paths: AppPaths?

    public init(store: Store, conversationID: String, conversationTitle: String, skills: SkillLibrary? = nil, allowedSkills: Set<String>? = nil) {
        self.store = store
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.skills = skills
        self.allowedSkills = allowedSkills
    }

    /// Доступные навыки этого разговора
    public var availableSkills: [Skill] { skills?.enabled(only: allowedSkills) ?? [] }

    /// Проект этого разговора (add_to_project есть только в проекте)
    public var project: Project? {
        guard paths != nil, let c = try? store.conversations().first(where: { $0.id == conversationID }), let pid = c.projectID else { return nil }
        return try? store.projects().first { $0.id == pid }
    }

    /// Инструменты проекта: добавить в контекст проекта (PROJECT.md) текст, ссылки, файлы, картинки
    nonisolated(unsafe) public static let projectDefinitions: [(name: String, description: String, schema: [String: Any])] = [
        ("add_to_project",
         "Добавить в контекст проекта (PROJECT.md) то, что человек просит сохранить для проекта: текст, ссылки, файлы, картинки. "
            + "Это увидят все чаты проекта. Бери, когда пишут «добавь в проект», «запомни для проекта», «вот материалы к проекту».",
         ["type": "object", "additionalProperties": false, "required": ["text", "section", "files", "links"],
          "properties": [
            "text": ["type": "string", "description": "Что добавить, в Markdown, коротко и по делу. Пусто — если только файлы или ссылки"],
            "section": ["type": "string", "enum": ProjectContext.sections.filter { $0 != ProjectContext.chats },
                        "description": "Раздел: «Заметки» — по умолчанию; другой — только если это явно про него"],
            "files": ["type": "array", "items": ["type": "string"],
                      "description": "Файлы и картинки: путь на Маке или имя вложения из этого разговора. Lumen скопирует их к PROJECT.md. Нет — пустой список"],
            "links": ["type": "array", "items": ["type": "string"], "description": "Ссылки. Нет — пустой список"],
          ]]),
    ]

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
        case "add_to_project":
            return addToProject(input)
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

    /// Дописать в PROJECT.md проекта: текст — в раздел, файлы — копией в `context/` рядом, ссылки — списком
    func addToProject(_ input: [String: Any]) -> String {
        guard let p = project, let paths else { return "Этот разговор не в проекте — добавлять некуда. Предложи человеку перенести его в проект." }
        let url = p.contextURL(fallback: paths.projects)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var doc = (try? String(contentsOf: url, encoding: .utf8)) ?? ProjectContext.template(name: p.name, folder: p.ownFolder?.path)
        var section = input["section"] as? String ?? ProjectContext.notes
        if !ProjectContext.sections.contains(section) || section == ProjectContext.chats { section = ProjectContext.notes }
        var parts: [String] = []
        let text = (input["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append(text) }
        var missing: [String] = []
        for ref in input["files"] as? [String] ?? [] {
            guard let src = resolveFile(ref) else { missing.append(ref); continue }
            let into = dir.appendingPathComponent(ProjectContext.filesFolder, isDirectory: true)
            try? fm.createDirectory(at: into, withIntermediateDirectories: true)
            let dest = Self.freeURL(into.appendingPathComponent(src.lastPathComponent))
            do { try fm.copyItem(at: src, to: dest) } catch { missing.append(ref); continue }
            let rel = ProjectContext.filesFolder + "/" + dest.lastPathComponent
            let link = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel
            let image = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].contains(dest.pathExtension.lowercased())
            parts.append((image ? "!" : "") + "[\(dest.lastPathComponent)](\(link))")
        }
        let links = (input["links"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        parts += links.map { "- \($0)" }
        guard !parts.isEmpty else {
            return missing.isEmpty ? "Нечего добавлять: пусто." : "Не нашёл файлы: " + missing.joined(separator: ", ") + "."
        }
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        doc = ProjectContext.appending("*\(f.string(from: Date())), из чата «\(conversationTitle)»:*\n" + parts.joined(separator: "\n"), to: section, in: doc)
        do { try doc.write(to: url, atomically: true, encoding: .utf8) } catch {
            return "Не смог записать \(url.path): \(error.localizedDescription)"
        }
        var out = "Добавил в контекст проекта «\(p.name)», раздел «\(section)» (\(url.path))."
        if !missing.isEmpty { out += " Не нашёл: " + missing.joined(separator: ", ") + "." }
        return out
    }

    /// Путь на Маке или имя вложения из этого разговора
    func resolveFile(_ ref: String) -> URL? {
        let r = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return nil }
        let path = (r as NSString).expandingTildeInPath
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        for m in ((try? store.messages(in: conversationID)) ?? []).reversed() {
            for a in m.attachments where (a.name == r || a.path.hasSuffix("/" + r)) && FileManager.default.fileExists(atPath: a.path) {
                return URL(fileURLWithPath: a.path)
            }
        }
        return nil
    }

    /// Свободное имя: «файл.png» занят — «файл 2.png», «файл 3.png»…
    static func freeURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension, dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let next = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            n += 1
        }
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
