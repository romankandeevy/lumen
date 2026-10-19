import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI
@testable import LumenStorage

// Живые проверки самостоятельной работы на настоящем `claude` (тратят немного лимита):
//   LUMEN_LIVE=1 swift test --filter LiveAutonomy

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

@Suite(.serialized) struct LiveAutonomySuite {

/// Своё сжатие: агент пишет записку, свежая сессия claude помнит главное по ней
@MainActor @Test(.enabled(if: live)) func liveHandoffCompactKeepsWhatMatters() async throws {
    pointToMCP()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumen-handoff-\(UUID().uuidString)")
    let repo = root.appendingPathComponent("proj")
    try fm.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try "print('hello')\n".write(to: repo.appendingPathComponent("server.py"), atomically: true, encoding: .utf8)

    let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.agentModel = .haiku; $0.agentEffort = .low; $0.agentMode = .bypassPermissions }
    app.tab = .agent
    app.agentFolder = repo
    app.newAgentTask()
    app.chat.send("Запомни для работы, это важно: кодовое имя проекта — ГРАНИТ, сервер слушает порт 4317, а главный файл — server.py. Ничего не делай с файлами, просто ответь «принял».")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
    let c = try #require(app.chat.conversation)
    #expect(app.chat.messages.last?.error == nil, "\(app.chat.messages.last?.error ?? "")")
    let oldSession = c.cliSessionID

    let ok = await app.chat.handoffCompact(c)
    #expect(ok == true)
    let note = try #require(app.chat.pendingHandoff(c.id))
    print("записка (\(note.count) знаков):\n\(note.prefix(600))")
    #expect(note.contains("ГРАНИТ") && note.contains("4317"))
    #expect(app.chat.conversation?.cliSessionID != oldSession)
    #expect(app.chat.messages.last?.note?.contains("сжал разговор") == true)

    app.chat.send("Как кодовое имя проекта и какой порт у сервера? Ответь коротко, одной строкой.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
    let answer = try #require(app.chat.messages.last)
    print("ответ после сжатия: \(answer.text)")
    #expect(answer.error == nil, "\(answer.error ?? "")")
    #expect(answer.text.uppercased().contains("ГРАНИТ") && answer.text.contains("4317"))
    // записка ушла в свежую сессию и больше не нужна
    #expect(app.chat.pendingHandoff(c.id) == nil)
}

}
