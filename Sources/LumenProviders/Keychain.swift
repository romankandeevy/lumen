import Foundation
import Security
import os

/// Секреты — только в Связке ключей (§10.4). В базе, логах и промптах их нет.
///
/// Чтение и запись идут через системную программу `security`, а не через SecItem самого Lumen. Причина (Рома, 27.10:
/// «просят три раза пароль»): запись, созданная Lumen, разрешена только сборке с тем же отпечатком кода (cdhash), а он
/// меняется с каждой сборкой и с каждым обновлением, — и macOS при первом чтении каждого секрета спрашивал пароль от входа.
/// У `security` отпечаток от Lumen не зависит, поэтому после одного «Всегда разрешать» вопросов больше нет.
/// Цена: записи может прочитать и другая программа пользователя через `security` — так же, как это делает сам Claude Code.
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
        // `.adopting` — копия, которую прежние версии оставляли при переносе записи: если основной нет, берём её
        guard let value = load(account) ?? load(account + Self.stagingSuffix) else { return nil }
        Self.cache.withLock { $0[key] = value }
        return value
    }

    private static let stagingSuffix = ".adopting"

    /// Прочитанное за запуск — второй раз Связку не трогаем
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String]())

    /// Есть ли запись — без чтения самого секрета: macOS на это не спрашивает пароль
    public func has(_ account: String) -> Bool {
        if Self.cache.withLock({ $0[service + "/" + account] }) != nil { return true }
        var q = base(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public func save(_ value: String, for account: String) throws {
        // секрет — шестнадцатеричной строкой и через stdin (`security -i`): ни в аргументах процесса, ни в кавычках
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        let run = Self.security(["-i"], stdin: "add-generic-password -U -s \(Self.quoted(service)) -a \(Self.quoted(account)) -X \(hex)\n")
        guard run.status == 0 else { throw KeychainError(status: OSStatus(run.status), detail: run.err) }
        // кэш — только после записи: иначе при ошибке приложение считало бы ключ сохранённым
        Self.cache.withLock { $0[service + "/" + account] = value }
    }

    public func delete(_ account: String) {
        Self.cache.withLock { $0[service + "/" + account] = nil }
        _ = Self.security(["delete-generic-password", "-s", service, "-a", account])
        _ = Self.security(["delete-generic-password", "-s", service, "-a", account + Self.stagingSuffix])
    }

    private func load(_ account: String) -> String? {
        // `-g` пишет секрет в stderr строкой `password: "…"`, а если там не только печатные символы (русский, перенос строки) —
        // `password: 0x<hex> …`. `-w` так не различает: у него и обычный токен из букв a–f и цифр выглядит как hex
        let run = Self.security(["find-generic-password", "-s", service, "-a", account, "-g"])
        guard run.status == 0 else { return nil }
        return Self.parsePassword(run.err)
    }

    /// Секрет из вывода `security … -g`
    static func parsePassword(_ output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("password: ") {
            let rest = line.dropFirst("password: ".count)
            if rest.hasPrefix("0x") {
                let hex = rest.dropFirst(2).prefix { $0.isHexDigit }
                guard hex.count % 2 == 0 else { return nil }
                var bytes: [UInt8] = []
                var i = hex.startIndex
                while i < hex.endIndex {
                    let j = hex.index(i, offsetBy: 2)
                    guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
                    bytes.append(b)
                    i = j
                }
                return String(decoding: bytes, as: UTF8.self)
            }
            if rest == "<NULL>" { return "" }
            if rest.hasPrefix("\""), rest.hasSuffix("\""), rest.count >= 2 { return String(rest.dropFirst().dropLast()) }
        }
        return nil
    }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Запуск /usr/bin/security. Пока macOS спрашивает пароль, процесс ждёт — вызывающий тоже
    private static func security(_ args: [String], stdin: String? = nil) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inp.fileHandleForWriting.close()
        // выводы читаем до конца до ожидания, иначе полный буфер трубы подвесит процесс
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var detail = ""
    public var errorDescription: String? {
        "Связка ключей: " + (detail.isEmpty ? ((SecCopyErrorMessageString(status, nil) as String?) ?? "ошибка \(status)") : detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
