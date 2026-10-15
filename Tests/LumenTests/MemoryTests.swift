import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage

@Test func russianStemming() {
    #expect(SearchQuery.stem("кнопки") == "кнопк")
    #expect(SearchQuery.stem("кнопку") == "кнопк")
    #expect(SearchQuery.stem("Shelf") == "shelf")
    #expect(SearchQuery.stem("дом") == "дом") // короткие не режем
    #expect(SearchQuery.fts("Что с кнопками?") == "\"что\"* \"кнопк\"*")
    #expect(SearchQuery.fts("!!") == nil)
}

@Test func memorySearchFindsWordForms() throws {
    let store = try Store()
    try store.save(MemoryFact(kind: .decision, text: "Существующие кнопки остаются на местах", source: "Тест"))
    try store.save(MemoryFact(kind: .pref, text: "Встаёт в 9 утра", source: "Тест"))
    try store.save(MemoryFact(kind: .project, text: "Shelf падал при двойном щелчке", source: "Тест"))
    #expect(try store.searchMemories("кнопку").map(\.text) == ["Существующие кнопки остаются на местах"])
    #expect(try store.searchMemories("встает").first?.text == "Встаёт в 9 утра") // ё = е
    #expect(try store.searchMemories("shelf").count == 1)
    #expect(try store.searchMemories("самолёт").isEmpty)
}

@Test func conversationSearchGivesOneHitPerChat() throws {
    let store = try Store()
    let c = Conversation(title: "Почему падает Shelf?", backend: .subscription, model: .sonnet, effort: .medium)
    try store.save(c)
    try store.save(ChatMessage(conversationID: c.id, role: .user, text: "Shelf падает при двойном щелчке"))
    try store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Падение в ShelfStorage: проверил индекс"))
    let hits = try store.searchConversations("shelf")
    #expect(hits.count == 1)
    #expect(hits[0].title == "Почему падает Shelf?")
    #expect(hits[0].snippet.contains("«"))
}

@Test func memoryToolsRememberRecallAndDedupe() throws {
    let store = try Store()
    let c = Conversation(title: "Утро", backend: .api, model: .haiku, effort: .low)
    try store.save(c)
    let tools = MemoryTools(store: store, conversationID: c.id, conversationTitle: c.title)
    let start = Date().addingTimeInterval(-1)
    #expect(try tools.call("remember", ["text": "Встаёт в 9 утра", "kind": "pref"]).hasPrefix("Запомнил"))
    #expect(try tools.call("remember", ["text": "встаёт в 9 утра!", "kind": "pref"]).hasPrefix("Это уже есть"))
    #expect(try store.memories().count == 1)
    let fact = try #require(try store.memories().first)
    #expect(fact.source == "Утро" && fact.conversationID == c.id && fact.kind == .pref)
    #expect(try tools.call("recall", ["query": "во сколько встаёт"]).contains("Встаёт в 9 утра"))
    #expect(try store.memoryUses(conversationID: c.id, since: start, action: "remember") == [fact.id!])
    #expect(try store.memoryUses(conversationID: c.id, since: start, action: "recall") == [fact.id!])
    #expect(MemoryTools.definitions.map(\.name) == ["remember", "recall"])
}

@Test func onboardingFactsKeepOneCopy() throws {
    let store = try Store()
    try store.save(MemoryFact(kind: .you, text: "Зовут Рома", source: "Знакомство", key: "onboarding.name", pinned: true))
    try store.save(MemoryFact(kind: .you, text: "Зовут Роман", source: "Знакомство", key: "onboarding.name", pinned: true))
    #expect(try store.memories().map(\.text) == ["Зовут Роман"])
}

@Test func toolTurnReplaysWholeChain() throws {
    let chain = #"[{"lumen_turn":[{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"remember","input":{"text":"x","kind":"you"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},{"role":"assistant","content":[{"type":"text","text":"Запомнил."}]}]}]"#
    let h = AnthropicChatRequest.history([
        ChatMessage(conversationID: "c", role: .user, text: "Запомни x"),
        ChatMessage(conversationID: "c", role: .assistant, text: "Запомнил.", apiContent: chain),
    ])
    #expect(h.count == 4)
    #expect(h.map { $0["role"] as? String } == ["user", "assistant", "user", "assistant"])
}

@Test func sseCollectsToolInput() throws {
    var b = SSEMessageBuilder()
    var out: (String, String)?
    for e in [
        #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"recall","input":{}}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"утро\"}"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":3}}"#,
        #"{"type":"message_stop"}"#,
    ] {
        for ev in try b.feed(Data(e.utf8)) { if case .finished(let r, let c, _) = ev { out = (r, c) } }
    }
    let (reason, content) = try #require(out)
    #expect(reason == "tool_use")
    let blocks = try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [[String: Any]])
    #expect((blocks[0]["input"] as? [String: Any])?["query"] as? String == "утро")
    #expect(blocks[0]["_partial"] == nil)
}
