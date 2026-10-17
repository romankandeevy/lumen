import Foundation

/// Установленный у пользователя официальный `claude` (§2). Lumen его только запускает:
/// токены не читает, вход делает сам `claude auth login`.
public struct ClaudeCLI: Sendable {
    public let binary: URL

    /// Ниже этой версии Lumen не работает: на ней проверены спайки (docs/spikes.md)
    public static let minimumVersion = Version(2, 1, 278)

    public init(binary: URL) {
        self.binary = binary
    }

    /// Находит `claude` в PATH
    public static func locate() -> ClaudeCLI? {
        Shell.which("claude").map(ClaudeCLI.init)
    }

    public func version() async throws -> Version {
        let out = try await Shell.run(binary, ["--version"])
        guard let v = Version(parsing: out.stdout) else { throw ClaudeError.unreadable("claude --version: \(out.stdout)") }
        return v
    }

    // MARK: вход

    public struct AuthStatus: Decodable, Sendable, Equatable {
        public let loggedIn: Bool
        public let authMethod: String?
        public let email: String?
        public let subscriptionType: String?

        /// «Max», «Pro» — как тариф называется у Anthropic
        public var planName: String? {
            subscriptionType.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
    }

    /// Установленные плагины Claude Code (id вида `vercel@claude-plugins-official`) — Lumen их выключает у себя
    public func plugins() async -> [String]? {
        guard let out = try? await Shell.run(binary, ["plugin", "list", "--json"]),
              let list = try? JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [[String: Any]] else { return nil }
        return list.compactMap { $0["id"] as? String }
    }

    public func authStatus() async throws -> AuthStatus {
        let out = try await Shell.run(binary, ["auth", "status", "--json"])
        guard let data = out.stdout.data(using: .utf8),
              let s = try? JSONDecoder().decode(AuthStatus.self, from: data)
        else { throw ClaudeError.unreadable("claude auth status: \(out.stdout)\(out.stderr)") }
        return s
    }

    /// Вход через браузер — собственный поток Anthropic. Ждёт, пока пользователь войдёт.
    public func login() async throws {
        let out = try await Shell.run(binary, ["auth", "login"])
        if out.status != 0 { throw ClaudeError.failed(out.stderr.isEmpty ? out.stdout : out.stderr) }
    }

    public func logout() async throws {
        let out = try await Shell.run(binary, ["auth", "logout"])
        if out.status != 0 { throw ClaudeError.failed(out.stderr.isEmpty ? out.stdout : out.stderr) }
    }

    // MARK: лимиты подписки

    /// Спрашивает `/usage` в коротком отдельном запуске (§2.3, проверено в спайке 3).
    /// Настройки ~/.claude не грузим: хуки острова не должны считать это сессией.
    public func usage() async throws -> [UsageWindow] {
        let out = try await Shell.run(binary, ["-p", "/usage", "--output-format", "json", "--setting-sources", ""])
        struct R: Decodable { let result: String? }
        guard let data = out.stdout.data(using: .utf8),
              let text = (try? JSONDecoder().decode(R.self, from: data))?.result
        else { throw ClaudeError.unreadable("/usage: \(out.stdout)\(out.stderr)") }
        return UsageWindow.parse(text)
    }
}

public enum ClaudeError: Error, LocalizedError, Equatable {
    case notInstalled
    case tooOld(Version)
    case unreadable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Claude Code не найден на этом Маке"
        case .tooOld(let v): "Claude Code \(v) слишком старый, нужен \(ClaudeCLI.minimumVersion) или новее"
        case .unreadable(let s): "Claude Code ответил непонятно: \(s.prefix(200))"
        case .failed(let s): s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Версия `claude` вида 2.1.278
public struct Version: Comparable, Sendable, CustomStringConvertible, Equatable {
    public let parts: [Int]

    public init(_ a: Int, _ b: Int, _ c: Int) { parts = [a, b, c] }

    /// Из строки «2.1.278 (Claude Code)»
    public init?(parsing s: String) {
        guard let token = s.split(whereSeparator: { $0 == " " || $0 == "\n" }).first else { return nil }
        let nums = token.split(separator: ".").compactMap { Int($0) }
        guard nums.count >= 2 else { return nil }
        parts = nums
    }

    public static func < (l: Version, r: Version) -> Bool {
        for i in 0..<max(l.parts.count, r.parts.count) {
            let a = i < l.parts.count ? l.parts[i] : 0, b = i < r.parts.count ? r.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Одно окно лимита из `/usage`: «Current session: 44% used · resets Oct 16 at 12:50am (Europe/Moscow)»
public struct UsageWindow: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case session, week, weekModel(String)
    }

    public let kind: Kind
    public let percent: Int
    public let resetsAt: Date?

    public init(kind: Kind, percent: Int, resetsAt: Date?) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
    }

    public static func parse(_ text: String, now: Date = Date()) -> [UsageWindow] {
        var result: [UsageWindow] = []
        let re = /Current (session|week \(([^)]+)\)):\s*(\d+)% used(?:\s*·\s*resets (.+?)(?:\s*\(([^)]+)\))?)?\s*$/
        for line in text.split(separator: "\n") {
            guard let m = String(line).trimmingCharacters(in: .whitespaces).firstMatch(of: re) else { continue }
            let kind: Kind
            if m.1 == "session" {
                kind = .session
            } else if m.2.map(String.init) == "all models" {
                kind = .week
            } else {
                kind = .weekModel(m.2.map(String.init) ?? "")
            }
            let resets = m.4.flatMap { parseReset(String($0), zone: m.5.map(String.init), now: now) }
            result.append(UsageWindow(kind: kind, percent: Int(m.3) ?? 0, resetsAt: resets))
        }
        return result
    }

    /// «Oct 16 at 12:50am» или «Oct 22 at 5pm» — без года: берём ближайшее будущее
    static func parseReset(_ s: String, zone: String?, now: Date) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f.timeZone
        let year = cal.component(.year, from: now)
        for format in ["MMM d 'at' h:mma yyyy", "MMM d 'at' ha yyyy"] {
            f.dateFormat = format
            if var d = f.date(from: "\(s) \(year)") {
                // Dec 31 → Jan 1: дата сброса не может быть в прошлом больше чем на сутки
                if d < now.addingTimeInterval(-86_400), let next = cal.date(byAdding: .year, value: 1, to: d) { d = next }
                return d
            }
        }
        return nil
    }
}
