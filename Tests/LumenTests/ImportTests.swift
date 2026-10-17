import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// MARK: абзацы и шаги, как в Claude Code

@Test func answerLayoutPutsStepsBetweenParagraphs() {
    let text = "Смотрю код.\n\nНашёл причину.\n\nГотово."
    let steps = [AgentStep(kind: .read, text: "Читает A.swift", at: 11),
                 AgentStep(kind: .run, text: "Запускает: ls", at: 11),
                 AgentStep(kind: .edit, text: "Правит A.swift", at: 28)]
    let pieces = AnswerPiece.layout(text: text, steps: steps)
    #expect(pieces == [.text("Смотрю код."), .steps(Array(steps[0...1])), .text("Нашёл причину."), .steps([steps[2]]), .text("Готово.")])
}

@Test func answerLayoutKeepsOldAnswersAndStepsAtEnd() {
    // старые ответы без места — все шаги над текстом, как было
    let old = [AgentStep(kind: .run, text: "Запускает: swift test")]
    #expect(AnswerPiece.layout(text: "Тесты зелёные.", steps: old) == [.steps(old), .text("Тесты зелёные.")])
    // шаг после всего текста (ход ещё идёт) — в конце; место чуть дальше конца — тоже в конце
    let tail = [AgentStep(kind: .read, text: "Читает B", at: 40)]
    #expect(AnswerPiece.layout(text: "Начинаю.", steps: tail) == [.text("Начинаю."), .steps(tail)])
    // место сдвинулось на пару символов (текст обрезали) — шаг всё равно на границе абзаца, предложение целое
    let shifted = [AgentStep(kind: .read, text: "Читает C", at: 9)]
    #expect(AnswerPiece.layout(text: "Один два.\n\nТри.", steps: shifted) == [.text("Один два."), .steps(shifted), .text("Три.")])
}

// MARK: импорт из Claude Code

private func line(_ o: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: o), as: UTF8.self)
}

/// Маленький разговор в формате ~/.claude/projects/<папка>/<сессия>.jsonl
private func writeSession(dir: URL, id: String, cwd: String) throws -> URL {
    let folder = dir.appendingPathComponent("-proj", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let ts = "2026-10-17T10:00:00.000Z"
    let lines = [
        line(["type": "file-history-snapshot", "snapshot": [:]]),
        line(["type": "user", "cwd": cwd, "sessionId": id, "timestamp": ts, "isMeta": true,
              "message": ["role": "user", "content": "<local-command-caveat>служебное</local-command-caveat>"]]),
        line(["type": "user", "cwd": cwd, "sessionId": id, "timestamp": ts,
              "message": ["role": "user", "content": "Почини кнопку в Shelf<system-reminder>скрыто</system-reminder>"]]),
        line(["type": "assistant", "uuid": "a1", "timestamp": ts,
              "message": ["role": "assistant", "model": "claude-opus-5-5", "content": [["type": "thinking", "thinking": "хм"]]]]),
        line(["type": "assistant", "uuid": "a2", "timestamp": ts,
              "message": ["role": "assistant", "model": "claude-opus-5-5", "content": [["type": "text", "text": "Смотрю код."]]]]),
        line(["type": "assistant", "uuid": "a3", "timestamp": ts,
              "message": ["role": "assistant", "content": [["type": "tool_use", "name": "Read", "input": ["file_path": "/x/Shelf.swift"]]]]]),
        line(["type": "user", "timestamp": ts,
              "message": ["role": "user", "content": [["type": "tool_result", "content": "..."]]]]),
        line(["type": "assistant", "uuid": "a4", "timestamp": ts,
              "message": ["role": "assistant", "content": [["type": "tool_use", "name": "TodoWrite",
                                                             "input": ["todos": [["content": "Починить", "status": "completed"]]]]]]]),
        line(["type": "assistant", "uuid": "a5", "timestamp": ts,
              "message": ["role": "assistant", "content": [["type": "text", "text": "Готово, кнопка на месте."]]]]),
        line(["type": "user", "isSidechain": true, "timestamp": ts, "message": ["role": "user", "content": "помощник"]]),
        line(["type": "user", "timestamp": ts, "message": ["role": "user", "content": "<command-name>/compact</command-name>"]]),
        line(["type": "user", "timestamp": "2026-10-17T11:00:00.000Z", "message": ["role": "user", "content": "Спасибо"]]),
        line(["type": "custom-title", "customTitle": "Кнопка Shelf", "sessionId": id]),
    ]
    let file = folder.appendingPathComponent("\(id).jsonl")
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    return file
}

@Test func claudeHistoryListsAndParsesSession() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try writeSession(dir: dir, id: "s1", cwd: "/Users/test/prog/shelf")
    _ = try writeSession(dir: dir, id: "tmp", cwd: "/private/tmp/spike")

    let list = ClaudeHistory.sessions(root: dir)
    #expect(list.map(\.id) == ["s1"]) // временные папки — служебное
    let s = try #require(list.first)
    #expect(s.title == "Кнопка Shelf")
    #expect(s.firstPrompt == "Почини кнопку в Shelf")
    #expect(s.cwd == "/Users/test/prog/shelf")
    #expect(ClaudeHistory.sessions(root: dir, skip: ["s1"]).isEmpty) // уже импортирован

    let t = try ClaudeHistory.transcript(s, conversationID: "c")
    #expect(t.messages.map(\.role) == [.user, .assistant, .user])
    #expect(t.messages[0].text == "Почини кнопку в Shelf")
    let a = t.messages[1]
    #expect(a.text == "Смотрю код.\n\nГотово, кнопка на месте.")
    #expect(a.steps.map(\.text) == ["Читает Shelf.swift", "Обновляет план"])
    #expect(a.cliAnchor == "a5")
    #expect(AnswerPiece.layout(text: a.text, steps: a.steps)
        == [.text("Смотрю код."), .steps(a.steps), .text("Готово, кнопка на месте.")])
    #expect(t.plan == [PlanItem(text: "Починить", state: .done)])
    #expect(t.model == .opus)
    #expect(t.messages[2].text == "Спасибо")
}

