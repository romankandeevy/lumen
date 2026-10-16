import Foundation
import LumenCore
import LumenProviders
import LumenStorage

// Обучение на опыте (техплан §4.4, §8.2): после задачи бота или агента Haiku коротко разбирает её —
// выводы «чему научился» уходят в правила бота, повторяемый приём предлагается навыком.
// Модель не переобучается: учится через память, выводы и навыки, которые ты подтверждаешь.

extension AppModel {
    /// Один короткий запрос к модели без инструментов и настроек пользователя; ответ — текст
    func quickAsk(_ prompt: String, system: String, model: ChatModel = .haiku, effort: Effort = .low) async -> String? {
        guard let cli else { return nil }
        let config = ClaudeSession.Config(model: model.rawValue, effort: effort.rawValue, systemPrompt: system, tools: [], userSettings: false)
        guard let session = try? ClaudeSession(cli: cli, config: config) else { return nil }
        defer { session.close() }
        guard let r = try? await session.ask(prompt), r.ok else { return nil }
        if r.costUSD > 0 {
            try? store.logSpend(conversationID: nil, backend: .subscription, model: model.rawValue, input: r.inputTokens, output: r.outputTokens,
                                cacheRead: r.cacheReadTokens, cacheWrite: r.cacheWriteTokens, usd: r.costUSD)
        }
        return r.text
    }

    /// Название разговора после первого ответа — придумывает та же сторона, где идёт разговор:
    /// Claude (Haiku) или ChatGPT (быстрая модель). Переименованный руками разговор не трогаем.
    func nameConversation(_ c: Conversation, question: String, answer: String) async {
        guard c.kind != .bot, c.title == ChatController.title(from: question) else { return }
        let prompt = """
        Придумай короткое название для разговора по его началу: 2–5 слов, по-русски (если разговор не на русском — на его языке),         без кавычек, точки и слова «разговор». Ответь только названием.
        Человек: \(question.prefix(1500))
        Ответ: \(answer.prefix(1500))
        """
        var text: String?
        if c.model.isGPT, codex == .signedIn, let codexCLI {
            let dir = paths.run.appendingPathComponent("titles", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            text = await codexCLI.ask(prompt, model: ChatModel.gptLuna.rawValue, folder: dir)
        } else {
            text = await quickAsk(prompt, system: "Ты придумываешь короткие точные названия разговоров. Отвечай только названием.")
        }
        guard var title = text?.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " «»\"'.:*#")) , !title.isEmpty else { return }
        if title.count > 48 { title = String(title.prefix(46)).trimmingCharacters(in: .whitespaces) + "…" }
        // за время запроса могли переименовать руками
        guard let now = conversations.first(where: { $0.id == c.id }), now.title == c.title else { return }
        renameChat(now, title)
    }

    /// Старые разговоры, названные первой фразой, — переименовать один раз (до 20, по одному)
    func nameOldConversations() async {
        guard (try? store.value("namedOld", as: Bool.self)) != true, cli != nil else { return }
        try? store.set("namedOld", true)
        for c in conversations.prefix(20) where c.kind != .bot {
            guard let all = try? store.messages(in: c.id), let q = all.first(where: { $0.role == .user })?.text,
                  let a = all.first(where: { $0.role == .assistant && $0.error == nil && !$0.text.isEmpty })?.text,
                  c.title == ChatController.title(from: q) else { continue }
            await nameConversation(c, question: q, answer: a)
        }
    }

    /// Разобрать законченную задачу: выводы для бота и, может быть, навык
    func learn(task: String, answer: String, steps: [AgentStep], bot: Bot?, messageID: Int64?, conversationID: String) async {
        let worthSkill = steps.count >= 4
        guard bot != nil || worthSkill, !answer.isEmpty else { return }
        let existing = skillLibrary.all().map(\.name)
        let system = """
        Ты разбираешь только что законченную задачу помощника, чтобы он работал лучше в следующий раз. Отвечай строго JSON без markdown:
        {"lessons": ["…"], "skill": null}
        lessons — 0–2 коротких правила на будущее (одно предложение каждое): что выяснилось о проекте, людях или о том, как правильно делать такую работу. \
        Только устойчивое и полезное в следующий раз, не пересказ задачи. Нечего — пустой список.
        skill — только если в задаче был повторяемый многошаговый приём, который пригодится снова почти дословно. Тогда объект:
        {"name": "латиница-через-дефис", "description": "что делает и когда применять: перечисли фразы и ситуации, в которых его брать", \
        "body": "инструкции в markdown: шаги в повелительном наклонении, зачем каждый, формат результата, пример", "tests": ["просьба 1", "просьба 2"]}
        Не предлагай навык для разовой работы. Уже есть навыки: \(existing.isEmpty ? "нет" : existing.joined(separator: ", ")).
        """
        let stepsText = steps.prefix(30).map { "- \($0.text)" }.joined(separator: "\n")
        let prompt = "Задача:\n\(task.prefix(3000))\n\nШаги:\n\(stepsText.isEmpty ? "—" : stepsText)\n\nИтог:\n\(answer.prefix(4000))"
        guard let text = await quickAsk(prompt, system: system), let json = Self.jsonObject(in: text) else { return }

        if var b = bot, let lessons = json["lessons"] as? [String] {
            let fresh = lessons.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { l in !l.isEmpty && !b.learned.contains { $0.caseInsensitiveCompare(l) == .orderedSame } }
            if !fresh.isEmpty {
                b.learned = Array((b.learned + fresh).suffix(12))
                try? store.save(b)
                reloadBots()
                chat.restart(conversations.first { $0.kind == .bot && $0.botID == b.id }?.id ?? "")
            }
        }
        if worthSkill, let s = json["skill"] as? [String: Any], let messageID {
            let draft = SkillDraft(name: (s["name"] as? String ?? "").lowercased(), description: s["description"] as? String ?? "",
                                   body: s["body"] as? String ?? "", tests: s["tests"] as? [String] ?? [])
            guard draft.problems.isEmpty, !existing.contains(draft.name) else { return }
            chat.attachSkillDraft(draft, to: messageID, conversationID: conversationID)
        }
    }

    /// Первый JSON-объект в тексте ответа модели
    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any]
    }
}
