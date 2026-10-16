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
    /// «Запоминать само»: Lumen сам сохраняет важное из разговора, а не только по просьбе «запомни»
    public var autoRemember = true
    /// Предохранитель API: не тратить больше стольких долларов в месяц (§18.3: $100, что входят в Max)
    public var monthlyLimit = 100
    /// Правая панель «Контекст» открыта
    public var contextOpen = false
    /// Левая панель спрятана (кнопка рядом с кнопками окна, как в Claude)
    public var sidebarHidden = false
    /// Модель и «сколько думать» для новой задачи агента (у чата — `model` и `effort`)
    public var agentModel: ChatModel?
    public var agentEffort: Effort?
    /// Получать бета-версии (1.0.1, 1.0.2…), а не только стабильные
    public var betaUpdates = false

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
        autoRemember = try c.decodeIfPresent(Bool.self, forKey: .autoRemember) ?? true
        monthlyLimit = try c.decodeIfPresent(Int.self, forKey: .monthlyLimit) ?? 100
        contextOpen = try c.decodeIfPresent(Bool.self, forKey: .contextOpen) ?? false
        sidebarHidden = try c.decodeIfPresent(Bool.self, forKey: .sidebarHidden) ?? false
        betaUpdates = try c.decodeIfPresent(Bool.self, forKey: .betaUpdates) ?? false
        agentModel = try? c.decodeIfPresent(ChatModel.self, forKey: .agentModel)
        agentEffort = try? c.decodeIfPresent(Effort.self, forKey: .agentEffort)
    }
}

