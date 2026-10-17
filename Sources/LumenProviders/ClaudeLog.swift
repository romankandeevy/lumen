import Foundation

/// Журнал процесса `claude` человеческими строками — чтобы было видно, думает он, ждёт API, работает или завис
/// (Рома, 17.10: «вкладку с логами Claude Code, чтобы понятно было, зависло это или нет»).
public enum ClaudeLog {
    public struct Line: Sendable, Identifiable, Equatable {
        public enum Kind: String, Sendable { case info, think, text, tool, wait, error, done }
        public let id = UUID()
        public let at: Date
        public let kind: Kind
        public let text: String

        public init(at: Date = Date(), kind: Kind, text: String) {
            self.at = at
            self.kind = kind
            self.text = text
        }
    }

    /// Что помнить между строками: какие инструменты вызваны (id → имя)
    public final class State: @unchecked Sendable {
        var tools: [String: String] = [:]
        public init() {}
    }

    /// Одна строка stream-json → строка журнала (дельты текста и служебный шум — nil)
    public static func summarize(_ line: Data, state: State) -> Line? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = o["type"] as? String else { return nil }
        let sub = o["subtype"] as? String
        switch (type, sub) {
        case ("system", "init"):
            let tools = (o["tools"] as? [Any])?.count ?? 0
            let mcp = (o["mcp_servers"] as? [[String: Any]])?.map { "\($0["name"] ?? "?"): \($0["status"] ?? "?")" }.joined(separator: ", ")
            return Line(kind: .info, text: "Claude Code \(o["claude_code_version"] as? String ?? "") готов: \(o["model"] as? String ?? ""), инструментов \(tools)"
                        + (mcp.map { $0.isEmpty ? "" : ", MCP — \($0)" } ?? ""))
        case ("system", "api_retry"):
            let delay = ((o["retry_delay_ms"] as? Double) ?? Double(o["retry_delay_ms"] as? Int ?? 0)) / 1000
            return Line(kind: .error, text: "Ошибка API\(o["error_status"].map { " \($0)" } ?? "") — повтор \(o["attempt"] ?? "?")/\(o["max_retries"] ?? "?") через \(Int(delay)) с\((o["error"] as? String).map { ": \($0)" } ?? "")")
        case ("system", "compact_boundary"):
            return Line(kind: .info, text: "Разговор сжат")
        case ("system", "status"):
            guard let s = o["status"] as? String, !s.isEmpty else { return nil }
            return Line(kind: .wait, text: s == "compacting" ? "Сжимает разговор…" : "Статус: \(s)")
        case ("system", let s):
            if ["thinking_tokens", "post_turn_summary", "hook_response", "hook_started"].contains(s ?? "") { return nil }
            return Line(kind: .info, text: "Служебное: \(s ?? "system")")
        case ("stream_event", _):
            guard let ev = o["event"] as? [String: Any] else { return nil }
            switch ev["type"] as? String {
            case "message_start":
                let u = (ev["message"] as? [String: Any])?["usage"] as? [String: Any] ?? [:]
                let input = (u["input_tokens"] as? Int ?? 0) + (u["cache_read_input_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
                let cached = u["cache_read_input_tokens"] as? Int ?? 0
                return Line(kind: .info, text: "Модель ответила: контекст \(k(input)) токенов\(input > 0 ? ", из кэша \(Int(100 * Double(cached) / Double(max(input, 1))))%" : "")")
            case "content_block_start":
                let b = ev["content_block"] as? [String: Any] ?? [:]
                switch b["type"] as? String {
                case "thinking", "redacted_thinking": return Line(kind: .think, text: "Думает…")
                case "text": return Line(kind: .text, text: "Пишет ответ")
                case "tool_use", "server_tool_use":
                    let name = b["name"] as? String ?? "?"
                    if let id = b["id"] as? String { state.tools[id] = name }
                    return Line(kind: .tool, text: "Вызывает \(short(name))")
                default: return nil
                }
            case "message_delta":
                guard let r = (ev["delta"] as? [String: Any])?["stop_reason"] as? String, r != "tool_use", r != "end_turn" else { return nil }
                return Line(kind: r == "max_tokens" || r == "refusal" ? .error : .info, text: "Модель остановилась: \(r)")
            default: return nil
            }
        case ("user", _):
            let content = (o["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for b in content where b["type"] as? String == "tool_result" {
                let name = (b["tool_use_id"] as? String).flatMap { state.tools[$0] }.map(short) ?? "инструмента"
                if b["is_error"] as? Bool == true {
                    let msg = (b["content"] as? String) ?? ((b["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ") ?? "")
                    return Line(kind: .error, text: "\(name): ошибка — \(msg.prefix(200))")
                }
                return Line(kind: .tool, text: "Результат \(name) получен")
            }
            return nil
        case ("rate_limit_event", _):
            let info = o["rate_limit_info"] as? [String: Any] ?? [:]
            guard let status = info["status"] as? String, status != "allowed" else { return nil }
            let reset = (info["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
            return Line(kind: .error, text: "Лимит подписки: \(status)\(reset.map { ", сброс в \($0)" } ?? "")")
        case ("control_request", _):
            let req = o["request"] as? [String: Any] ?? [:]
            return Line(kind: .wait, text: "Спрашивает разрешение: \(short(req["tool_name"] as? String ?? "?"))")
        case ("result", _):
            let secs = Double(o["duration_ms"] as? Int ?? 0) / 1000
            let u = o["usage"] as? [String: Any] ?? [:]
            let out = u["output_tokens"] as? Int ?? 0
            if o["is_error"] as? Bool == true || (sub != nil && sub != "success") {
                return Line(kind: .error, text: "Ход завершился с ошибкой (\(sub ?? "error")) за \(String(format: "%.0f", secs)) с: \((o["result"] as? String ?? "").prefix(200))")
            }
            return Line(kind: .done, text: "Ход завершён за \(String(format: secs < 10 ? "%.1f" : "%.0f", secs)) с, ответ \(k(out)) токенов")
        default:
            return nil
        }
    }

    static func short(_ tool: String) -> String {
        tool.hasPrefix("mcp__") ? tool.components(separatedBy: "__").dropFirst().joined(separator: ": ") : tool
    }

    static func k(_ n: Int) -> String { n >= 1000 ? String(format: "%.1f тыс.", Double(n) / 1000).replacingOccurrences(of: ".0 ", with: " ") : "\(n)" }
}
