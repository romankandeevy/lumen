import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI
@testable import LumenStorage

// Живые проверки на настоящем `claude` по подписке. Тратят немного лимита, поэтому только по запросу:
//   LUMEN_LIVE=1 swift test --filter Live

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

/// lumen-mcp собран рядом с тестами (зависимость тестовой цели)
func pointToMCP() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for rel in [".build/out/Products/Debug/lumen-mcp", ".build/debug/lumen-mcp"] {
        let bin = root.appendingPathComponent(rel)
        if FileManager.default.isExecutableFile(atPath: bin.path) { setenv("LUMEN_MCP", bin.path, 1); return }
    }
}

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

@MainActor @Test(.enabled(if: live)) func liveAgentEditsCommitsAndReverts() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumen-agent-\(UUID().uuidString)")
    let repo = root.appendingPathComponent("proj")
    try fm.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    func sh(_ args: String...) async throws { _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), args, cwd: repo) }
    try "hello\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try await sh("git", "init", "-q")
    try await sh("git", "add", ".")
    try await sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")

    let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.tab = .agent
    app.agentFolder = repo
    app.newAgentTask()
    app.chat.send("Допиши в конец файла a.txt строку world и создай файл b.txt со словом new. Больше ничего не делай.")
    // модель агента — Haiku, чтобы тест был быстрым
    app.chat.set(model: .haiku, effort: .low)
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }

    let reply = try #require(app.chat.messages.last)
    #expect(reply.error == nil, "\(reply.error ?? "")")
    #expect(!reply.steps.isEmpty)
    let changes = try #require(reply.changes)
    #expect(Set(changes.files.map(\.path)) == ["a.txt", "b.txt"])
    #expect(app.chat.conversation?.kind == .agent)
    #expect(app.recentFolders.first?.resolvingSymlinksInPath() == repo.resolvingSymlinksInPath())

    let diff = await app.chat.diff(reply)
    #expect(diff.contains("+world"))

    await app.chat.revert(reply)
    #expect(app.chat.messages.last?.changes?.state == .reverted)
    #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "hello\n")
    #expect(!fm.fileExists(atPath: repo.appendingPathComponent("b.txt").path))

    // второй ход в той же сессии: правка и коммит кнопкой
    app.chat.send("Создай файл c.txt со словом ok. Больше ничего не делай.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
    let second = try #require(app.chat.messages.last)
    #expect(second.changes?.files.map(\.path) == ["c.txt"])
    await app.chat.commit(second)
    #expect(app.chat.messages.last?.changes?.state == .committed)
    let log = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "log", "--oneline"], cwd: repo)
    #expect(log.stdout.split(separator: "\n").count == 2)
}

@MainActor @Test(.enabled(if: live)) func liveMemoryAcrossChats() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-mem-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    #expect(app.mcpBinary.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true)
    await app.refreshClaude()
    app.finishOnboarding(name: "Ярослав", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .haiku, effort: .low)

    app.chat.send("Запомни, пожалуйста: я встаю в 7:40 утра.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let first = try #require(app.chat.messages.last)
    #expect(first.error == nil, "\(first.error ?? "")")
    #expect(!first.remembered.isEmpty, "плашка «Запомнил»")
    #expect(app.memories.contains { $0.text.contains("7:40") })
    let fact = try #require(app.memories.first { $0.text.contains("7:40") })
    #expect(fact.conversationID == app.chat.conversation?.id)

    // новый чат: факт не закреплён, значит модель должна вспомнить его через recall
    app.newChat()
    app.chat.send("Во сколько я обычно встаю? Ответь только временем.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let second = try #require(app.chat.messages.last)
    #expect(second.text.contains("7:40"), "ответ: \(second.text)")
    #expect(second.recalled.contains(fact.id!), "«Опирался на»")
    #expect(app.conversations.count == 2)
}

@MainActor @Test(.enabled(if: live)) func liveContextAndCompact() async throws {
    pointToMCP()
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ctx-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .haiku, effort: .low)
    app.chat.send("Запомни кодовое слово СОВА, без инструментов, просто в разговоре. Ответь «ок».")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(100)) }
    let ctx = try #require(app.chat.lastContext)
    #expect(ctx.used > 0 && ctx.window >= 200_000)
    #expect((try app.store.spent(backend: .subscription, since: app.monthStart)) > 0)

    app.chat.compact()
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(100)) }
    #expect(app.chat.messages.last?.note != nil, "\(app.chat.messages.last?.error ?? "")")

    app.chat.send("Какое кодовое слово? Одним словом.")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(100)) }
    #expect(app.chat.messages.last?.text.uppercased().contains("СОВА") == true)
}
