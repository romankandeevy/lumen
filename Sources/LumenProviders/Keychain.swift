import Foundation
import Security

/// Секреты — только в Связке ключей (§10.4). В базе, логах и промптах их нет.
public struct Keychain: Sendable {
    public let service: String

    /// LUMEN_KEYCHAIN — другая «папка» в Связке ключей, чтобы тесты не трогали настоящий ключ
    public init(service: String = ProcessInfo.processInfo.environment["LUMEN_KEYCHAIN"] ?? "com.roman.lumen") {
        self.service = service
    }

    public static let anthropicKey = "anthropic-api-key"

    public func read(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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
    }

    public func delete(_ account: String) {
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
