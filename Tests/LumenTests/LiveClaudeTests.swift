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

/// Живые проверки по одной: параллельные процессы claude мешают замерам и тратят лимит разом
@Suite(.serialized) struct LiveSuite {

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

/// Lumen в чате сам работает во встроенном браузере: открывает страницу, вписывает, нажимает (Рома, 17.10)
@MainActor @Test(.enabled(if: live)) func liveChatUsesBuiltInBrowser() async throws {
    // путь к сокету должен быть короче 104 знаков — короткая папка в /tmp
    let home = URL(fileURLWithPath: "/tmp/lb-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .sonnet, effort: .low)
    app.startBrowser()
    let page = home.appendingPathComponent("form.html")
    try """
        <!doctype html><meta charset="utf-8"><title>Заявка</title>
        <input id="n" placeholder="Имя"><button onclick="document.getElementById('o').textContent='Готово, ' + document.getElementById('n').value">Отправить</button>
        <p id="o"></p>
        """.write(to: page, atomically: true, encoding: .utf8)

    app.chat.send("Открой во встроенном браузере файл \(page.path), впиши в поле «Имя» слово Ромашка и нажми «Отправить». Потом перепиши, что появилось на странице.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let m = try #require(app.chat.messages.last)
    #expect(m.error == nil, "\(m.error ?? "")")
    #expect(m.text.contains("Готово, Ромашка"), "ответ: \(m.text)")
    #expect(m.steps.contains { $0.text.hasPrefix("Нажимает") }, "\(m.steps.map(\.text))")
    #expect(app.browser.url.hasSuffix("form.html"))
}

/// Очередь: написанное во время ответа уходит само; после «Стоп» ждёт; «Сейчас» — сразу (Рома, 17.10)
@MainActor @Test(.enabled(if: live)) func liveQueuedMessagesGoAfterAnswer() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-queue-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .haiku, effort: .low)

    app.chat.send("Посчитай от 1 до 15 словами, каждое с новой строки.")
    #expect(app.chat.busy)
    app.chat.send("А теперь скажи только слово ЛИМОН.")
    #expect(app.chat.openQueue.count == 1)
    while app.chat.busy || !app.chat.openQueue.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    let roles = app.chat.messages.map(\.role)
    #expect(roles == [.user, .assistant, .user, .assistant], "\(roles)")
    #expect(app.chat.messages.last?.text.uppercased().contains("ЛИМОН") == true, "\(app.chat.messages.last?.text ?? "")")

    // «Стоп» — очередь ждёт; «Сейчас» — уходит
    app.chat.send("Напиши длинный рассказ на 20 абзацев о море.")
    app.chat.send("Скажи только слово ГРУША.")
    try await Task.sleep(for: .seconds(2))
    app.chat.stop()
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    try await Task.sleep(for: .milliseconds(300))
    #expect(app.chat.openQueue.count == 1)
    app.chat.sendNow(app.chat.openQueue[0].id)
    #expect(app.chat.openQueue.isEmpty)
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    #expect(app.chat.messages.last?.text.uppercased().contains("ГРУША") == true, "\(app.chat.messages.last?.text ?? "")")
}

/// Lumen выдаёт файл вложением (make_file), ничего не записывая в проект (Рома, 17.10)
@MainActor @Test(.enabled(if: live)) func liveMakesFileAsAttachment() async throws {
    let home = URL(fileURLWithPath: "/tmp/lf-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .sonnet, effort: .low)
    app.startBrowser()
    app.chat.send("Сделай файл plan.md: заголовок «План» и три пункта списка про изучение английского. Выдай его файлом-вложением.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let m = try #require(app.chat.messages.last)
    #expect(m.error == nil, "\(m.error ?? "")")
    let f = try #require(m.attachments.first, "вложения нет: \(m.text)")
    #expect(f.name.hasSuffix(".md"))
    #expect((try? String(contentsOf: f.url, encoding: .utf8))?.contains("План") == true)
    #expect(f.path.hasPrefix(home.path)) // лежит в хранилище Lumen, не в проекте
}

/// «Характер» реально меняет ответы: правило «Всегда» и запрещённое слово (Рома, 17.10)
@MainActor @Test(.enabled(if: live)) func livePersonaChangesAnswers() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-soul-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.set(model: .haiku, effort: .low)
    var p = Persona()
    p.always = ["Начинать каждый ответ со слова «Йохо!»"]
    p.bannedWords = ["привет"]
    app.savePersona(p)
    app.chat.send("Поздоровайся со мной одной фразой.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let a = try #require(app.chat.messages.last?.text)
    #expect(a.hasPrefix("Йохо"), "ответ: \(a)")
    #expect(!a.lowercased().contains("привет"), "ответ: \(a)")

    // поменяли характер посреди разговора — следующий ответ уже по-новому
    p.always = ["Начинать каждый ответ со слова «Ахой!»"]
    app.savePersona(p)
    app.chat.send("А теперь попрощайся одной фразой.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
    let b = try #require(app.chat.messages.last?.text)
    #expect(b.hasPrefix("Ахой"), "ответ: \(b)")
}

/// Характер держится у агента, где он дописан к длинному промпту Claude Code: несколько разных сообщений подряд,
/// в том числе по-английски, — правило «Всегда», запрещённое слово, язык, длина, без ссылок на инструкции (Рома, 17.10)
@MainActor @Test(.enabled(if: live)) func livePersonaHoldsInAgent() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-soul-agent-\(UUID().uuidString)")
    let folder = home.appendingPathComponent("proj", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "# Проект\nКалькулятор чаевых.".write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: home) }
    pointToMCP()
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    var p = Persona()
    p.always = ["Начинать каждый ответ со слова «Йохо!»"]
    p.bannedWords = ["привет"]
    p.language = .ru
    p.length = .short
    app.savePersona(p)
    app.tab = .agent
    app.agentFolder = folder
    app.newAgentTask()
    app.chat.set(model: .sonnet, effort: .low)
    var answers: [String] = []
    for q in ["Hi! What is this project about? Answer briefly.",
              "Что лежит в README? Одной фразой.",
              "Как ты обычно отвечаешь людям?"] {
        app.chat.send(q)
        while app.chat.busy { try await Task.sleep(for: .milliseconds(100)) }
        let a = try #require(app.chat.messages.last?.text)
        answers.append(a)
        #expect(a.hasPrefix("Йохо"), "«\(q)» → \(a)")
        #expect(!a.lowercased().contains("привет"), "«\(q)» → \(a)")
        #expect(a.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil, "не по-русски: \(a)")
        #expect(a.count < 700, "длинно (\(a.count)): \(a)")
    }
    // не ссылается на инструкции в обычном ответе
    for a in answers.prefix(2) {
        #expect(!["инструкц", "мне велено", "по моим правилам", "lumen-style"].contains { a.lowercased().contains($0) }, "\(a)")
    }
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

@MainActor @Test(.enabled(if: live)) func liveAgentPlanAndNextStep() async throws {
    pointToMCP()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumen-next-\(UUID().uuidString)")
    let repo = root.appendingPathComponent("proj")
    try fm.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try "a\n".write(to: repo.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.tab = .agent
    app.agentFolder = repo
    app.newAgentTask()
    app.chat.send("Сначала составь план из трёх пунктов инструментом TodoWrite, потом выполни: допиши в notes.txt строки b и c, отмечая пункты плана. Сборки нет.")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(200)) }
    let reply = try #require(app.chat.messages.last)
    #expect(reply.error == nil, "\(reply.error ?? "")")
    let planCount = app.chat.conversation?.plan.count ?? 0
    #expect(planCount > 0, "план сбоку; шаги: \(reply.steps.map(\.text))")
    #expect(reply.next != nil, "карточка «что дальше»: \(reply.text.suffix(300))")
    #expect(!reply.text.contains("<lumen-next>"))
}

@MainActor @Test(.enabled(if: live)) func liveAnswerTypesSmoothly() async throws {
    pointToMCP()
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-type-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.chat.send("Расскажи в 5 предложениях, как устроена Луна.")
    var lengths: [Int] = []
    while app.chat.running != nil {
        if let n = app.chat.streaming?.text.count, n != lengths.last { lengths.append(n) }
        try await Task.sleep(for: .milliseconds(15))
    }
    let final = app.chat.messages.last?.text.count ?? 0
    // claude присылает текст пачками; на экране он растёт многими мелкими шагами
    #expect(lengths.count >= 20, "шагов печати: \(lengths.count), всего \(final) знаков")
    #expect((lengths.last ?? 0) == final)
}

@MainActor @Test(.enabled(if: live)) func liveSuggestionsComeFromMemory() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-sug-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.addMemory("Делает Mac-приложение Lumen — личного агента", kind: .project, pinned: true)
    app.addMemory("По вечерам бегает в парке", kind: .you, pinned: false)
    try app.store.save(Conversation(title: "Почему падает Shelf при двойном щелчке", backend: .subscription, model: .sonnet, effort: .medium))
    app.reloadConversations()
    await app.refreshSuggestions()
    let items = app.suggestions
    #expect(items != Suggestions.fallback, "подсказки не придуманы")
    #expect(items.count == 3)
    #expect(items.allSatisfy { $0.count <= 60 })
    print("ПОДСКАЗКИ:", items)
    // сохранились и читаются при следующем запуске
    let again = try AppModel(paths: AppPaths(root: home))
    #expect(again.suggestions == items)
}
}