@Test func importedConversationIsFoundByRecall() throws {
    let store = try Store()
    var c = Conversation(title: "Кнопка Shelf", kind: .agent, folder: "/tmp", backend: .subscription, model: .opus, effort: .high,
                         cliSessionID: "s1")
    c.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
    try store.importConversation(c, messages: [
        ChatMessage(conversationID: c.id, role: .user, text: "Почини кнопку в Shelf"),
        ChatMessage(conversationID: c.id, role: .assistant, text: "Кнопка падала из-за индекса в ShelfStorage"),
    ])
    #expect(try store.messages(in: c.id).count == 2)
    #expect(try store.conversations().first?.updatedAt == c.updatedAt) // время как было, не «сейчас»

    let tools = MemoryTools(store: store, conversationID: "другой", conversationTitle: "Новый")
    let out = try tools.call("recall", ["query": "почему падала кнопка"])
    #expect(out.contains("Из прошлых разговоров"))
    #expect(out.contains("Кнопка Shelf"))
    // в самом этом разговоре его же не подсовываем
    let own = MemoryTools(store: store, conversationID: c.id, conversationTitle: "Кнопка Shelf")
    #expect(try own.call("recall", ["query": "кнопка"]).contains("ничего не нашлось"))
}

@Test func claudeAppTitlesProjectsAndHiddenSessions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-desktop-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let projects = dir.appendingPathComponent("projects")
    // три разговора из приложения: переименованный в проекте, архивный и удалённый (в приложении его уже нет)
    for id in ["renamed", "archived", "gone"] { _ = try writeSession(dir: projects, id: id, cwd: "/Users/test/Prog") }
    for f in try FileManager.default.contentsOfDirectory(at: projects.appendingPathComponent("-proj"), includingPropertiesForKeys: nil) {
        let text = try String(contentsOf: f, encoding: .utf8).replacingOccurrences(of: "\"cwd\"", with: "\"entrypoint\":\"claude-desktop\",\"cwd\"")
        try text.write(to: f, atomically: true, encoding: .utf8)
    }
    let app = dir.appendingPathComponent("Claude")
    let org = app.appendingPathComponent("claude-code-sessions/acc/org")
    try FileManager.default.createDirectory(at: org, withIntermediateDirectories: true)
    func json(_ o: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: o).write(to: url) }
    try json(["sessionId": "local_1", "cliSessionId": "renamed", "title": "Изучение", "isArchived": false], org.appendingPathComponent("local_1.json"))
    try json(["sessionId": "local_2", "cliSessionId": "archived", "title": "Старое", "isArchived": true], org.appendingPathComponent("local_2.json"))
    try "1792233563839".write(to: org.appendingPathComponent("deleted_3"), atomically: true, encoding: .utf8)
    try json(["preferences": ["epitaxyPrefs": [
        "dframe-code-sections": ["acc": ["org": ["sections": [
            ["id": "pinned", "kind": "pinned", "name": "", "order": 0],
            ["id": "g-en", "kind": "manual", "name": "Изучение английского", "order": 2],
            ["id": "g-empty", "kind": "manual", "name": "Hermes", "order": 1],
        ]]]],
        "dframe-group-scopes": ["acc/org": ["groups": [["id": "g-en", "name": "Изучение английского"]],
                                            "assignments": ["code:local_1": "g-en"]]],
    ]]], app.appendingPathComponent("claude_desktop_config.json"))

    let desktop = try #require(ClaudeHistory.Desktop.load(root: app))
    #expect(desktop.groups.map(\.name) == ["Hermes", "Изучение английского"]) // порядок боковой панели, пустые тоже
    let list = ClaudeHistory.sessions(root: projects, desktop: desktop)
    #expect(list.map(\.id) == ["renamed"])            // архивный и удалённый скрыты
    #expect(list.first?.title == "Изучение")          // название из приложения, а не из файла
    #expect(list.first?.group?.name == "Изучение английского")
    // без данных приложения — как раньше: всё по файлам
    #expect(ClaudeHistory.sessions(root: projects).count == 3)
}

