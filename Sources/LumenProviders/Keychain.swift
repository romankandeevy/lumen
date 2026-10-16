import Foundation
import Security
import os

/// Секреты — только в Связке ключей (§10.4). В базе, логах и промптах их нет.
public struct Keychain: Sendable {
    public let service: String

    /// LUMEN_KEYCHAIN — другая «папка» в Связке ключей, чтобы тесты не трогали настоящий ключ
    public init(service: String = ProcessInfo.processInfo.environment["LUMEN_KEYCHAIN"] ?? "com.roman.lumen") {
        self.service = service
    }

    public static let anthropicKey = "anthropic-api-key"

    public func read(_ account: String) -> String? {
        let key = service + "/" + account
        if let v = Self.cache.withLock({ $0[key] }) { return v }
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        Self.cache.withLock { $0[key] = value }
        // запись могла остаться от старой сборки — тогда macOS спрашивает доступ при каждом запуске.
        // Переписываем её от имени этой сборки (подпись постоянная): дальше вопросов не будет.
        if !Self.adopted.withLock({ $0.contains(key) }) {
            Self.adopted.withLock { _ = $0.insert(key) }
            let done = UserDefaults.standard.stringArray(forKey: "lumen.keychainAdopted") ?? []
            if !done.contains(key) {
                SecItemDelete(base(account) as CFDictionary)
                try? add(value, account)
                UserDefaults.standard.set(done + [key], forKey: "lumen.keychainAdopted")
            }
        }
        return value
    }

    /// Прочитанное за запуск — второй раз Связку не трогаем
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String]())
    private static let adopted = OSAllocatedUnfairLock(initialState: Set<String>())

    public func save(_ value: String, for account: String) throws {
        Self.cache.withLock { $0[service + "/" + account] = value }
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
