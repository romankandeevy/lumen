import Foundation

/// Модели Claude, которые Lumen предлагает в чате (как в макете, `lib/mock-data.ts`)
public enum ChatModel: String, Codable, Sendable, CaseIterable, Identifiable {
    case fable = "claude-fable-5-1"
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .fable: "Fable 5.1"
        case .opus: "Opus 5.5"
        case .sonnet: "Sonnet 5.5"
        case .haiku: "Haiku 5.5"
        }
    }

    public var note: String {
        switch self {
        case .fable: "самый сильный, для сложного"
        case .opus: "умный, для кода и разбора"
        case .sonnet: "быстрый, на каждый день"
        case .haiku: "мгновенный и дешёвый"
        }
    }

    /// Если модель откажется отвечать по правилам безопасности, API сам доотвечает другой моделью.
    /// У Haiku такого нет.
    public var hasServerFallback: Bool { self != .haiku }
}

/// «Сколько думать» — effort, одинаковый у CLI и API
public enum Effort: String, Codable, Sendable, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .low: "Низкий"
        case .medium: "Средний"
        case .high: "Высокий"
        case .xhigh: "Сверхвысокий"
        case .max: "Максимальный"
        }
    }

    public var note: String {
        switch self {
        case .low: "быстрые ответы на простое"
        case .medium: "обычные вопросы и правки"
        case .high: "код и разбор"
        case .xhigh: "сложные баги, большие правки"
        case .max: "самое трудное, думает долго"
        }
    }

    public var level: Int { Effort.allCases.firstIndex(of: self) ?? 0 }
}

/// Разговор во вкладке «Чат». Через что он думает, выбирается при создании и не меняется:
/// у подписки история живёт в сессии `claude`, у API — в базе Lumen.
public struct Conversation: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var backend: Backend
    public var model: ChatModel
    public var effort: Effort
    /// Сессия `claude` для режима подписки — для `--resume`
    public var cliSessionID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), title: String = "", backend: Backend, model: ChatModel,
                effort: Effort, cliSessionID: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.backend = backend
        self.model = model
        self.effort = effort
        self.cliSessionID = cliSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Сообщение разговора
public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: Int64?
    public var conversationID: String
    public var role: Role
    public var text: String
    /// Ответ API целиком (блоки content в JSON): при следующем ходе отправляется как есть,
    /// чтобы история только дописывалась (§3 техплана)
    public var apiContent: String?
    public var model: ChatModel?
    /// Остановлен кнопкой «Стоп»
    public var stopped: Bool
    /// Понятная ошибка вместо ответа
    public var error: String?
    public var createdAt: Date

    public init(id: Int64? = nil, conversationID: String, role: Role, text: String, apiContent: String? = nil,
                model: ChatModel? = nil, stopped: Bool = false, error: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.apiContent = apiContent
        self.model = model
        self.stopped = stopped
        self.error = error
        self.createdAt = createdAt
    }
}
