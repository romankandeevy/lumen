import Foundation

/// Тонкий клиент Anthropic API на URLSession (§3). Пока умеет только проверить ключ;
/// чат по ключу добавится вместе с чатом.
public struct AnthropicAPI: Sendable {
    public let key: String
    public var baseURL = URL(string: "https://api.anthropic.com")!
    public var session: URLSession = .shared

    public init(key: String) {
        self.key = key
    }

    public enum KeyCheck: Equatable, Sendable {
        case ok
        case rejected
        case noNetwork
        case other(String)
    }

    /// Ключ похож на настоящий? Проверка до запроса
    public static func looksValid(_ key: String) -> Bool {
        key.hasPrefix("sk-ant-") && key.count > 20
    }

    /// Проверка ключа: список моделей — бесплатный запрос
    public func check() async -> KeyCheck {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: return .ok
            case 401, 403: return .rejected
            default: return .other(Self.message(from: data) ?? "Anthropic ответил \(code)")
            }
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(e.code) {
            return .noNetwork
        } catch {
            return .other(error.localizedDescription)
        }
    }

    static func message(from data: Data) -> String? {
        struct E: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        return (try? JSONDecoder().decode(E.self, from: data))?.error.message
    }
}
