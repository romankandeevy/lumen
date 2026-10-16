import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// Боты: права переводятся во флаги claude, @id находит бота, бот хранится и удаляется вместе с разговором,
// lumen-mcp не даёт писать в память боту без права. Живые проверки (LUMEN_LIVE=1) — на настоящем claude.

private func tester() -> Bot {
    Bot(id: "tester", name: "Тестировщик", icon: "flask-conical", hue: 160, role: "Проверяет сборки — и только",
        capabilities: [.read, .run], commands: ["ls", "swift test"], model: .haiku, effort: .low)
}

@Test func botWithoutWriteCannotEditOrPushAndRunsOnlyListedCommands() {
    let p = BotPermissions(tester())
    #expect(p.tools.contains("Read") && p.tools.contains("Bash"))
    #expect(!p.tools.contains("Edit") && !p.tools.contains("Write") && !p.tools.contains("WebFetch"))
    // терминал — только из белого списка, а не весь Bash
    #expect(!p.allowed.contains("Bash"))
    #expect(p.allowed.contains("Bash(ls:*)") && p.allowed.contains("Bash(swift test:*)"))
    #expect(p.disallowed.contains("Bash(git push:*)"))
    #expect(p.disallowed.contains("Bash(git commit:*)"))
    // память и вызов других ботов — у всех ботов всегда (Рома, 16.10)
    #expect(!p.memoryReadOnly)
    #expect(p.allowed.contains("mcp__lumen__remember") && p.allowed.contains("mcp__lumen__delegate"))
    #expect(tester().can.isSuperset(of: BotCapability.always))
    #expect(!BotPermissions.blocked(tester()).contains("Писать в память") && !BotPermissions.blocked(tester()).contains("Звать других ботов"))
    #expect(!BotCapability.choosable.contains(.memory) && !BotCapability.choosable.contains(.bots))
    #expect(BotPermissions.blocked(tester()).contains("Править файлы"))
    #expect(BotPermissions.blocked(tester()).last == "Push на GitHub")
}

@Test func coderBotGetsFullTerminalButNeverPush() {
    let coder = Bot(id: "coder", name: "Кодер", capabilities: [.read, .write, .run, .git, .memory])
    let p = BotPermissions(coder)
    #expect(p.tools.contains("Edit") && p.allowed.contains("Bash"))
    #expect(p.disallowed.contains("Bash(git push:*)") && !p.disallowed.contains("Bash(git commit:*)"))
    #expect(!p.memoryReadOnly && p.allowed.contains("mcp__lumen__remember"))
    // чистый собеседник: ни одного инструмента
    #expect(BotPermissions(Bot(id: "talk", name: "Собеседник", capabilities: [])).tools.isEmpty)
}

@Test func botIDRules() {
    #expect(Bot.isValidID("tester") && Bot.isValidID("qa-2"))
    #expect(!Bot.isValidID("t") && !Bot.isValidID("Tester") && !Bot.isValidID("тест") && !Bot.isValidID("lumen") && !Bot.isValidID("-x"))
}

@MainActor @Test func mentionFindsBotAndStoreKeepsIt() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-bots-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.saveBot(tester())
    #expect(app.bots.map(\.id) == ["tester"])

    let (b, task) = try #require(app.mention(in: "@tester проверь сборку Shelf"))
    #expect(b.id == "tester" && task == "проверь сборку Shelf")
    #expect(app.mention(in: "@nobody привет") == nil)
    #expect(app.mention(in: "@tester") == nil)          // без задачи — не вызов
    #expect(app.mention(in: "напиши @tester") == nil)   // только в начале

    // постоянный разговор — один, в списках чатов и агента его нет
    let c1 = app.botConversation(for: b)
    let c2 = app.botConversation(for: b)
    #expect(c1.id == c2.id && c1.kind == .bot && c1.botID == "tester")
    #expect(app.botFolder(b).path.contains("bots/tester"))

    // смена @id: разговор переходит к новому имени
    var renamed = b
    renamed.id = "qa"
    app.saveBot(renamed, replacing: "tester")
    #expect(app.bots.map(\.id) == ["qa"])
    #expect(app.conversations.first { $0.kind == .bot }?.botID == "qa")

    app.deleteBot(renamed)
    #expect(app.bots.isEmpty)
    #expect(!app.conversations.contains { $0.kind == .bot })

    // правила бота: роль и отрезанное
    let prompt = app.botPrompt(tester())
    #expect(prompt.contains("@tester") && prompt.contains("Отрезано в коде") && prompt.contains("Править файлы"))
}

