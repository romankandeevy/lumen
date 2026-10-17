import Foundation
import LumenCore

/// Ход чата по ключу: POST /v1/messages со стримом SSE (§3 техплана).
/// Thinking не передаём — у этих моделей он адаптивный по умолчанию; глубину задаёт effort.
public struct AnthropicChatRequest: Sendable {
    public var model: ChatModel
    public var effort: Effort
    public var system: String
    /// История: user — текст, assistant — блоки ответа как вернул API (или текст, если их нет)
    public var messages: [[String: any Sendable]]
    public var maxTokens = 64_000
    /// Клиентские инструменты (память): name, description, input_schema
    public var tools: [JSONBox] = []

    public init(model: ChatModel, effort: Effort, system: String, messages: [[String: any Sendable]]) {
        self.model = model
        self.effort = effort
        self.system = system
        self.messages = messages
    }

    /// Сообщения в формате API из истории разговора. Ответы с ошибкой не отправляем.
    public static func history(_ msgs: [ChatMessage]) -> [[String: any Sendable]] {
        let plain: [[String: any Sendable]] = msgs.compactMap { m -> [String: any Sendable]? in
            switch m.role {
            case .user:
                if !m.attachments.isEmpty {
                    return ["role": "user", "content": JSONBox(Attachment.userContent(text: m.text, attachments: m.attachments, agent: false))]
                }
                return ["role": "user", "content": m.text]
            case .assistant:
                if let raw = m.apiContent, let blocks = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any], !blocks.isEmpty {
                    return ["role": "assistant", "content": JSONBox(blocks)]
                }
                guard m.error == nil, !m.text.isEmpty else { return nil }
                // ответ бота в этом чате — подписан, чтобы Lumen не принял его за свой
                return ["role": "assistant", "content": m.botID.map { "[Это ответил бот @\($0), не ты]\n" + m.text } ?? m.text]
            }
        }
        return plain.flatMap { msg -> [[String: any Sendable]] in
            // ход с инструментами хранится целиком: assistant(tool_use) → user(tool_result) → … → assistant
            if let box = msg["content"] as? JSONBox, let blocks = box.value as? [Any], blocks.count == 1,
               let wrapped = blocks.first as? [String: Any], let turn = wrapped["lumen_turn"] as? [[String: Any]] {
                return turn.map { ["role": $0["role"] as? String ?? "assistant", "content": JSONBox($0["content"] ?? [])] }
            }
            return [msg]
        }
    }

    func body() throws -> Data {
        var b: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "stream": true,
            // системный блок стабилен на весь разговор — кэшируется; история кэшируется автоматически
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "cache_control": ["type": "ephemeral"],
            "output_config": ["effort": effort.rawValue],
            "messages": messages.map { $0.mapValues { ($0 as? JSONBox)?.value ?? $0 } },
        ]
        if model.hasServerFallback { b["fallbacks"] = "default" }
        if !tools.isEmpty { b["tools"] = tools.map(\.value) }
        return try JSONSerialization.data(withJSONObject: b)
    }
}

/// Обёртка, чтобы разобранный JSON можно было хранить в Sendable-словаре
public struct JSONBox: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}

public enum APIChatEvent: Sendable {
    case textDelta(String)
    /// Конец хода: почему остановился, блоки ответа (JSON) для истории, расход
    case finished(stopReason: String, content: String, usage: Usage)

    public struct Usage: Sendable, Equatable {
        public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0

        public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
        }
    }
}

public enum APIChatError: Error, LocalizedError, Equatable {
    case noKey
    case noNetwork
    case rejectedKey
    case rateLimited
    case overloaded
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .noKey: "Нет ключа Anthropic API. Добавь его в Настройках → Модели и оплата."
        case .noNetwork: "Нет связи с Anthropic. Проверь интернет и отправь ещё раз."
        case .rejectedKey: "Ключ API не подошёл. Проверь его в Настройках → Модели и оплата."
        case .rateLimited: "Слишком много запросов подряд. Подожди минуту и отправь ещё раз."
        case .overloaded: "Anthropic сейчас перегружен. Отправь ещё раз чуть позже."
        case .server(let m): m
        }
    }
}