@Test func pastedContentWrapperIsRemoved() {
    #expect(ClaudeHistory.clean("<pasted_content id=\"9601\">длинный текст</pasted_content>\nи вопрос") == "длинный текст\nи вопрос")
}

@Test func claudeLogExplainsWhatClaudeIsDoing() {
    let st = ClaudeLog.State()
    func s(_ o: [String: Any]) -> ClaudeLog.Line? { ClaudeLog.summarize(try! JSONSerialization.data(withJSONObject: o), state: st) }
    #expect(s(["type": "system", "subtype": "init", "model": "claude-opus-5-5", "tools": ["Read", "Bash"], "claude_code_version": "2.1.301"])?.text
        .contains("готов: claude-opus-5-5, инструментов 2") == true)
    #expect(s(["type": "system", "subtype": "api_retry", "attempt": 2, "max_retries": 10, "retry_delay_ms": 4000, "error_status": 529, "error": "overloaded"])?.kind == .error)
    #expect(s(["type": "stream_event", "event": ["type": "content_block_start", "content_block": ["type": "thinking"]]])?.text == "Думает…")
    #expect(s(["type": "stream_event", "event": ["type": "content_block_start", "content_block": ["type": "tool_use", "id": "t1", "name": "mcp__lumen__browser_click"]]])?.text == "Вызывает lumen: browser_click")
    #expect(s(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "t1", "is_error": true, "content": "нет элемента"]]]])?.text
        == "lumen: browser_click: ошибка — нет элемента")
    #expect(s(["type": "stream_event", "event": ["type": "content_block_delta", "delta": ["type": "text_delta", "text": "x"]]]) == nil) // дельты — не в журнал
    #expect(s(["type": "result", "subtype": "success", "duration_ms": 12400, "usage": ["output_tokens": 1500]])?.text == "Ход завершён за 12 с, ответ 1.5 тыс. токенов")
}

@Test func importedConversationCatchesUpWithClaudeCode() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-sync-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let f = try writeSession(dir: dir, id: "s1", cwd: "/Users/test/prog")
    // после переноса: ход Lumen (sdk-cli) и потом — разговор в приложении Claude
    let more = [
        line(["type": "user", "entrypoint": "sdk-cli", "timestamp": "2026-10-17T12:00:00.000Z", "message": ["role": "user", "content": "из Lumen"]]),
        line(["type": "assistant", "uuid": "l1", "entrypoint": "sdk-cli", "timestamp": "2026-10-17T12:00:01.000Z", "message": ["role": "assistant", "content": [["type": "text", "text": "ответ в Lumen"]]]]),
        line(["type": "user", "entrypoint": "claude-desktop", "timestamp": "2026-10-17T12:05:00.000Z", "message": ["role": "user", "content": "из Claude"]]),
        line(["type": "assistant", "uuid": "d1", "entrypoint": "claude-desktop", "timestamp": "2026-10-17T12:05:01.000Z", "message": ["role": "assistant", "content": [["type": "text", "text": "ответ в Claude"]]]]),
    ]
    let h = try FileHandle(forWritingTo: f)
    h.seekToEndOfFile()
    h.write(Data(("\n" + more.joined(separator: "\n")).utf8))
    try h.close()
    let s = try #require(ClaudeHistory.sessions(root: dir).first)
    let t = try ClaudeHistory.transcript(s, conversationID: "c", after: "a5", skipLumen: true)
    // то, что уже есть в Lumen (до a5) и ходы самого Lumen — не повторяются
    #expect(t.messages.map(\.text).filter { !$0.isEmpty } == ["Спасибо", "из Claude", "ответ в Claude"], "\(t.messages.map(\.text))")
    #expect(try ClaudeHistory.transcript(s, conversationID: "c", after: "нет такой", skipLumen: true).messages.isEmpty)
    // приложение Claude продолжило разговор в новой сессии
    let d = ClaudeHistory.Desktop(entries: ["s2": .init(title: "x", archived: false, groupID: nil, priors: ["s1"])])
    #expect(d.successor(of: "s1") == "s2")
}

