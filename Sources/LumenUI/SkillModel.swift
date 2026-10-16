import Foundation
import LumenCore
import LumenProviders
import LumenStorage

// Навыки в приложении: список, каталог, установка, создание с Lumen; и самонастройка бота по одной фразе.

extension AppModel {
    func reloadSkills() {
        skills = skillLibrary.all()
        skillUses = (try? store.skillUseCounts()) ?? [:]
    }

    func setSkill(_ s: Skill, enabled: Bool) {
        try? skillLibrary.setEnabled(s.name, enabled)
        reloadSkills()
        chat.memoryChanged() // список навыков в правилах чата поменялся — процессы перезапустятся
    }

    func removeSkill(_ s: Skill) {
        try? skillLibrary.remove(s.name)
        for var b in bots where b.skills.contains(s.name) {
            b.skills.removeAll { $0 == s.name }
            try? store.save(b)
        }
        reloadBots()
        reloadSkills()
        chat.memoryChanged()
    }

    func saveSkill(_ d: SkillDraft, origin: SkillInfo.Origin) throws -> Skill {
        let s = try skillLibrary.save(name: d.name, description: d.description, body: d.body, origin: origin)
        reloadSkills()
        chat.memoryChanged()
        return s
    }

    /// Поставить по ссылке или из каталога; ответ — что получилось, простыми словами
    func installSkill(_ link: String, origin: SkillInfo.Origin = .github) async -> String {
        guard let loc = GitHubSkills.Location(link: link), !loc.path.isEmpty || origin == .github else {
            return "Не понял ссылку. Нужна ссылка на папку навыка на GitHub или на его SKILL.md."
        }
        do {
            let r = try await GitHubSkills(session: urlSession).install(loc, into: skillLibrary, origin: origin)
            reloadSkills()
            chat.memoryChanged()
            switch r {
            case .alreadyInstalled(let n): return "«\(n)» уже стоит — та же версия, качать не стал."
            case .updated(let n): return "«\(n)» обновлён."
            case .installed(let n):
                if let s = skillLibrary.skill(n), !s.info.warnings.isEmpty {
                    return "«\(n)» поставлен, но выключен: проверка нашла подозрительное — \(s.info.warnings.joined(separator: ", ")). Посмотри и включи сам, если доверяешь."
                }
                return "«\(n)» поставлен и включён."
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// Перевод на русский для английских описаний (Haiku). Уже переведённое — из файла, без запроса.
    func translateToRussian(_ text: String) async -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.isASCII }.count
        guard letters.count > 0, Double(latin) / Double(letters.count) > 0.6 else { return text } // уже не английский
        let file = paths.skills.appendingPathComponent(".hub/translations.json")
        var cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
        if let hit = cache[text] { return hit }
        guard let ru = await quickAsk("Переведи на русский, коротко и естественно, без пояснений и кавычек:\n\n\(text)",
                                      system: "Ты переводчик. Отвечай только переводом.") else { return nil }
        let clean = ru.trimmingCharacters(in: .whitespacesAndNewlines)
        cache[text] = clean
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
        return clean
    }

    /// Поставить из каталога skills.sh
    func installFromDirectory(_ e: SkillsDirectory.Entry) async -> String {
        do {
            let r = try await SkillsDirectory(session: urlSession).install(e, into: skillLibrary)
            reloadSkills()
            chat.memoryChanged()
            switch r {
            case .alreadyInstalled(let n): return "«\(n)» уже стоит — та же версия, качать не стал."
            case .updated(let n): return "«\(n)» обновлён."
            case .installed(let n):
                if let s = skillLibrary.skill(n), !s.info.warnings.isEmpty {
                    return "«\(n)» поставлен, но выключен: проверка нашла подозрительное — \(s.info.warnings.joined(separator: ", ")). Посмотри и включи сам, если доверяешь."
                }
                return "«\(n)» поставлен и включён."
            }
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: создание с Lumen

    /// Правила хорошего навыка — общие с lumen-mcp (SkillFormat.authoringRules)
    static var skillRules: String { SkillFormat.authoringRules }

    /// Черновик навыка: модель пишет, потом перечитывает свежим взглядом и улучшает, потом проверка по стандарту
    func draftSkill(_ request: String, context: String? = nil) async -> Result<SkillDraft, SkillDraftError> {
        let system = """
        Ты пишешь навыки (SKILL.md, формат agentskills.io) для помощника Lumen. \(Self.skillRules)
        Отвечай строго JSON без markdown вокруг: {"name": "…", "description": "…", "body": "…", "tests": ["…", "…"]}
        """
        var ask = "Нужен навык: \(request)"
        if let context, !context.isEmpty { ask += "\n\nВот разговор, из которого его стоит собрать (шаги, поправки человека, формат результата):\n\(context.prefix(12000))" }
        let taken = skillLibrary.all().map(\.name)
        if !taken.isEmpty { ask += "\n\nЭти имена уже заняты: \(taken.joined(separator: ", "))." }
        guard let first = await quickAsk(ask, system: system, model: .sonnet, effort: .medium), var draft = Self.draft(from: first) else {
            return .failure(.noAnswer)
        }
        // второй проход: свежим взглядом по тем же правилам
        let review = """
        Вот черновик навыка. Перечитай его свежим взглядом по правилам и верни улучшенную версию тем же JSON. \
        Особенно проверь: описание говорит, когда брать навык, с конкретными фразами; шаги понятны без догадок; \
        есть формат результата и пример; нет лишнего.
        \(Self.json(draft))
        """
        if let second = await quickAsk(review, system: system, model: .sonnet, effort: .medium), let better = Self.draft(from: second), better.problems.isEmpty {
            draft = better
        }
        if taken.contains(draft.name) { draft.name += "-2" }
        let problems = draft.problems
        return problems.isEmpty ? .success(draft) : .failure(.invalid(problems, draft))
    }

    enum SkillDraftError: Error {
        case noAnswer
        case invalid([String], SkillDraft)
    }

    static func draft(from text: String) -> SkillDraft? {
        guard let j = jsonObject(in: text), let name = j["name"] as? String else { return nil }
        return SkillDraft(name: name.lowercased().trimmingCharacters(in: .whitespaces), description: j["description"] as? String ?? "",
                          body: j["body"] as? String ?? "", tests: j["tests"] as? [String] ?? [])
    }

    static func json(_ d: SkillDraft) -> String {
        let obj: [String: Any] = ["name": d.name, "description": d.description, "body": d.body, "tests": d.tests]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])) ?? Data(), as: UTF8.self)
    }

    /// Текст разговора для «Сделать навык из этого разговора»
    func transcript(of c: Conversation) -> String {
        ((try? store.messages(in: c.id)) ?? []).map { m in
            let who = m.role == .user ? "Человек" : "Помощник"
            let steps = m.steps.isEmpty ? "" : "\n[шаги: " + m.steps.map(\.text).joined(separator: "; ") + "]"
            return "\(who): \(m.text)\(steps)"
        }.joined(separator: "\n\n")
    }

    // MARK: бот по одной фразе (§4.5)

    /// Черновик бота: модель предлагает роль, минимальные права, команды и подсказки. Права подтверждает человек в конструкторе.
    func draftBot(_ phrase: String) async -> Bot? {
        let icons = Bot.icons.joined(separator: ", ")
        let caps = BotCapability.allCases.map { "\($0.rawValue) — \($0.name)" }.joined(separator: "; ")
        let skillList = skillLibrary.enabled().map { "\($0.name): \($0.description.prefix(120))" }.joined(separator: "\n")
        let system = """
        Ты настраиваешь бота для Lumen по описанию человека. Отвечай строго JSON без markdown:
        {"name": "по-русски, 1–3 слова", "id": "латиница-через-дефис, 2–20 знаков", "icon": "одно из: \(icons)", "hue": 0–360,
         "role": "роль одной строкой", "instructions": "как работать: что делать, как отчитываться, чего не делать — 3–6 предложений",
         "capabilities": ["…"], "commands": ["…"], "starters": ["три готовые просьбы"], "skills": ["имена подходящих навыков из списка"]}
        Возможности: \(caps). Давай МИНИМУМ, нужный для роли: права раздаёт человек, лишнее — риск. \
        commands — только если есть run без write: команды сборки и тестов, которые нужны роли.
        Навыки на выбор:
        \(skillList.isEmpty ? "нет" : skillList)
        """
        // Haiku 5.5: быстро (пара секунд) и дёшево, для черновика хватает
        guard let text = await quickAsk("Нужен бот: \(phrase)", system: system, model: .haiku, effort: .low),
              let j = Self.jsonObject(in: text) else { return nil }
        var id = (j["id"] as? String ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        if !Bot.isValidID(id) { id = "bot-\(Int.random(in: 10...99))" }
        while bot(id) != nil { id += "-2" }
        let installed = Set(skillLibrary.enabled().map(\.name))
        return Bot(id: id, name: j["name"] as? String ?? "Бот", icon: Bot.icons.contains(j["icon"] as? String ?? "") ? j["icon"] as! String : "bot",
                   hue: (j["hue"] as? Double) ?? Double(j["hue"] as? Int ?? 200), role: j["role"] as? String ?? "",
                   instructions: j["instructions"] as? String ?? "",
                   capabilities: Set((j["capabilities"] as? [String] ?? []).compactMap(BotCapability.init(rawValue:))),
                   commands: j["commands"] as? [String] ?? [], starters: j["starters"] as? [String] ?? [],
                   skills: (j["skills"] as? [String] ?? []).filter { installed.contains($0) })
    }
}
