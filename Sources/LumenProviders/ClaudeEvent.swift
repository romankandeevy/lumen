import Foundation
import LumenCore

/// Событие из `claude -p --output-format stream-json` (§2.2).
/// Декодер терпимый: формат меняется от версии к версии, незнакомое не роняет разговор.
public enum ClaudeEvent: Sendable, Equatable {
    case started(sessionID: String, model: String, tools: [String])
    /// Кусок текста ответа (при --include-partial-messages)
    case textDelta(String)
    /// Модель вызвала инструмент — человеческой строкой
    case step(AgentStep)
    case rateLimit(RateLimit)
    case retry(attempt: Int, error: String)
    case finished(TurnResult)
    case unknown(String)

    public struct RateLimit: Sendable, Equatable {
        public let status: String
        /// «five_hour» и т. п. — тип окна приходит прямо в событии (спайк 3)
        public let window: String?
        public let resetsAt: Date?
    }

    public struct TurnResult: Sendable, Equatable {
        public let ok: Bool
        public let text: String
        public let sessionID: String
        /// Оценка CLI, по подписке это «сколько стоило бы по API»
        public let costUSD: Double
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
    }

    /// Все события строки: в одном сообщении может быть несколько вызовов инструментов
    public static func decodeAll(_ line: Data) -> [ClaudeEvent] {
        if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], obj["type"] as? String == "assistant" {
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.filter { $0["type"] as? String == "tool_use" }.map {
                .step(AgentStep.from(tool: $0["name"] as? String ?? "", input: $0["input"] as? [String: Any] ?? [:]))
            }
        }
        return decode(line).map { [$0] } ?? []
    }

    /// Разбирает одну строку вывода. Пустые и служебные строки → nil.
    public static func decode(_ line: Data) -> ClaudeEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        let subtype = obj["subtype"] as? String

        switch (type, subtype) {
        case ("system", "init"):
            return .started(sessionID: obj["session_id"] as? String ?? "",
                            model: obj["model"] as? String ?? "",
                            tools: obj["tools"] as? [String] ?? [])
        case ("system", "api_retry"):
            return .retry(attempt: obj["attempt"] as? Int ?? 0, error: obj["error"] as? String ?? "")
        case ("system", _):
            // status, thinking_tokens, post_turn_summary и др. — служебные
            return nil
        case ("stream_event", _):
            guard let ev = obj["event"] as? [String: Any],
                  let delta = ev["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .textDelta(text)
        case ("assistant", _):
            // целые сообщения: текст уже пришёл дельтами, отсюда берём только вызовы инструментов
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            if let tool = content.first(where: { $0["type"] as? String == "tool_use" }) {
                return .step(AgentStep.from(tool: tool["name"] as? String ?? "", input: tool["input"] as? [String: Any] ?? [:]))
            }
            return nil
        case ("user", _):
            return nil
        case ("rate_limit_event", _):
            let info = obj["rate_limit_info"] as? [String: Any] ?? [:]
            return .rateLimit(RateLimit(status: info["status"] as? String ?? "",
                                        window: info["rateLimitType"] as? String,
                                        resetsAt: (info["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))))
        case ("result", _):
            let usage = obj["usage"] as? [String: Any] ?? [:]
            let isError = obj["is_error"] as? Bool ?? (subtype != "success")
            return .finished(TurnResult(ok: !isError,
                                        text: obj["result"] as? String ?? "",
                                        sessionID: obj["session_id"] as? String ?? "",
                                        costUSD: obj["total_cost_usd"] as? Double ?? 0,
                                        inputTokens: usage["input_tokens"] as? Int ?? 0,
                                        outputTokens: usage["output_tokens"] as? Int ?? 0,
                                        cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0))
        default:
            return .unknown(type)
        }
    }
}