@Test func claudeCodeStateComesFromRecordsNotFileTime() {
    let now = Date()
    let ts = ISO8601DateFormatter().string(from: now)
    func next(_ s: ClaudeHistory.Live, _ o: [String: Any]) -> ClaudeHistory.Live { ClaudeHistory.live(after: s, o) }
    var s = next(.idle, ["type": "user", "timestamp": ts, "message": ["content": "сделай"]])
    #expect(s == .working(ISO8601DateFormatter().date(from: ts)!, step: "Думает…"))
    let tool = next(s, ["type": "assistant", "timestamp": ts, "message": ["content": [["type": "tool_use", "name": "Bash", "input": ["description": "Showing tokens page"]]]]])
    #expect(tool == .working(ISO8601DateFormatter().date(from: ts)!, step: "Запускает: Showing tokens page"))
    s = next(s, ["type": "custom-title", "customTitle": "x"])          // служебное — не меняет
    #expect(s.active(now: now) != .idle)
    s = next(s, ["type": "system", "subtype": "api_error", "timestamp": ts])
    if case .retrying = s {} else { Issue.record("ожидали retrying, а \(s)") }
    s = next(s, ["type": "assistant", "isApiErrorMessage": true, "timestamp": ts, "message": ["content": [["type": "text", "text": "API Error"]]]])
    #expect(s == .idle)
    s = next(.working(now), ["type": "assistant", "timestamp": ts, "message": ["stop_reason": "end_turn", "content": [["type": "text", "text": "готово"]]]])
    #expect(s == .idle)
    // «идёт», но без записей больше 2 минут — уже не идёт
    #expect(ClaudeHistory.Live.working(now.addingTimeInterval(-300)).active(now: now) == .idle)
}

@Test func apiErrorFromClaudeIsShownAsErrorNotText() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-apierr-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let f = try writeSession(dir: dir, id: "s1", cwd: "/Users/test/prog")
    let h = try FileHandle(forWritingTo: f)
    h.seekToEndOfFile()
    h.write(Data(("\n" + line(["type": "assistant", "isApiErrorMessage": true, "timestamp": "2026-10-17T12:57:27.819Z",
                               "message": ["role": "assistant", "content": [["type": "text", "text": "API Error: Can't reach the API server"]]]])).utf8))
    try h.close()
    let s = try #require(ClaudeHistory.sessions(root: dir).first)
    let t = try ClaudeHistory.transcript(s, conversationID: "c")
    let last = try #require(t.messages.last)
    #expect(last.error == "API Error: Can't reach the API server")
    #expect(!last.text.contains("API Error"))
    #expect(t.live == .idle)
}

@Test func markdownFilesArePreviewedAsFormattedText() {
    let html = MarkdownHTML.render("""
        # План
        Абзац с **жирным**, *курсивом*, `кодом` и [ссылкой](https://x.ru).

        - раз
        - два

        1. первое
        2. второе

        > цитата

        ```swift
        let a = 1 < 2
        ```

        | Имя | Цена |
        |---|---|
        | A | 1 |
        """)
    #expect(html.contains("<h1>План</h1>"))
    #expect(html.contains("<strong>жирным</strong>") && html.contains("<em>курсивом</em>") && html.contains("<code>кодом</code>"))
    #expect(html.contains("<a href=\"https://x.ru\">ссылкой</a>"))
    #expect(html.contains("<ul><li>раз</li><li>два</li></ul>") && html.contains("<ol><li>первое</li><li>второе</li></ol>"))
    #expect(html.contains("<blockquote>"))
    #expect(html.contains("<pre><code>let a = 1 &lt; 2</code></pre>"))
    #expect(html.contains("<th>Имя</th>") && html.contains("<td>A</td>"))
    // код — моноширинным, без разметки
    #expect(MarkdownHTML.page(name: "App.swift", text: "if a < b {}").contains("<pre><code>if a &lt; b {}</code></pre>"))
}

