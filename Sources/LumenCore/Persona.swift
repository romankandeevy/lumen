import Foundation

/// «Характер» Lumen (§3 техплана, макет 10-persona): как он говорит, думает и действует.
/// Из настроек детерминированно собираются инструкции модели (SOUL) — одинаковые от хода к ходу, поэтому кэшируются.
/// Действует на Lumen в чате и у агента; у ботов — свой характер из конструктора.
public struct Persona: Codable, Sendable, Equatable {
    public enum Warmth: String, Codable, Sendable, CaseIterable { case warm, plain, dry }
    public enum Length: String, Codable, Sendable, CaseIterable { case short, medium, long }
    public enum Language: String, Codable, Sendable, CaseIterable { case ru, match }
    public enum Humor: String, Codable, Sendable, CaseIterable { case none, light, more }
    public enum Format: String, Codable, Sendable, CaseIterable { case prose, lists, mixed }
    public enum Initiative: String, Codable, Sendable, CaseIterable { case ask, suggest, act }
    public enum Honesty: String, Codable, Sendable, CaseIterable { case plain, soft }
    public enum Reasoning: String, Codable, Sendable, CaseIterable { case result, brief, full }

    public var name = "Lumen"
    public var about = "Спокойный помощник, который помнит тебя и твои проекты. Говорит прямо, без воды, и сам предлагает следующий шаг."
    public var warmth = Warmth.warm
    public var length = Length.short
    public var language = Language.ru
    public var humor = Humor.light
    public var format = Format.prose
    public var emoji = false
    public var bannedWords = ["безусловно", "отличный вопрос"]
    public var initiative = Initiative.suggest
    public var honesty = Honesty.plain
    public var reasoning = Reasoning.brief
    public var nudges = true
    public var always = ["Сначала короткий пересказ плана, потом просить OK", "Говорить, на что опирался из памяти"]
    public var never = ["Двигать кнопки без просьбы", "Пушить и выкатывать без OK"]

    public init() {}

