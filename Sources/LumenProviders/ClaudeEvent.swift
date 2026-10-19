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
    /// Разговор сжат (`/compact` или автоматически)
    case compacted
    /// Агент обновил план (TodoWrite, TaskCreate, TaskUpdate)
    case plan(PlanItem.Change)
    case finished(TurnResult)
    /// Агент просит разрешения (режимы «Спрашивать», «Принимать правки», «Авто», «План» — выход из плана)
    case permission(PermissionRequest)
    /// Метка сообщения claude (uuid): к ней можно откатить разговор (`--resume-session-at`)
    case anchor(String)
    /// Инструмент вернул результат (сообщение user с tool_result)
    case toolDone
    case unknown(String)

    public struct PermissionRequest: Sendable, Equatable, Identifiable {
        public let id: String
        public let tool: String
        /// Вход инструмента как JSON — чтобы отдать его обратно как есть
        public let inputJSON: String
        public let description: String

        public init(id: String, tool: String, inputJSON: String, description: String) {
            self.id = id
            self.tool = tool
            self.inputJSON = inputJSON
            self.description = description
        }

        public var input: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any]) ?? [:]
        }

        /// Человеческая строка: что именно хочет сделать
        public var step: AgentStep { AgentStep.from(tool: tool, input: input) }
    }

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
        public var cacheWriteTokens = 0
        /// Сколько занял разговор на последнем запросе хода и сколько вмещает окно
        public var contextTokens = 0
        public var contextWindow = 0
    }

    /// Из ответа инструмента: «Task #7 created successfully: Название» → номер и название. Текст — строкой или блоками.
    static func taskCreated(_ block: [String: Any]) -> (id: String, subject: String)? {
        guard block["type"] as? String == "tool_result" else { return nil }
        let text: String
        if let s = block["content"] as? String {
            text = s
        } else if let parts = block["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            return nil
        }
        guard let m = text.firstMatch(of: /Task #(\d+) created successfully:?[ \t]*(.*)/) else { return nil }
        return (String(m.1), String(m.2).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Все события строки: в одном сообщении может быть несколько вызовов инструментов
    public static func decodeAll(_ line: Data) -> [ClaudeEvent] {
        if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], obj["type"] as? String == "assistant" {
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let anchor: [ClaudeEvent] = (obj["uuid"] as? String).map { [.anchor($0)] } ?? []
            return anchor + content.filter { $0["type"] as? String == "tool_use" }.flatMap { block -> [ClaudeEvent] in
                let name = block["name"] as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                var out: [ClaudeEvent] = [.step(AgentStep.from(tool: name, input: input))]
                switch name {
                case "TodoWrite":
                    if let todos = input["todos"] as? [[String: Any]] { out.append(.plan(.replace(PlanItem.from(todos: todos)))) }
                case "TaskCreate":
                    if let subject = input["subject"] as? String { out.append(.plan(.add(subject))) }
                case "TaskUpdate":
                    if let id = input["taskId"] as? String ?? (input["taskId"] as? Int).map(String.init) {
                        out.append(.plan(.update(id: id, status: input["status"] as? String, text: input["subject"] as? String)))
                    }
                default: break
                }
                return out
            }
        }
        if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], obj["type"] as? String == "user",
           let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]],
           content.contains(where: { $0["type"] as? String == "tool_result" }) {
            // ответ на TaskCreate несёт настоящий номер задачи — по нему потом придёт TaskUpdate
            let created: [ClaudeEvent] = content.compactMap(taskCreated).map { .plan(.created(id: $0.id, subject: $0.subject)) }
            // по событию на каждый ответ инструмента: при нескольких командах сразу Lumen считает, сколько ещё идёт
            let done = content.filter { $0["type"] as? String == "tool_result" }.map { _ in ClaudeEvent.toolDone }
            return done + created
        }
        return decode(line).map { [$0] } ?? []
    }

    /// Разбирает одну строку вывода. Пустые и служебные строки → nil.
    public static func decode(_ line: Data) -> ClaudeEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        let subtype = obj["subtype"] as? String

        switch (type, subtype) {
        case ("control_request", _):
            guard let req = obj["request"] as? [String: Any], req["subtype"] as? String == "can_use_tool",
                  let id = obj["request_id"] as? String else { return nil }
            let input = req["input"] as? [String: Any] ?? [:]
            let json = String(decoding: (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8), as: UTF8.self)
            return .permission(.init(id: id, tool: req["tool_name"] as? String ?? "", inputJSON: json,
                                     description: req["description"] as? String ?? ""))
        case ("system", "init"):
            return .started(sessionID: obj["session_id"] as? String ?? "",
                            model: obj["model"] as? String ?? "",
                            tools: obj["tools"] as? [String] ?? [])
        case ("system", "compact_boundary"):
            return .compacted
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
            var r = TurnResult(ok: !isError,
                               text: obj["result"] as? String ?? "",
                               sessionID: obj["session_id"] as? String ?? "",
                               costUSD: obj["total_cost_usd"] as? Double ?? 0,
                               inputTokens: usage["input_tokens"] as? Int ?? 0,
                               outputTokens: usage["output_tokens"] as? Int ?? 0,
                               cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0)
            r.cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
            // контекст — вход последнего запроса хода (у агента их несколько)
            let last = (usage["iterations"] as? [[String: Any]])?.last ?? usage
            r.contextTokens = (last["input_tokens"] as? Int ?? 0) + (last["cache_read_input_tokens"] as? Int ?? 0)
                + (last["cache_creation_input_tokens"] as? Int ?? 0)
            r.contextWindow = (obj["modelUsage"] as? [String: [String: Any]])?.values.compactMap { $0["contextWindow"] as? Int }.max() ?? 0
            return .finished(r)
        default:
            return .unknown(type)
        }
    }
}
