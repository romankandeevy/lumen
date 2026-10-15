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

    public init(onboarded: Bool = false, backend: Backend = .subscription, theme: Theme = .lumen, reducedMotion: Bool = false) {
        self.onboarded = onboarded
        self.backend = backend
        self.theme = theme
        self.reducedMotion = reducedMotion
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
