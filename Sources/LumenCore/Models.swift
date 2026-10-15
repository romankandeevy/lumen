import Foundation

// Доменные типы Lumen. Здесь только то, что уже используется.

/// Как обращаться к человеку
public enum Address: String, Codable, Sendable, CaseIterable {
    case ty, vy
}

/// Через что Lumen думает
public enum Backend: String, Codable, Sendable, CaseIterable {
    /// Подписка через установленный у пользователя `claude`
    case subscription
    /// Ключ Anthropic API
    case api
}

/// Тема окна. Обе тёмные, светлой нет.
public enum Theme: String, Codable, Sendable, CaseIterable {
    case lumen, mono
}

/// Ширина переписки: чат, агент и боты (`chatWidthClass` в макете)
public enum ChatWidth: String, Codable, Sendable, CaseIterable {
    case normal, wide, full

    /// max-w-[44rem] / [60rem] / [88rem]
    public var points: Double {
        switch self { case .normal: 704; case .wide: 960; case .full: 1408 }
    }
}

/// Кто пользуется Lumen — из знакомства
public struct Profile: Codable, Sendable, Equatable {
    public var name: String
    public var address: Address

    public init(name: String = "", address: Address = .ty) {
        self.name = name
        self.address = address
    }
}

/// Настройки, которые хранятся в базе
public struct Preferences: Codable, Sendable, Equatable {
    public var onboarded: Bool
    public var backend: Backend
    public var theme: Theme
    public var reducedMotion: Bool
    /// Последние выбранные в чате модель и «сколько думать» — для нового чата
    public var model: ChatModel
    public var effort: Effort
    public var chatWidth: ChatWidth
    /// Папки, где недавно работал агент — первая выбрана для новой задачи
    public var recentFolders: [String] = []

    public init(onboarded: Bool = false, backend: Backend = .subscription, theme: Theme = .lumen, reducedMotion: Bool = false,
                model: ChatModel = .sonnet, effort: Effort = .medium, chatWidth: ChatWidth = .normal) {
        self.onboarded = onboarded
        self.backend = backend
        self.theme = theme
        self.reducedMotion = reducedMotion
        self.model = model
        self.effort = effort
        self.chatWidth = chatWidth
    }

    // старые настройки (0.1) без модели и effort читаются с умолчаниями
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        backend = try c.decodeIfPresent(Backend.self, forKey: .backend) ?? .subscription
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .lumen
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        model = try c.decodeIfPresent(ChatModel.self, forKey: .model) ?? .sonnet
        effort = try c.decodeIfPresent(Effort.self, forKey: .effort) ?? .medium
        chatWidth = try c.decodeIfPresent(ChatWidth.self, forKey: .chatWidth) ?? .normal
        recentFolders = try c.decodeIfPresent([String].self, forKey: .recentFolders) ?? []
    }
}

/// Факт памяти. Пока пишется только знакомством; поиск и показ — в «Памяти».
public struct MemoryFact: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var kind: String
    public var text: String
    public var source: String
    public var pinned: Bool
    public var createdAt: Date

    public init(id: Int64? = nil, kind: String, text: String, source: String, pinned: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.source = source
        self.pinned = pinned
        self.createdAt = createdAt
    }
}
