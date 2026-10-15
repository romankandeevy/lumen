import Foundation

/// Вид факта — как фильтры на странице «Что Lumen знает» (`memoryKinds` в макете)
public enum MemoryKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case you, project, decision, pref, people

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .you: "О тебе"
        case .project: "Проекты"
        case .decision: "Решения"
        case .pref: "Как тебе удобно"
        case .people: "Люди"
        }
    }
}

/// Факт памяти (§5 техплана): текст, вид, откуда взялся, закреплён ли
public struct MemoryFact: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int64?
    public var kind: MemoryKind
    public var text: String
    /// Откуда: заголовок разговора, «Знакомство», «Добавлено вручную»
    public var source: String
    /// Разговор-источник — чтобы открыть его со страницы памяти
    public var conversationID: String?
    /// Постоянный ключ для фактов, которые переписываются (имя из знакомства)
    public var key: String?
    /// Закреплённое всегда в разговоре, остальное — когда к месту
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: Int64? = nil, kind: MemoryKind, text: String, source: String, conversationID: String? = nil, key: String? = nil,
                pinned: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.source = source
        self.conversationID = conversationID
        self.key = key
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Найденное место в прошлом разговоре
public struct ConversationHit: Sendable, Equatable, Identifiable {
    public var id: Int64 { messageID }
    public let messageID: Int64
    public let conversationID: String
    public let title: String
    public let kind: ConversationKind
    public let snippet: String
    public let date: Date

    public init(messageID: Int64, conversationID: String, title: String, kind: ConversationKind, snippet: String, date: Date) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.title = title
        self.kind = kind
        self.snippet = snippet
        self.date = date
    }
}

/// Запрос к полнотекстовому поиску с упрощённой русской морфологией (§5.2):
/// у каждого слова отрезается окончание и ищется начало («кнопки» → «кнопк*» найдёт «кнопку», «кнопок»)
public enum SearchQuery {
    static let endings = ["иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими", "иях", "ях", "ах", "ов", "ев", "ей",
                          "ам", "ям", "ом", "ем", "ой", "ий", "ый", "ая", "яя", "ое", "ее", "ые", "ие", "ую", "юю", "ия",
                          "ть", "ла", "ли", "ло", "а", "я", "ы", "и", "е", "о", "у", "ю", "ь", "й"]

    public static func stem(_ word: String) -> String {
        let w = word.lowercased().replacingOccurrences(of: "ё", with: "е")
        guard w.count > 4, w.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) else { return w }
        for e in endings where w.hasSuffix(e) && w.count - e.count >= 3 {
            return String(w.dropLast(e.count))
        }
        return w
    }

    /// Служебные слова, по которым искать бессмысленно (для поиска «по любому слову»)
    static let stopwords: Set<String> = ["что", "как", "где", "когда", "кто", "это", "мне", "меня", "мой", "моя", "мои", "про",
                                         "сколько", "какой", "какая", "какие", "который", "или", "для", "его", "она", "они",
                                         "был", "была", "было", "уже", "ещё", "еще", "там", "тут", "так", "все", "всё"]

    /// FTS5-запрос: каждое слово — префиксом; все слова (AND) или любое (OR). nil — искать нечего.
    public static func fts(_ text: String, anyWord: Bool = false) -> String? {
        var words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if anyWord { words = words.filter { $0.count >= 3 && !stopwords.contains($0) } }
        guard !words.isEmpty else { return nil }
        return words.prefix(8).map { "\"\(stem($0))\"*" }.joined(separator: anyWord ? " OR " : " ")
    }
}
