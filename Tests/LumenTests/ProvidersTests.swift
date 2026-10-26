import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage

// Контрактные тесты на записанном выводе настоящего `claude` 2.1.278 (спайк 1, docs/spikes.md)

@Test func decodesRecordedTwoTurnChat() throws {
    let url = try #require(Bundle.module.url(forResource: "chat-two-turns", withExtension: "jsonl", subdirectory: "Fixtures"))
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let events = lines.compactMap { ClaudeEvent.decode(Data($0.utf8)) }

    let starts = events.filter { if case .started = $0 { true } else { false } }
    #expect(starts.count == 2)
    if case .started(_, _, let tools) = starts[0] { #expect(tools.isEmpty) }

    let text = events.compactMap { if case .textDelta(let t) = $0 { t } else { nil } }.joined()
    #expect(text.contains("Привет"))

    let results = events.compactMap { if case .finished(let r) = $0 { r } else { nil } }
    #expect(results.count == 2)
    #expect(results.filter { !$0.ok }.isEmpty)
    #expect(results[0].text == "Привет!")
    #expect(results[0].inputTokens > 0)

    let limits = events.compactMap { if case .rateLimit(let r) = $0 { r } else { nil } }
    #expect(limits.first?.window == "five_hour")
    #expect(limits.first?.resetsAt != nil)

    // служебное (status, thinking_tokens, post_turn_summary) не доходит до интерфейса
    #expect(!events.contains { if case .unknown = $0 { true } else { false } })
}

@Test func unknownEventsDoNotBreakDecoding() {
    #expect(ClaudeEvent.decode(Data(#"{"type":"something_new","x":1}"#.utf8)) == .unknown("something_new"))
    #expect(ClaudeEvent.decode(Data("не json".utf8)) == nil)
}

@Test func chatArgumentsMatchSpike() {
    let c = ClaudeSession.Config(model: "claude-sonnet-5-5", sessionID: "abc")
    let a = c.arguments
    #expect(a.contains("--tools"))
    #expect(a[a.firstIndex(of: "--tools")! + 1] == "")
    #expect(a[a.firstIndex(of: "--setting-sources")! + 1] == "")
    #expect(a.contains("--session-id"))
    #expect(!a.contains("--resume"))
    #expect(!a.contains("--bare"))

    var paid = ClaudeSession.Config(model: "claude-sonnet-5-5", sessionID: "abc")
    paid.payWithAPIKey("sk-ant-test")
    #expect(paid.arguments.contains("--bare"))
    #expect(paid.extraEnv["ANTHROPIC_API_KEY"] == "sk-ant-test")

    // агент: свои настройки (остров видит сессию), все инструменты, продолжение сессии
    let agent = ClaudeSession.Config(model: "claude-sonnet-5-5", tools: nil, userSettings: true, sessionID: "abc", resume: true)
    #expect(!agent.arguments.contains("--setting-sources"))
    #expect(!agent.arguments.contains("--tools"))
    #expect(agent.arguments.contains("--resume"))
}

@Test func versionParsingAndOrder() throws {
    let v = try #require(Version(parsing: "2.1.278 (Claude Code)\n"))
    #expect(v == Version(2, 1, 278))
    #expect(v >= ClaudeCLI.minimumVersion)
    #expect(v < Version(2, 1, 280))
    #expect(Version(2, 2, 0) > v)
}

@Test func parsesUsageOutput() throws {
    let text = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 44% used · resets Oct 16 at 12:50am (Europe/Moscow)
    Current week (all models): 7% used · resets Oct 22 at 5pm (Europe/Moscow)
    Current week (Fable): 0% used · resets Oct 22 at 5pm (Europe/Moscow)
    """
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23))!
    let w = UsageWindow.parse(text, now: now)
    #expect(w.count == 3)
    #expect(w[0].kind == .session && w[0].percent == 44)
    #expect(w[1].kind == .week && w[1].percent == 7)
    #expect(w[2].kind == .weekModel("Fable"))
    let reset = try #require(w[0].resetsAt)
    #expect(cal.dateComponents([.month, .day, .hour, .minute], from: reset) == DateComponents(month: 10, day: 16, hour: 0, minute: 50))
    let week = try #require(w[1].resetsAt)
    #expect(cal.component(.hour, from: week) == 17)
}

@Test func apiKeyShape() {
    #expect(AnthropicAPI.looksValid("sk-ant-api03-" + String(repeating: "x", count: 40)))
    #expect(!AnthropicAPI.looksValid("sk-proj-123"))
}

/// Схемы инструментов для API: у каждого object — явное additionalProperties: false, иначе Anthropic отклоняет ход (Рома, 26.10)
@Test func toolSchemasAreStrictForObject() {
    let schema: [String: Any] = ["type": "object",
                                 "properties": ["q": ["type": "string"],
                                                "where": ["type": "object", "properties": ["x": ["type": "number"]]]]]
    guard let s = AnthropicAPI.strict(schema) as? [String: Any],
          let props = s["properties"] as? [String: Any], let w = props["where"] as? [String: Any] else {
        Issue.record("схема не сохранилась"); return
    }
    #expect(s["additionalProperties"] as? Bool == false)
    #expect(w["additionalProperties"] as? Bool == false)
    // явно указанное не трогаем
    let open = AnthropicAPI.strict(["type": "object", "additionalProperties": true]) as? [String: Any]
    #expect(open?["additionalProperties"] as? Bool == true)
    // как в Lumen: схема без additionalProperties у самого object
    let bare = AnthropicAPI.strict(["type": "object", "properties": [String: Any]()]) as? [String: Any]
    #expect(bare?["additionalProperties"] as? Bool == false)
}

@Test func storeKeepsSettingsAndUpsertsFacts() throws {
    let store = try Store()
    #expect(store.preferences == Preferences())
    try store.set("profile", Profile(name: "Рома", address: .ty))
    #expect(store.profile.name == "Рома")

    try store.save(MemoryFact(kind: .you, text: "Зовут Рома", source: "Знакомство", key: "onboarding.name", pinned: true))
    try store.save(MemoryFact(kind: .you, text: "Зовут Роман", source: "Знакомство", key: "onboarding.name", pinned: true))
    let facts = try store.memories()
    #expect(facts.count == 1)
    #expect(facts[0].text == "Зовут Роман")
}
