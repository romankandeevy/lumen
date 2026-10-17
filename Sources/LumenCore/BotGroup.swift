import Foundation

// Группы ботов — как группы в Hermes Agent (NousResearch/hermes-agent, MIT, apps/desktop/src/plugins/hermes-bots:
// group-rounds.ts, group-round-prompt.ts): одна общая «комната» — ты и до 6 ботов. На твоё сообщение отвечают
// по кругу, строго по очереди, не больше 3 раундов и 10 ответов; каждый бот видит только новое с его прошлого хода
// и сам решает — сказать что-то по делу или «(pass)». Упомянул кого-то (@id) — отвечают только упомянутые.
// Раунд, где все промолчали, — комната затихла.

public struct BotGroup: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var hue: Double
    /// id ботов-участников по порядку
    public var members: [String]
    /// До какого сообщения комнаты каждый участник уже дочитал (id сообщения)
    public var seen: [String: Int64]
    public var createdAt: Date

    public init(id: String = UUID().uuidString.lowercased(), name: String, hue: Double = 200, members: [String],
                seen: [String: Int64] = [:], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.hue = hue
        self.members = members
        self.seen = seen
        self.createdAt = createdAt
    }

    public static let maxMembers = 6
    public static let maxRounds = 3
    public static let maxMessages = 10
    /// Сколько последних сообщений комнаты бот получает за ход и сколько знаков
    public static let deltaLimit = 60
    public static let deltaChars = 32_000
    public static let lineChars = 6_000
    public static let pass = "(pass)"
}

public enum GroupRoom {
    /// Упомянутые участники (@id) и было ли @все / @everyone
    public static func mentions(_ text: String, members: [Bot]) -> (ids: Set<String>, everyone: Bool) {
        var ids = Set<String>()
        var everyone = false
        let lower = text.lowercased()
        for token in lower.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "@" || $0 == "-" || $0 == "_") }) {
            guard token.hasPrefix("@") else { continue }
            let name = String(token.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            if ["все", "всем", "everyone", "all"].contains(name) { everyone = true; continue }
            if let b = members.first(where: { $0.id == name || $0.name.lowercased() == name }) { ids.insert(b.id) }
        }
        return (ids, everyone)
    }

    /// Кто отвечает в этом раунде: упомянутые с последнего сообщения человека, иначе все
    public static func responders(log: [ChatMessage], members: [Bot]) -> [Bot] {
        let since = log.lastIndex { $0.role == .user }.map { Array(log[$0...]) } ?? []
        var ids = Set<String>()
        var everyone = false
        for m in since {
            let r = mentions(m.text, members: members)
            ids.formUnion(r.ids)
            everyone = everyone || r.everyone
        }
        if everyone || ids.isEmpty { return members }
        return members.filter { ids.contains($0.id) }
    }

    /// К кому человек обратился прямо (@id или @все) — им промолчать нельзя
    public static func addressed(log: [ChatMessage], members: [Bot]) -> Set<String> {
        guard let last = log.last(where: { $0.role == .user }) else { return [] }
        let r = mentions(last.text, members: members)
        return r.everyone ? Set(members.map(\.id)) : r.ids
    }

    /// Каждый раунд первым говорит другой
    public static func rotate(_ members: [Bot], round: Int) -> [Bot] {
        guard members.count > 1 else { return members }
        let shift = round % members.count
        return Array(members[shift...] + members[..<shift])
    }

    /// Строка журнала глазами участника: «Роман (человек): …», «Дизайнер (@designer): …», «… (ты): …»
    public static func line(_ m: ChatMessage, viewer: Bot, userName: String, members: [Bot]) -> String {
        let files = m.attachments.isEmpty ? "" : " " + m.attachments.map { "[вложение: \($0.name)]" }.joined(separator: " ")
        var text = m.text
        if text.count > BotGroup.lineChars { text = String(text.prefix(BotGroup.lineChars)) + "…" }
        if m.role == .user { return "\(userName.isEmpty ? "Человек" : userName) (человек): \(text)\(files)" }
        let id = m.botID ?? "?"
        let name = members.first { $0.id == id }?.name ?? id
        return "\(name) (@\(id))\(id == viewer.id ? " (ты)" : ""): \(text)\(files)"
    }

    /// Новое в комнате с прошлого хода участника — последние, что влезают; срезанное — пометкой
    public static func delta(_ log: [ChatMessage], after seen: Int64?, viewer: Bot, userName: String, members: [Bot]) -> [String] {
        let fresh = log.filter { ($0.id ?? 0) > (seen ?? 0) && $0.note == nil && $0.error == nil }
        var lines: [String] = []
        var chars = 0
        for m in fresh.reversed() {
            let l = line(m, viewer: viewer, userName: userName, members: members)
            if !lines.isEmpty && (lines.count >= BotGroup.deltaLimit || chars + l.count > BotGroup.deltaChars) { break }
            lines.append(l)
            chars += l.count + 1
        }
        lines.reverse()
        let omitted = fresh.count - lines.count
        if omitted > 0 { lines.insert("… ещё \(omitted) ранних сообщений комнаты не поместились", at: 0) }
        return lines
    }

    /// Ход участника: кто он, кто ещё в комнате, что нового, правила комнаты
    public static func prompt(group: BotGroup, viewer: Bot, members: [Bot], delta: [String]) -> String {
        let peers = members.filter { $0.id != viewer.id }.map { "\($0.name) (@\($0.id))" }.joined(separator: ", ")
        return ([
            "[Группа «\(group.name)»] Ты — @\(viewer.id), один из участников группового чата: \(peers.isEmpty ? "пока никого" : peers) и человек.",
            "",
            "Новое в комнате с твоего прошлого хода (по порядку):",
        ] + delta.map { "  " + $0 } + [
            "",
            "Правила комнаты:",
            "- Отвечай ОДНИМ сообщением, только если есть что добавить по сути: продолжи мысль, возьми или передай работу, ответь на вопрос к тебе, сообщи результат. Болтовню — коротко (1–3 фразы); результат или ответ, который просил человек, — полностью, не урезай.",
            "- Если добавить нечего — ответь ровно «\(BotGroup.pass)». Молчать — нормально: так разговор успокаивается.",
            "- Зови коллегу как @id; человека — только за решением или результатом, который ему нужен. Не повторяй сказанное.",
            "- Твой ответ уходит в комнату как есть — без вступлений и пояснений о себе.",
        ]).joined(separator: "\n")
    }

    /// Обратились прямо, а он промолчал — переспросить один раз
    public static let addressedNudge = """

    Ты ответил «\(BotGroup.pass)», но человек обратился прямо к тебе (@ты или @все). Промолчать нельзя.
    Ответь одним сообщением: ответ, результат или прямо скажи, почему не можешь.
    """

    /// Молчит ли участник
    public static func isPass(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "«»\"'."))
        return t.isEmpty || t.lowercased() == "(pass)" || t.lowercased() == "pass"
    }
}