@Test func artifactsCollectEverythingLumenGaveAsAttachment() throws {
    let store = try Store()
    let c = Conversation(title: "Паспорт", kind: .agent, folder: "/tmp", backend: .subscription, model: .opus, effort: .high)
    try store.save(c)
    try store.save(ChatMessage(conversationID: c.id, role: .user, text: "сделай план"))
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "Готово")
    m.attachments = [LumenCore.Attachment(name: "plan.md", kind: .text, mime: "text/plain", path: "/tmp/plan.md", size: 10)]
    try store.save(m)
    try store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "без вложений"))
    let list = try store.artifacts()
    #expect(list.count == 1)
    #expect(list.first?.title == "Паспорт")
    #expect(list.first?.message.attachments.first?.name == "plan.md")
    #expect(BrowserTools.names.contains("make_file")) // у всех ботов и Lumen
}


@Test func claudeAppPlanServiceTurnsAndNoResponseAreHandled() throws {
    // план приложения Claude: список, «следующий», «сделаны N, начат M»
    var p = ClaudeHistory.desktopPlan(["items": [["content": "Прочитать", "status": "in_progress"], ["content": "Плитки", "status": "pending"],
                                                 ["content": "Паспорт", "status": "pending"]]], [])
    #expect(p.map(\.state) == [.doing, .todo, .todo])
    p = ClaudeHistory.desktopPlan(["advance": true], p)
    #expect(p.map(\.state) == [.done, .doing, .todo])
    p = ClaudeHistory.desktopPlan(["done": [2], "start": 3], p)
    #expect(p.map(\.state) == [.done, .done, .doing])

    // автоматический ход (уведомление) и ответ «No response requested.» — не показываются
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-svc-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let f = try writeSession(dir: dir, id: "s1", cwd: "/Users/test/prog")
    let more = [
        line(["type": "user", "origin": ["kind": "task-notification"], "timestamp": "2026-10-17T13:00:00.000Z",
              "message": ["role": "user", "content": "<task-notification><status>stopped</status></task-notification>"]]),
        line(["type": "assistant", "uuid": "x1", "timestamp": "2026-10-17T13:00:01.000Z",
              "message": ["role": "assistant", "content": [["type": "text", "text": "No response requested."]]]]),
        line(["type": "assistant", "uuid": "x2", "timestamp": "2026-10-17T13:00:02.000Z",
              "message": ["role": "assistant", "content": [["type": "tool_use", "name": "mcp__ccd_turn__update_plan",
                                                             "input": ["items": [["content": "Шаг", "status": "in_progress"]]]]]]]),
    ]
    let h = try FileHandle(forWritingTo: f)
    h.seekToEndOfFile()
    h.write(Data(("\n" + more.joined(separator: "\n")).utf8))
    try h.close()
    let s = try #require(ClaudeHistory.sessions(root: dir).first)
    let t = try ClaudeHistory.transcript(s, conversationID: "c")
    #expect(!t.messages.contains { $0.text.contains("No response requested") || $0.text.contains("task-notification") }, "\(t.messages.map(\.text))")
    #expect(t.plan.map(\.text) == ["Шаг"])
}

/// 17.10 Lumen падал при сворачивании блока правой панели: внутри app.update читались app.prefs
@MainActor @Test func readingPrefsInsideUpdateDoesNotCrash() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-upd-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.update { pr in
        if app.prefs.panelCollapsed.contains("log") { pr.panelCollapsed.removeAll { $0 == "log" } } else { pr.panelCollapsed.append("log") }
    }
    #expect(app.prefs.panelCollapsed.contains("log"))
}

/// 17.10: план не очищался между ходами — пункты дублировались
@Test func newTurnStartsNewPlanWithContinuingIDs() {
    var p: [PlanItem] = []
    for t in ["Найти папку", "Прочитать файлы"] { p = PlanItem.apply(.add(t), to: p, freshTurn: p.isEmpty) }
    p = PlanItem.apply(.update(id: "1", status: "completed", text: nil), to: p)
    #expect(p.map(\.text) == ["Найти папку", "Прочитать файлы"])
    // новый ход: агент снова добавляет пункты — это новый план, а не хвост к старому
    p = PlanItem.apply(.add("Найти папку"), to: p, freshTurn: true)
    p = PlanItem.apply(.add("Пересказать"), to: p, freshTurn: false)
    #expect(p.map(\.text) == ["Найти папку", "Пересказать"])
    #expect(p.map(\.id) == ["3", "4"]) // номера сквозные, как у claude: TaskUpdate попадёт в нужный пункт
    p = PlanItem.apply(.update(id: "3", status: "completed", text: nil), to: p, freshTurn: false)
    #expect(p.first?.state == .done)
    // в новом ходе агент продолжает старый план (сначала отмечает пункт) — не сбрасываем
    let kept = PlanItem.apply(.update(id: "4", status: "in_progress", text: nil), to: p, freshTurn: true)
    #expect(kept.count == 2 && kept[1].state == .doing)
}