extension AnthropicAPI {
    /// Стрим ответа. Отмена задачи-потребителя обрывает соединение — это «Стоп».
    /// Пока ответ не пошёл, сбои сети, перегрузка, лимит и ошибки сервера 5xx повторяются сами (до 3 раз,
    /// пауза растёт; у 429 — сколько просит сервер). Связь, молчащая дольше 2 минут, считается оборванной.
    public func chat(_ request: AnthropicChatRequest, onRetry: (@Sendable (Int, String) -> Void)? = nil) -> AsyncThrowingStream<APIChatEvent, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                var attempt = 0
                while true {
                    var yielded = false
                    do {
                        var req = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
                        req.httpMethod = "POST"
                        req.setValue(key, forHTTPHeaderField: "x-api-key")
                        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        req.setValue("application/json", forHTTPHeaderField: "content-type")
                        if request.model.hasServerFallback {
                            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                        }
                        req.httpBody = try request.body()
                        // таймаут между пакетами: сервер шлёт ping раз в ~10 с, 2 минуты тишины — обрыв
                        req.timeoutInterval = 120

                        let (bytes, resp) = try await session.bytes(for: req)
                        let http = resp as? HTTPURLResponse
                        let code = http?.statusCode ?? 0
                        guard code == 200 else {
                            var data = Data()
                            for try await b in bytes { data.append(b) }
                            let err = Self.error(status: code, body: data)
                            if attempt < Self.maxRetries, Self.retryable(status: code) {
                                attempt += 1
                                let wait = Self.delay(attempt, retryAfter: http?.value(forHTTPHeaderField: "retry-after"))
                                onRetry?(attempt, err.localizedDescription)
                                try await Task.sleep(for: .seconds(wait))
                                continue
                            }
                            throw err
                        }
                        var parser = SSEMessageBuilder()
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:") else { continue }
                            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            for ev in try parser.feed(Data(json.utf8)) {
                                yielded = true
                                cont.yield(ev)
                            }
                        }
                        cont.finish()
                        return
                    } catch let e as URLError where e.code == .cancelled {
                        cont.finish()
                        return
                    } catch is CancellationError {
                        cont.finish()
                        return
                    } catch let e as URLError {
                        let network = [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                                       .timedOut, .dnsLookupFailed, .secureConnectionFailed].contains(e.code)
                        // ответ ещё не пошёл — повторить; пошёл — оборвать честно, без дублей
                        if network && !yielded && attempt < Self.maxRetries {
                            attempt += 1
                            onRetry?(attempt, APIChatError.noNetwork.localizedDescription)
                            try? await Task.sleep(for: .seconds(Self.delay(attempt, retryAfter: nil)))
                            if Task.isCancelled { cont.finish(); return }
                            continue
                        }
                        cont.finish(throwing: network ? APIChatError.noNetwork : e)
                        return
                    } catch {
                        cont.finish(throwing: error)
                        return
                    }
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    public static let maxRetries = 3

    /// Что стоит повторить: лимит, перегрузка, ошибки сервера
    static func retryable(status: Int) -> Bool { status == 429 || status == 529 || status == 408 || (500...599).contains(status) }

    /// Пауза перед повтором: 2, 6, 15 с; если сервер сказал, сколько ждать, — столько (не больше минуты)
    static func delay(_ attempt: Int, retryAfter: String?) -> Double {
        if let r = retryAfter.flatMap(Double.init), r > 0 { return min(60, r) }
        return [2, 6, 15][min(attempt, 3) - 1]
    }

    static func error(status: Int, body: Data) -> APIChatError {
        switch status {
        case 401, 403: return .rejectedKey
        case 429: return .rateLimited
        case 529: return .overloaded
        default: return .server(message(from: body).map { "Anthropic: \($0)" } ?? "Anthropic ответил \(status)")
        }
    }
}

/// Собирает ответ из SSE-событий: дельты текста — наружу сразу, блоки целиком — для истории
struct SSEMessageBuilder {
    private var blocks: [Int: [String: Any]] = [:]
    private var stopReason = ""
    private var usage = APIChatEvent.Usage()

    mutating func feed(_ data: Data) throws -> [APIChatEvent] {
        guard let ev = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = ev["type"] as? String else { return [] }
        switch type {
        case "message_start":
            if let u = (ev["message"] as? [String: Any])?["usage"] as? [String: Any] { read(u) }
        case "content_block_start":
            if let i = ev["index"] as? Int, let b = ev["content_block"] as? [String: Any] { blocks[i] = b }
        case "content_block_stop":
            // вход инструмента пришёл кусками JSON — собрать
            if let i = ev["index"] as? Int, var b = blocks[i], let partial = b["_partial"] as? String {
                b["input"] = (try? JSONSerialization.jsonObject(with: Data(partial.utf8))) ?? [:]
                b.removeValue(forKey: "_partial")
                blocks[i] = b
            }
        case "content_block_delta":
            guard let i = ev["index"] as? Int, let d = ev["delta"] as? [String: Any] else { return [] }
            switch d["type"] as? String {
            case "text_delta":
                let t = d["text"] as? String ?? ""
                append(t, to: "text", in: i)
                return [.textDelta(t)]
            case "thinking_delta":
                append(d["thinking"] as? String ?? "", to: "thinking", in: i)
            case "signature_delta":
                blocks[i]?["signature"] = d["signature"] as? String
            case "input_json_delta":
                append(d["partial_json"] as? String ?? "", to: "_partial", in: i)
            default: break
            }
        case "message_delta":
            if let r = (ev["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = r }
            if let u = ev["usage"] as? [String: Any] { read(u) }
        case "message_stop":
            return [.finished(stopReason: stopReason, content: contentJSON(), usage: usage)]
        case "error":
            let msg = (ev["error"] as? [String: Any])?["message"] as? String ?? "ошибка"
            let kind = (ev["error"] as? [String: Any])?["type"] as? String
            throw kind == "overloaded_error" ? APIChatError.overloaded : APIChatError.server("Anthropic: \(msg)")
        default: break
        }
        return []
    }

    private mutating func append(_ t: String, to field: String, in i: Int) {
        guard var b = blocks[i] else { return }
        b[field] = (b[field] as? String ?? "") + t
        blocks[i] = b
    }

    private mutating func read(_ u: [String: Any]) {
        if let v = u["input_tokens"] as? Int { usage.input = v }
        if let v = u["output_tokens"] as? Int { usage.output = v }
        if let v = u["cache_read_input_tokens"] as? Int { usage.cacheRead = v }
        if let v = u["cache_creation_input_tokens"] as? Int { usage.cacheWrite = v }
    }

    /// Блоки ответа по порядку — как их вернул API (thinking с подписью, text, fallback)
    func contentJSON() -> String {
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        guard let d = try? JSONSerialization.data(withJSONObject: ordered) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }
}
