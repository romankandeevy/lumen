import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

@Test func apiRequestBody() throws {
    let history = AnthropicChatRequest.history([
        ChatMessage(conversationID: "c", role: .user, text: "Привет"),
        ChatMessage(conversationID: "c", role: .assistant, text: "Привет!",
                    apiContent: #"[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"Привет!"}]"#),
        ChatMessage(conversationID: "c", role: .assistant, text: "", error: "нет сети"),
        ChatMessage(conversationID: "c", role: .user, text: "Как дела?"),
    ])
    #expect(history.count == 3) // ответ с ошибкой не отправляется
    let req = AnthropicChatRequest(model: .opus, effort: .high, system: "Ты Lumen.", messages: history)
    let body = try #require(JSONSerialization.jsonObject(with: req.body()) as? [String: Any])
    #expect(body["model"] as? String == "claude-opus-5-5")
    #expect(body["stream"] as? Bool == true)
    #expect(body["thinking"] == nil) // адаптивный по умолчанию
    #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "high")
    #expect(body["fallbacks"] as? String == "default")
    let msgs = try #require(body["messages"] as? [[String: Any]])
    // блоки ответа уходят как пришли — с подписью thinking
    let blocks = try #require(msgs[1]["content"] as? [[String: Any]])
    #expect(blocks[0]["signature"] as? String == "sig")

    let haiku = try #require(JSONSerialization.jsonObject(with: AnthropicChatRequest(model: .haiku, effort: .low, system: "", messages: []).body()) as? [String: Any])
    #expect(haiku["fallbacks"] == nil)
}

@Test func sseBuildsTextAndContent() throws {
    let events = [
        #"{"type":"message_start","message":{"usage":{"input_tokens":12,"cache_read_input_tokens":3}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"При"}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"вет"}}"#,
        #"{"type":"content_block_stop","index":1}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#,
        #"{"type":"message_stop"}"#,
    ]
    var b = SSEMessageBuilder()
    var text = ""
    var finished: (String, String, APIChatEvent.Usage)?
    for e in events {
        for ev in try b.feed(Data(e.utf8)) {
            switch ev {
            case .textDelta(let t): text += t
            case .finished(let r, let c, let u): finished = (r, c, u)
            }
        }
    }
    #expect(text == "Привет")
    let f = try #require(finished)
    #expect(f.0 == "end_turn")
    #expect(f.2 == APIChatEvent.Usage(input: 12, output: 5, cacheRead: 3, cacheWrite: 0))
    let blocks = try #require(JSONSerialization.jsonObject(with: Data(f.1.utf8)) as? [[String: Any]])
    #expect(blocks.count == 2)
    #expect(blocks[0]["signature"] as? String == "abc")
    #expect(blocks[1]["text"] as? String == "Привет")

    var e = SSEMessageBuilder()
    #expect(throws: APIChatError.overloaded) {
        _ = try e.feed(Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8))
    }
}

@Test func storeKeepsConversations() throws {
    let store = try Store()
    let c = Conversation(title: "Тест", backend: .subscription, model: .sonnet, effort: .medium, cliSessionID: "s1")
    try store.save(c)
    try store.save(ChatMessage(conversationID: c.id, role: .user, text: "Привет"))
    try store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Привет!", model: .sonnet))
    #expect(try store.messages(in: c.id).map(\.text) == ["Привет", "Привет!"])
    #expect(try store.conversations().first?.cliSessionID == "s1")
    try store.deleteConversation(c.id)
    #expect(try store.messages(in: c.id).isEmpty) // сообщения удаляются вместе с разговором
}

@Test func oldPreferencesStillDecode() throws {
    let old = #"{"onboarded":true,"backend":"api","theme":"mono","reducedMotion":false}"#
    let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
    #expect(p.onboarded && p.backend == .api && p.theme == .mono)
    #expect(p.model == .sonnet && p.effort == .medium)
}

@Test func pricesAndTokens() {
    // Sonnet 5.5: $2 вход, $10 выход, $0.20 чтение кэша, запись — 1,25 входа
    #expect(abs(ChatModel.sonnet.cost(input: 1_000_000, output: 100_000, cacheRead: 1_000_000, cacheWrite: 0) - 3.2) < 0.0001)
    #expect(abs(ChatModel.opus.cost(input: 0, output: 0, cacheRead: 0, cacheWrite: 1_000_000) - 5) < 0.0001)
    #expect(Tokens.short(47_400) == "47 тыс.")
    #expect(Tokens.short(1_000_000) == "1 млн")
    #expect(Tokens.short(512) == "512")
}

@Test func contextFromRecordedResult() throws {
    let url = try #require(Bundle.module.url(forResource: "chat-two-turns", withExtension: "jsonl", subdirectory: "Fixtures"))
    let results = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        .compactMap { ClaudeEvent.decode(Data($0.utf8)) }
        .compactMap { if case .finished(let r) = $0 { r } else { nil } }
    #expect(results[0].contextTokens == 600)
    #expect(results[0].contextWindow == 200_000)
    #expect(results[0].costUSD > 0)
}

