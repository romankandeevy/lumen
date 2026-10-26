import Foundation

/// Проверка ключа OpenAI API (ChatGPT по ключу, не по подписке): список моделей — бесплатный запрос
public struct OpenAIAPI: Sendable {
    public let key: String
    public var baseURL = URL(string: "https://api.openai.com")!
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

    /// Ключ похож на настоящий? `sk-…` (в том числе `sk-proj-`, `sk-svcacct-`, `sk-admin-`), но не Anthropic
    public static func looksValid(_ key: String) -> Bool {
        (key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-")) && key.count > 20
    }

    /// Проверка ключа: список моделей — бесплатный запрос
    public func check() async -> KeyCheck {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: return .ok
            case 401, 403: return .rejected
            default: return .other(AnthropicAPI.message(from: data) ?? "OpenAI ответил \(code)")
            }
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(e.code) {
            return .noNetwork
        } catch {
            return .other(error.localizedDescription)
        }
    }
}
