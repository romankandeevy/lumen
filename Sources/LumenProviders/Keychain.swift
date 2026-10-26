import Foundation
import Security
import os

/// Секреты — только в Связке ключей (§10.4). В базе, логах и промптах их нет.
public struct Keychain: Sendable {
    public let service: String

    /// LUMEN_KEYCHAIN — другая «папка» в Связке ключей, чтобы тесты не трогали настоящий ключ
    public init(service: String = Keychain.defaultService) {
        self.service = service
    }

    /// Настоящая Связка ключей — только у самого Lumen.app. Тесты и всё прочее без LUMEN_KEYCHAIN идут в свою «папку»:
    /// иначе они читают и переписывают настоящие ключи, и Lumen потом просит пароль.
    public static var defaultService: String {
        if let s = ProcessInfo.processInfo.environment["LUMEN_KEYCHAIN"], !s.isEmpty { return s }
        return isApp ? "com.roman.lumen" : "com.roman.lumen.tests"
    }

    static var isApp: Bool { Bundle.main.bundleIdentifier == "com.roman.lumen" }

    public static let anthropicKey = "anthropic-api-key"
    /// Ключ OpenAI API: ChatGPT по ключу, не по подписке (вход codex этим ключом)
    public static let openaiKey = "openai-api-key"

    public func read(_ account: String) -> String? {
        let key = service + "/" + account
        if let v = Self.cache.withLock({ $0[key] }) { return v }
        guard let value = load(account) ?? load(account + Self.stagingSuffix) else { return nil }
        Self.cache.withLock { $0[key] = value }
        // запись могла остаться от старой сборки — тогда macOS спрашивает доступ при каждом запуске.
        // Переписываем её от имени этой сборки (подпись постоянная): дальше вопросов не будет.
        // только сам Lumen.app: переписанная тестами запись принадлежала бы тестам (так и случилось 16.10)
        if Self.isApp, !Self.adopted.withLock({ $0.contains(key) }) {
            Self.adopted.withLock { _ = $0.insert(key) }
            adopt(value, account)
        }
        return value
    }

    private static let stagingSuffix = ".adopting"
    private static let log = Logger(subsystem: "com.roman.lumen", category: "keychain")

    private func load(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Перенос в запись этой сборки. Сначала копия под временным именем, потом старая запись удаляется
    /// и заводится новая, и только после этого копия. Если что-то падает, секрет остаётся хотя бы в одной записи:
    /// `read` возьмёт копию, а перенос повторится при следующем запуске (отметка ставится только при успехе).
    private func adopt(_ value: String, _ account: String) {
        let done = UserDefaults.standard.stringArray(forKey: "lumen.keychainAdopted.v2") ?? []
        let key = service + "/" + account
        guard !done.contains(key) else { return }
        let staging = account + Self.stagingSuffix
        do {
            SecItemDelete(base(staging) as CFDictionary)
            try add(value, staging)
            SecItemDelete(base(account) as CFDictionary)
            try add(value, account)
            SecItemDelete(base(staging) as CFDictionary)
            UserDefaults.standard.set(done + [key], forKey: "lumen.keychainAdopted.v2")
        } catch {
            Self.log.error("Перенос ключа \(account) не удался: \(error.localizedDescription, privacy: .public). Копия в \(staging, privacy: .public)")
        }
    }

    /// Прочитанное за запуск — второй раз Связку не трогаем
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String]())
    private static let adopted = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Есть ли запись — без чтения самого секрета: macOS на это не спрашивает пароль
    public func has(_ account: String) -> Bool {
        if Self.cache.withLock({ $0[service + "/" + account] }) != nil { return true }
        var q = base(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public func save(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base(account)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError(status: add) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
        // кэш — только после записи: иначе при ошибке приложение считало бы ключ сохранённым
        Self.cache.withLock { $0[service + "/" + account] = value }
    }

    private func add(_ value: String, _ account: String) throws {
        var q = base(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) {
        Self.cache.withLock { $0[service + "/" + account] = nil }
        SecItemDelete(base(account) as CFDictionary)
    }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        "Связка ключей: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "ошибка \(status)")
    }
}