/// Агент на копии настоящего проекта (LUMEN_REAL_PROJECT=путь к репозиторию): правка, коммит кнопкой, push — отказ.
/// Оригинал не трогается: клонируется во временную папку, у клона нет удалённого репозитория.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_REAL_PROJECT"] != nil))
func liveAgentOnRealProjectCopy() async throws {
    pointToMCP()
    let source = ProcessInfo.processInfo.environment["LUMEN_REAL_PROJECT"]!
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumen-real-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let repo = root.appendingPathComponent("proj")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "clone", "-q", source, repo.path])
    _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "remote", "remove", "origin"], cwd: repo)
    let before = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "rev-list", "--count", "HEAD"], cwd: repo)

    let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.tab = .agent
    app.agentFolder = repo
    app.chat.set(model: .sonnet, effort: .low)
    app.newAgentTask()
    app.chat.send("Посмотри проект и добавь в конец README.md раздел «## Проверено Lumen» с одной строкой: что это за приложение, одним предложением. Больше ничего не меняй.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(300)) }
    let reply = try #require(app.chat.messages.last)
    #expect(reply.error == nil, "\(reply.error ?? "")")
    let changes = try #require(reply.changes)
    #expect(changes.files.map(\.path) == ["README.md"])
    let readme = try String(contentsOf: repo.appendingPathComponent("README.md"), encoding: .utf8)
    #expect(readme.contains("Проверено Lumen"))
    await app.chat.commit(reply)
    #expect(app.chat.messages.last?.changes?.state == .committed)
    let after = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "rev-list", "--count", "HEAD"], cwd: repo)
    #expect(Int(after.stdout.trimmingCharacters(in: .whitespacesAndNewlines))! == Int(before.stdout.trimmingCharacters(in: .whitespacesAndNewlines))! + 1)

    // push без OK невозможен: агент даже не может его запустить
    _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "remote", "add", "origin", root.appendingPathComponent("remote.git").path], cwd: repo)
    _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "init", "-q", "--bare", root.appendingPathComponent("remote.git").path])
    app.chat.send("Сделай git push origin HEAD прямо сейчас командой в терминале.")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(300)) }
    let refs = try await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["git", "--git-dir", root.appendingPathComponent("remote.git").path, "rev-list", "--all", "--count"])
    #expect(refs.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "push прошёл, а не должен был")
}

/// Название разговора придумывает модель после первого ответа, а не первая фраза
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"))
func liveConversationGetsModelTitle() async throws {
    pointToMCP()
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-title-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    app.newChat()
    app.chat.set(model: .haiku, effort: .low)
    app.chat.send("привет, подскажи, как быстро сварить гречку на ужин")
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
    // название приходит фоном
    for _ in 0..<60 where app.conversations.first?.title.hasPrefix("привет") == true { try await Task.sleep(for: .milliseconds(250)) }
    let title = try #require(app.conversations.first?.title)
    #expect(!title.hasPrefix("привет"), "осталось «\(title)»")
    #expect(title.localizedCaseInsensitiveContains("греч"), "название «\(title)»")
}
