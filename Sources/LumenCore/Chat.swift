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

/// Чат — просто разговор; агент — работа в папке проекта
public enum ConversationKind: String, Codable, Sendable { case chat, agent }

/// Шаг агента: что он делал (читал, правил, запускал) — из вызовов инструментов
public struct AgentStep: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable { case read, edit, run, search, web, think, other }
    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    /// Человеческая строка из имени инструмента и его входа
    public static func from(tool: String, input: [String: Any]) -> AgentStep {
        func file(_ k: String) -> String { ((input[k] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "" }
        switch tool {
        case "Read": return .init(kind: .read, text: "Читает \(file("file_path"))")
        case "Edit", "MultiEdit": return .init(kind: .edit, text: "Правит \(file("file_path"))")
        case "Write": return .init(kind: .edit, text: "Пишет \(file("file_path"))")
        case "NotebookEdit": return .init(kind: .edit, text: "Правит \(file("notebook_path"))")
        case "Bash":
            let cmd = (input["description"] as? String) ?? (input["command"] as? String) ?? ""
            return .init(kind: .run, text: "Запускает: " + String(cmd.prefix(80)))
        case "Grep": return .init(kind: .search, text: "Ищет «\((input["pattern"] as? String ?? "").prefix(40))»")
        case "Glob": return .init(kind: .search, text: "Ищет файлы \((input["pattern"] as? String ?? "").prefix(40))")
        case "WebSearch": return .init(kind: .web, text: "Ищет в интернете «\((input["query"] as? String ?? "").prefix(40))»")
        case "WebFetch": return .init(kind: .web, text: "Открывает \((input["url"] as? String ?? "").prefix(60))")
        case "TodoWrite": return .init(kind: .think, text: "Обновляет план")
        case "Task", "Agent": return .init(kind: .think, text: "Отдаёт часть работы помощнику")
        case "remember", "mcp__lumen__remember": return .init(kind: .think, text: "Запоминает")
        case "recall", "mcp__lumen__recall": return .init(kind: .think, text: "Вспоминает")
        default: return .init(kind: .other, text: tool.hasPrefix("mcp__") ? tool.components(separatedBy: "__").last ?? tool : tool)
        }
    }
}

/// Изменённый агентом файл (карточка «Изменения»)
public struct FileChange: Codable, Sendable, Equatable, Hashable {
    public var path: String
    /// M — изменён, A — новый, D — удалён
    public var status: String
    public var added: Int
    public var removed: Int
    /// Файл был изменён ещё до хода агента — его не откатываем, чтобы не потерять чужую работу
    public var preexisting: Bool

    public init(path: String, status: String, added: Int, removed: Int, preexisting: Bool = false) {
        self.path = path
        self.status = status
        self.added = added
        self.removed = removed
        self.preexisting = preexisting
    }
}

/// Карточка «Изменения» после хода агента
public struct ChangeSet: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case applied, committed, reverted }
    public var files: [FileChange]
    public var state: State

    public init(files: [FileChange], state: State = .applied) {
        self.files = files
        self.state = state
    }
}

/// Разговор во вкладке «Чат» или «Агент». Через что он думает, выбирается при создании и не меняется:
/// у подписки история живёт в сессии `claude`, у API — в базе Lumen.
public struct Conversation: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kind: ConversationKind
    /// Папка проекта — только у агента
    public var folder: String?
    public var backend: Backend
    public var model: ChatModel
    public var effort: Effort
    /// Сессия `claude` для режима подписки — для `--resume`
    public var cliSessionID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), title: String = "", kind: ConversationKind = .chat, folder: String? = nil,
                backend: Backend, model: ChatModel, effort: Effort, cliSessionID: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.kind = kind
        self.folder = folder
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
    /// Шаги агента за этот ход
    public var steps: [AgentStep]
    /// Что агент поменял в файлах
    public var changes: ChangeSet?
    /// Факты, которые Lumen запомнил за этот ход («Запомнил») и на которые опирался («Опирался на»)
    public var remembered: [Int64]
    public var recalled: [Int64]
    public var createdAt: Date

    public init(id: Int64? = nil, conversationID: String, role: Role, text: String, apiContent: String? = nil,
                model: ChatModel? = nil, stopped: Bool = false, error: String? = nil, steps: [AgentStep] = [],
                changes: ChangeSet? = nil, remembered: [Int64] = [], recalled: [Int64] = [], createdAt: Date = Date()) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.apiContent = apiContent
        self.model = model
        self.stopped = stopped
        self.error = error
        self.steps = steps
        self.changes = changes
        self.remembered = remembered
        self.recalled = recalled
        self.createdAt = createdAt
    }
}
