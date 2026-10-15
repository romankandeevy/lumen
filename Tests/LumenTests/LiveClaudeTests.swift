import Foundation
import Testing
@testable import LumenProviders

// Живые проверки на настоящем `claude` по подписке. Тратят немного лимита, поэтому только по запросу:
//   LUMEN_LIVE=1 swift test --filter Live

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

@Test(.enabled(if: live)) func liveStopIsFastAndSessionContinues() async throws {
    let cli = try #require(ClaudeCLI.locate())
    let session = try ClaudeSession(cli: cli, config: .init(model: "claude-haiku-5-5",
                                                            systemPrompt: "Ты Lumen. Отвечай по-русски."))
    defer { session.close() }

    let turn = try session.send("Запомни кодовое слово ФИАЛКА. Потом напиши длинный рассказ на 30 абзацев.")
    var stoppedAt: Date?
    var firstText: Date?
    var stopDelay: TimeInterval?
    for await ev in turn {
        if case .textDelta = ev {
            firstText = firstText ?? Date()
            if stoppedAt == nil, let f = firstText, Date().timeIntervalSince(f) > 1 {
                stoppedAt = Date()
                session.interrupt()
            }
        }
        if case .finished = ev {
            stopDelay = stoppedAt.map { Date().timeIntervalSince($0) }
            break
        }
    }
    let delay = try #require(stopDelay)
    #expect(delay < 0.5, "«Стоп» должен срабатывать быстрее 0,5 с, было \(delay)")
    #expect(session.isRunning)

    let next = try await session.ask("Какое кодовое слово? Одним словом.")
    #expect(next.ok)
    #expect(next.text.uppercased().contains("ФИАЛКА"))
}