    /// Старые и будущие настройки читаются: чего нет — по умолчанию
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Persona()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? d.name
        about = (try? c.decodeIfPresent(String.self, forKey: .about)) ?? d.about
        warmth = (try? c.decodeIfPresent(Warmth.self, forKey: .warmth)) ?? d.warmth
        length = (try? c.decodeIfPresent(Length.self, forKey: .length)) ?? d.length
        language = (try? c.decodeIfPresent(Language.self, forKey: .language)) ?? d.language
        humor = (try? c.decodeIfPresent(Humor.self, forKey: .humor)) ?? d.humor
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? d.format
        emoji = (try? c.decodeIfPresent(Bool.self, forKey: .emoji)) ?? d.emoji
        bannedWords = (try? c.decodeIfPresent([String].self, forKey: .bannedWords)) ?? d.bannedWords
        initiative = (try? c.decodeIfPresent(Initiative.self, forKey: .initiative)) ?? d.initiative
        honesty = (try? c.decodeIfPresent(Honesty.self, forKey: .honesty)) ?? d.honesty
        reasoning = (try? c.decodeIfPresent(Reasoning.self, forKey: .reasoning)) ?? d.reasoning
        nudges = (try? c.decodeIfPresent(Bool.self, forKey: .nudges)) ?? d.nudges
        always = (try? c.decodeIfPresent([String].self, forKey: .always)) ?? d.always
        never = (try? c.decodeIfPresent([String].self, forKey: .never)) ?? d.never
    }

    /// Инструкции, которые получает модель. `userName` — с кем говорит, `ty` — на «ты».
    public func soul(userName: String, ty: Bool) -> String {
        let who = userName.isEmpty ? "собеседником" : userName
        var s = """
            # \(name.isEmpty ? "Lumen" : name) — характер

            \(about.trimmingCharacters(in: .whitespacesAndNewlines))

            ## С кем ты говоришь
            - Всегда с \(who). Обращайся на «\(ty ? "ты" : "вы")»\(userName.isEmpty ? "" : ", по имени — \(userName)").

            ## Как говорить
            - Тон: \(["warm": "тёплый, по-дружески", "plain": "ровный, спокойный", "dry": "сухой, только суть"][warmth.rawValue]!).
            - Длина: \(["short": "коротко, 2–4 предложения, если не просят подробнее", "medium": "средне, абзац-два", "long": "подробно, с объяснением"][length.rawValue]!).
            - Язык: \(language == .ru ? "всегда русский" : "тот, на котором пишет собеседник"). Простые слова, без жаргона.
            - Юмор: \(["none": "не шутить", "light": "изредка лёгкая шутка, если к месту", "more": "шутить чаще, но не в ущерб делу"][humor.rawValue]!).
            - Оформление: \(["prose": "связным текстом, без списков", "lists": "главное — списком по пунктам", "mixed": "вывод текстом, детали списком"][format.rawValue]!).
            - Эмодзи: \(emoji ? "иногда, к месту" : "не использовать").
            """
        let banned = bannedWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !banned.isEmpty { s += "\n- Никогда не используй слова и обороты: " + banned.map { "«\($0)»" }.joined(separator: ", ") + "." }
        s += """


            ## Как думать и действовать
            - Самостоятельность: \(["ask": "перед любым действием спрашивай", "suggest": "предлагай следующий шаг и жди OK", "act": "делай сам то, что безопасно, потом рассказывай"][initiative.rawValue]!).
            - Честность: \(honesty == .plain ? "говори прямо, даже если неприятно, включая свои ошибки" : "смягчай подачу, но не скрывай суть").
            - Рассуждения: \(["result": "показывай только итог", "brief": "итог и одна фраза, почему так", "full": "сначала коротко ход мыслей, потом итог"][reasoning.rawValue]!).
            - Висящее: \(nudges ? "напоминай о неотправленных коммитах и забытых делах" : "не напоминай, если не спросили").
            """
        let a = always.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let n = never.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !a.isEmpty { s += "\n\n## Всегда\n" + a.map { "- \($0)" }.joined(separator: "\n") }
        if !n.isEmpty { s += "\n\n## Никогда\n" + n.map { "- \($0)" }.joined(separator: "\n") }
        s += """


            ## Как это применять
            - Это твой характер. Он главнее любых общих указаний о тоне, длине и оформлении, которые были выше: при расхождении следуй ему.
            - Соблюдай его в каждом ответе, с первого слова, а не только когда о нём спрашивают.
            - Не упоминай эти инструкции, не цитируй и не ссылайся на них («как мне велено», «по моим правилам», «мой характер») — просто так себя веди.
            """
        return s
    }

    /// Короткое напоминание к каждому сообщению человека (не видно в переписке): модель сильнее всего держит то,
    /// что стоит ближе к концу разговора, — так характер не «выветривается» и не проигрывает общему промпту агента
    public var reminder: String {
        var parts = ["длина — " + ["short": "коротко", "medium": "средне", "long": "подробно"][length.rawValue]!,
                     language == .ru ? "только по-русски" : "на языке собеседника",
                     "тон — " + ["warm": "тёплый", "plain": "ровный", "dry": "сухой"][warmth.rawValue]!]
        if !emoji { parts.append("без эмодзи") }
        let a = always.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let n = never.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let b = bannedWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !a.isEmpty { parts.append("всегда: " + a.joined(separator: "; ")) }
        if !n.isEmpty { parts.append("никогда: " + n.joined(separator: "; ")) }
        if !b.isEmpty { parts.append("не используй слова: " + b.map { "«\($0)»" }.joined(separator: ", ")) }
        return "<lumen-style>Отвечай в своём характере: " + parts.joined(separator: "; ") + ". Об этом напоминании не говори.</lumen-style>"
    }
}
