import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

/// Подменённая сеть: отдаёт записанные SSE-ответы по очереди и запоминает запросы
final class StubAPI: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String] = []
    /// Вместо ответа: код HTTP (401…) или ошибка сети
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var networkError: URLError.Code?
    nonisolated(unsafe) static var requests: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.anthropic.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            Self.requests.append((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        }
        if let code = Self.networkError {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let body = Self.status != 200 ? #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
            : (Self.responses.isEmpty ? "" : Self.responses.removeFirst())
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func sse(_ events: [String]) -> String { events.map { "event: x\ndata: \($0)\n\n" }.joined() }
}

/// Тесты с подменённой сетью: очереди ответов общие, поэтому строго по одному
@Suite(.serialized) @MainActor struct APIStubTests {

@Test func apiChatRunsMemoryToolLoop() async throws {
    setenv("LUMEN_KEYCHAIN", "com.roman.lumen.tests", 1)
    defer { Keychain(service: "com.roman.lumen.tests").delete(Keychain.anthropicKey) }
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-api-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    try app.keychain.save("sk-ant-test-" + String(repeating: "x", count: 30), for: Keychain.anthropicKey)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubAPI.self]
    app.urlSession = URLSession(configuration: config)
    app.finishOnboarding(name: "Рома", address: .ty, backend: .api, theme: .lumen)

    StubAPI.requests = []
    StubAPI.responses = [
        StubAPI.sse([
            #"{"type":"message_start","message":{"usage":{"input_tokens":50}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tu1","name":"remember","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"text\":\"Встаёт в 9 утра\",\"kind\":\"pref\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}"#,
            #"{"type":"message_stop"}"#,
        ]),
        StubAPI.sse([
            #"{"type":"message_start","message":{"usage":{"input_tokens":80}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Запомнил, "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"буду учитывать."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":6}}"#,
            #"{"type":"message_stop"}"#,
        ]),
    ]
    app.chat.send("Запомни: я встаю в 9 утра")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }

    let reply = try #require(app.chat.messages.last)
    #expect(reply.error == nil, "\(reply.error ?? "")")
    #expect(reply.text == "Запомнил, буду учитывать.")
    #expect(reply.remembered.count == 1)
    #expect(app.memories.contains { $0.text == "Встаёт в 9 утра" && $0.kind == .pref })
    #expect(reply.steps.isEmpty) // в чате вызовы памяти не показываются шагами

    // два запроса: второй несёт tool_result
    #expect(StubAPI.requests.count == 2)
    let first = StubAPI.requests[0]
    #expect(first["model"] as? String == ChatModel.sonnet.rawValue)
    #expect((first["tools"] as? [[String: Any]])?.map { $0["name"] as? String } == ["remember", "recall"])
    #expect((first["system"] as? [[String: Any]])?.first?["text"] as? String != nil)
    let msgs2 = try #require(StubAPI.requests[1]["messages"] as? [[String: Any]])
    let last = try #require(msgs2.last?["content"] as? [[String: Any]])
    #expect(last.first?["type"] as? String == "tool_result")
    #expect((last.first?["content"] as? String)?.hasPrefix("Запомнил") == true)

    // следующий ход отправляет историю целиком, с вызовом инструмента
    StubAPI.responses = [StubAPI.sse([
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"В 9."}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
        #"{"type":"message_stop"}"#,
    ])]
    app.chat.send("Во сколько я встаю?")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
    let roles = (StubAPI.requests[2]["messages"] as? [[String: Any]])?.map { $0["role"] as? String }
    #expect(roles == ["user", "assistant", "user", "assistant", "user"])
    #expect(app.chat.messages.last?.text == "В 9.")
}

@Test func monthlyLimitStopsAPI() async throws {
    setenv("LUMEN_KEYCHAIN", "com.roman.lumen.tests", 1)
    defer { Keychain(service: "com.roman.lumen.tests").delete(Keychain.anthropicKey) }
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-limit-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    try app.keychain.save("sk-ant-test-" + String(repeating: "x", count: 30), for: Keychain.anthropicKey)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubAPI.self]
    app.urlSession = URLSession(configuration: config)
    app.finishOnboarding(name: "Рома", address: .ty, backend: .api, theme: .lumen)
    app.update { $0.monthlyLimit = 5 }
    try app.store.logSpend(conversationID: nil, backend: .api, model: "claude-opus-5-5", input: 0, output: 0, cacheRead: 0, cacheWrite: 0, usd: 5.01)
    StubAPI.requests = []
    app.chat.send("Привет")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
    // запрос не ушёл (сеть общая с соседним тестом — ищем именно своё сообщение)
    let sent = StubAPI.requests.contains { r in
        ((r["messages"] as? [[String: Any]]) ?? []).contains { ($0["content"] as? String) == "Привет" }
    }
    #expect(!sent)
    #expect(app.chat.messages.last?.error?.contains("лимит") == true)
    // подписка лимитом не ограничена — это другой счёт
    #expect(app.limitReached != nil)
}

@Test func clearErrorsWithoutKeyOrNetwork() async throws {
    setenv("LUMEN_KEYCHAIN", "com.roman.lumen.tests", 1)
    defer {
        Keychain(service: "com.roman.lumen.tests").delete(Keychain.anthropicKey)
        StubAPI.status = 200
        StubAPI.networkError = nil
    }
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-err-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubAPI.self]
    app.urlSession = URLSession(configuration: config)
    app.finishOnboarding(name: "Рома", address: .ty, backend: .api, theme: .lumen)

    func ask() async throws -> String {
        app.newChat()
        app.chat.send("Привет")
        while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
        return app.chat.messages.last?.error ?? ""
    }

    #expect(try await ask().contains("Нет ключа"))
    try app.keychain.save("sk-ant-test-" + String(repeating: "x", count: 30), for: Keychain.anthropicKey)
    StubAPI.status = 401
    #expect(try await ask().contains("не подошёл"))
    StubAPI.status = 200
    StubAPI.networkError = .notConnectedToInternet
    #expect(try await ask().contains("Нет связи"))
}
}