/// lumen-mcp с LUMEN_MEMORY_READONLY=1: remember не виден и не выполняется (вторая линия защиты)
@Test func memoryServerRefusesRememberForReadOnlyBot() async throws {
    pointToMCP()
    guard let path = ProcessInfo.processInfo.environment["LUMEN_MCP"] else { Issue.record("lumen-mcp не собран"); return }
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-mcp-ro-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let db = home.appendingPathComponent("lumen.sqlite")
    _ = try Store(path: db)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.environment = ["LUMEN_DB": db.path, "LUMEN_CONVERSATION_ID": "c1", "LUMEN_MEMORY_READONLY": "1"]
    let input = Pipe(), output = Pipe()
    p.standardInput = input
    p.standardOutput = output
    try p.run()
    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"remember","arguments":{"text":"Любит чай","kind":"pref"}}}"#,
    ]
    try input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
    try input.fileHandleForWriting.close()
    p.waitUntilExit()
    let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let lines = out.split(separator: "\n").map(String.init)
    #expect(lines.count == 2)
    #expect(lines[0].contains("recall") && !lines[0].contains("\"remember\""))
    #expect(lines[1].contains("isError") && lines[1].contains("запрещено"))
    #expect(try Store(path: db).memories().isEmpty)
}

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

/// Живые проверки ботов по одной (тратят немного лимита подписки)
@Suite(.serialized) struct LiveBotSuite {

    /// Главное обещание ботов: без права правки файл не изменить ни инструментом, ни командой в терминале
    @MainActor @Test(.enabled(if: live)) func liveBotWithoutWriteCannotChangeFiles() async throws {
        pointToMCP()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lumen-livebot-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("proj")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "hello\n".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        var b = tester()
        b.folder = folder.path
        app.saveBot(b)
        app.openBot("tester")
        #expect(app.page == .bot("tester"))

        app.chat.send("Допиши в конец файла a.txt строку world. Если инструмент правки недоступен — сделай это командой echo world >> a.txt в терминале. Потом создай файл b.txt командой touch b.txt.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let reply = try #require(app.chat.messages.last)
        #expect(reply.botID == "tester")
        #expect(try String(contentsOf: folder.appendingPathComponent("a.txt"), encoding: .utf8) == "hello\n")
        #expect(!fm.fileExists(atPath: folder.appendingPathComponent("b.txt").path))

        // разрешённая команда работает
        app.chat.send("Выполни команду ls в своей папке и перечисли файлы.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let second = try #require(app.chat.messages.last)
        #expect(second.error == nil, "\(second.error ?? "")")
        #expect(second.text.contains("a.txt"))
        #expect(second.steps.contains { $0.kind == .run })
    }

    /// @id из обычного чата: ответ со знаком бота здесь, задача и ответ — в постоянном разговоре бота
    @MainActor @Test(.enabled(if: live)) func liveMentionDelegatesToBot() async throws {
        pointToMCP()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lumen-livemention-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("proj")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "x".write(to: folder.appendingPathComponent("отчёт.md"), atomically: true, encoding: .utf8)

        let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        var b = tester()
        b.folder = folder.path
        app.saveBot(b)

        app.newChat()
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("@tester какие файлы лежат в твоей папке? Ответь одним списком.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let reply = try #require(app.chat.messages.last)
        #expect(reply.error == nil, "\(reply.error ?? "")")
        #expect(reply.botID == "tester")
        #expect(reply.text.contains("отчёт.md"))
        #expect(app.chat.conversation?.kind == .chat)

        let botChat = app.botConversation(for: b)
        let inBot = try app.store.messages(in: botChat.id)
        #expect(inBot.count == 2)
        #expect(inBot.first?.text.contains("из другого разговора") == true)
        #expect(inBot.last?.botID == "tester")
    }
}
