import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

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

@MainActor @Test(.enabled(if: live)) func liveChatThroughSubscription() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Ярослав", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .haiku, effort: .low)

    // имя из знакомства попадает в системный промпт
    app.chat.send("Как меня зовут? Ответь одним словом.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let first = try #require(app.chat.messages.last)
    #expect(first.error == nil, "\(first.error ?? "")")
    #expect(first.text.contains("Ярослав"))
    #expect(app.conversations.count == 1)

    // «Стоп» посреди ответа: остаётся начало ответа с пометкой, процесс жив
    app.chat.send("Напиши длинный рассказ на 30 абзацев.")
    while app.chat.streaming == nil { try await Task.sleep(for: .milliseconds(50)) }
    try await Task.sleep(for: .seconds(1))
    let stoppedAt = Date()
    app.chat.stop()
    while app.chat.busy { try await Task.sleep(for: .milliseconds(20)) }
    #expect(Date().timeIntervalSince(stoppedAt) < 0.5)
    let stopped = try #require(app.chat.messages.last)
    #expect(stopped.stopped)
    #expect(!stopped.text.isEmpty)

    // следующий ход в том же разговоре помнит контекст
    app.chat.send("Как меня зовут? Одним словом.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    #expect(app.chat.messages.last?.text.contains("Ярослав") == true)
    #expect(try app.store.messages(in: app.chat.conversation!.id).count == 6)
}
