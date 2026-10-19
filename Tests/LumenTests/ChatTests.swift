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


@Test func nextStepBlockIsSplitOut() {
    let text = """
    Починил падение.

    <lumen-next>{"recap": "Добавил проверку индекса. Сборку не запускал.", "ask": "Собрать и проверить?", "primary": {"label": "Собери", "reply": "Собери и проверь"}, "secondary": null}</lumen-next>
    """
    let (visible, next) = NextStep.split(text)
    #expect(visible == "Починил падение.")
    #expect(next?.recap == "Добавил проверку индекса. Сборку не запускал.")
    #expect(next?.primary?.reply == "Собери и проверь")
    #expect(next?.secondary == nil)
    // пока блок пишется — он уже спрятан
    #expect(NextStep.split("Готово. <lumen-next>{\"rec").text == "Готово.")
    #expect(NextStep.split("Без карточки").next == nil)
}

@Test func todoWriteBecomesPlan() {
    let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"Понять задачу","status":"completed","activeForm":"x"},{"content":"Сделать правки","status":"in_progress","activeForm":"x"},{"content":"Проверить","status":"pending","activeForm":"x"}]}}]}}"#
    let events = ClaudeEvent.decodeAll(Data(line.utf8))
    let change = events.compactMap { if case .plan(let p) = $0 { p } else { nil } }.first
    let plan = change.map { PlanItem.apply($0, to: []) }
    #expect(plan?.map(\.state) == [.done, .doing, .todo])
    #expect(plan?.first?.text == "Понять задачу")
    #expect(events.contains { if case .step(let s) = $0 { s.text == "Обновляет план" } else { false } })
}

/// 19.10: у claude номера задач сквозные на всю сессию (в этом ходе — 7, 8, 9), а план у нас с каждым ходом сбрасывается.
/// Своя нумерация с 1 отмечала «сделано» в третьем пункте вместо первого.
@Test func planUsesRealTaskNumbersFromClaude() {
    var plan: [PlanItem] = []
    var first = true
    let lines = [
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Прочитать"}},{"type":"tool_use","name":"TaskCreate","input":{"subject":"Проверить"}},{"type":"tool_use","name":"TaskCreate","input":{"subject":"Показать"}}]}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"Task #7 created successfully: Прочитать"}]}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b","content":[{"type":"text","text":"Task #8 created successfully: Проверить"}]}]}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c","content":"Task #9 created successfully: Показать"}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"7","status":"completed"}}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"8","status":"in_progress"}}]}}"#,
    ]
    for line in lines {
        for case .plan(let ch) in ClaudeEvent.decodeAll(Data(line.utf8)) {
            plan = PlanItem.apply(ch, to: plan, freshTurn: first, live: true)
            first = false
        }
    }
    #expect(plan.map(\.id) == ["7", "8", "9"])
    #expect(plan.map(\.state) == [.done, .doing, .todo])
    // номер из прошлого хода, которого в плане нет, ничего не отмечает
    #expect(PlanItem.apply(.update(id: "3", status: "completed", text: nil), to: plan).map(\.state) == [.done, .doing, .todo])
}

@Test func taskToolsBuildPlan() {
    var plan: [PlanItem] = []
    for line in [
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Прочитать","activeForm":"x"}},{"type":"tool_use","name":"TaskCreate","input":{"subject":"Поправить","activeForm":"x"}}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}"#,
    ] {
        for case .plan(let ch) in ClaudeEvent.decodeAll(Data(line.utf8)) { plan = PlanItem.apply(ch, to: plan) }
    }
    #expect(plan.map(\.text) == ["Прочитать", "Поправить"])
    #expect(plan.map(\.state) == [.done, .doing])
    #expect(PlanItem.apply(.update(id: "1", status: "deleted", text: nil), to: plan).count == 1)
}

@MainActor @Test func renameConversation() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ren-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let c = Conversation(title: "привет", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    app.reloadConversations()
    app.openChat(c)
    app.renameChat(c, "  План на неделю  ")
    #expect(app.conversations.first?.title == "План на неделю")
    #expect(app.chat.conversation?.title == "План на неделю")
    app.renameChat(c, "   ") // пустое не сохраняется
    #expect(try app.store.conversations().first?.title == "План на неделю")
}

@Test func suggestionsParse() {
    #expect(Suggestions.parse(#"```json\n["Доделаем Lumen?", "Что с Shelf?", "Куда сходить вечером"]\n```"#)
            == ["Доделаем Lumen?", "Что с Shelf?", "Куда сходить вечером"])
    #expect(Suggestions.parse("[\"«Одна»\", \"Две\", \"Три\", \"Четыре\"]") == ["Одна", "Две", "Три"])
    #expect(Suggestions.parse("не json") == nil)
    #expect(Suggestions.prompt(name: "Рома", address: .ty, facts: ["Делает Lumen"], recent: ["Почему падает Shelf?"]).contains("Почему падает Shelf?"))
}

@MainActor @Test func pinAndMenu() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-pin-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let a = Conversation(title: "Старый", backend: .subscription, model: .sonnet, effort: .medium, updatedAt: Date().addingTimeInterval(-86_400 * 3))
    let b = Conversation(title: "Новый", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(a)
    try app.store.save(b)
    app.reloadConversations()
    app.togglePin(a)
    #expect(app.conversations.first { $0.id == a.id }?.pinned == true)
    let fresh = try #require(app.conversations.first { $0.id == a.id })
    app.showChatMenu(fresh, at: .zero)
    #expect(app.menu?.items.map(\.title) == ["Открепить", "Переименовать", "Переместить в проект…", "Сделать навык из разговора", "Удалить"])
    #expect(app.menu?.items.map(\.key) == ["p", "r", "m", "s", "d"])
    app.menu?.items[1].action() // «Переименовать» включает поле в строке
    #expect(app.renamingID == a.id)
}

@MainActor @Test func projectsCarryInstructionsAndFiles() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-proj-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let pr = app.createProject()
    #expect(app.page == .project(pr.id))
    app.updateProject(pr) {
        $0.name = "Блог"
        $0.instructions = "Пиши как редактор блога."
    }
    let file = home.appendingPathComponent("стиль.md")
    try "Короткие абзацы.".write(to: file, atomically: true, encoding: .utf8)
    #expect(app.addFile(file, to: app.project(pr.id)!))

    // новый чат в проекте получает его инструкции и файлы
    app.newChat(in: app.project(pr.id)!)
    #expect(app.chat.newProjectID == pr.id)
    var c = Conversation(title: "Пост", backend: .subscription, model: .sonnet, effort: .medium)
    c.projectID = pr.id
    let prompt = app.systemPrompt(for: c)
    #expect(prompt.contains("проекте «Блог»"))
    #expect(prompt.contains("Пиши как редактор блога."))
    #expect(prompt.contains("<file name=\"стиль.md\">"))
    #expect(!app.systemPrompt(for: Conversation(title: "x", backend: .api, model: .sonnet, effort: .low)).contains("Блог"))

    // перенос и удаление проекта: разговор остаётся, просто без проекта
    let other = Conversation(title: "Черновик", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(other)
    app.reloadConversations()
    app.move(other, to: pr.id)
    #expect(app.conversations(in: pr.id).map(\.title) == ["Черновик"])
    app.deleteProject(app.project(pr.id)!)
    #expect(app.projects.isEmpty)
    #expect(app.conversations.first { $0.id == other.id }?.projectID == nil)
}


/// Вкладки помнят своё: новый пустой чат остаётся новым после похода в «Агента»
@MainActor @Test func tabsRememberWhatWasOpen() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-tabs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let old = Conversation(title: "Старый", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(old)
    let task = Conversation(title: "Задача", kind: .agent, folder: "/tmp", backend: .subscription, model: .sonnet, effort: .high)
    try app.store.save(task)
    app.reloadConversations()

    app.openChat(old)
    app.newChat()                      // ушёл в новый чат
    #expect(app.chat.conversation == nil)
    app.switchTab(.agent)              // первый раз — последняя задача
    #expect(app.chat.conversation?.id == task.id)
    app.switchTab(.chat)               // вернулся — снова новый чат, а не «Старый»
    #expect(app.chat.conversation == nil)
    app.openChat(old)
    app.switchTab(.agent)
    app.newAgentTask()
    app.switchTab(.chat)
    #expect(app.chat.conversation?.id == old.id)
    app.switchTab(.agent)              // и у агента — новая задача
    #expect(app.chat.conversation == nil && app.tab == .agent)
}

/// Без выбранной папки агент работает во «Моих файлах» (домашняя папка) — задача отправляется сразу
@MainActor @Test func agentWorksWithoutChosenFolder() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-nofolder-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    #expect(app.agentFolder.map(AppModel.isHome) == true)
    #expect(AppModel.folderName(AppModel.home) == "Мои файлы")
    app.newAgentTask()
    app.chat.send("привет")
    #expect(app.chat.conversation?.kind == .agent)
    #expect(app.chat.conversation?.folder == AppModel.home.path)
    app.chat.stop()
}

/// «Боты» — третья вкладка: возвращает открытого бота, ⌘N на ней — новый бот
@MainActor @Test func botsTabRemembersBot() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-botstab-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.saveBot(Bot(id: "tester", name: "Тестировщик"))
    app.switchTab(.bots)
    #expect(app.tab == .bots && app.page == .bots)
    app.openBot("tester")
    app.switchTab(.chat)
    #expect(app.page == .chat && app.tab == .chat)
    app.switchTab(.bots)
    #expect(app.page == .bot("tester"))
    app.newChat()
    #expect(app.page == .botEditor(nil))
}


/// Вкладка «Чат» никогда не показывает задачу агента (и наоборот), даже если вкладку переключили напрямую
@MainActor @Test func tabNeverShowsOtherKind() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-tabkind-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let task = Conversation(title: "Задача", kind: .agent, folder: "/tmp", backend: .subscription, model: .sonnet, effort: .high)
    try app.store.save(task)
    app.reloadConversations()
    app.openChat(task)
    #expect(app.tab == .agent && app.chat.conversation?.id == task.id)
    app.tab = .chat
    #expect(app.chat.conversation == nil)
    app.openChat(task)          // открыть снова — вкладка сама становится «Агентом»
    #expect(app.tab == .agent && app.chat.conversation?.id == task.id)
}

/// Несколько ключей API: старый единственный становится «Ключ 1», выбранный — в основном слоте, удаление переключает
@MainActor @Test func severalApiKeys() throws {
    setenv("LUMEN_KEYCHAIN", "com.roman.lumen.tests.keys", 1)
    let kc = Keychain(service: "com.roman.lumen.tests.keys")
    defer { for a in [Keychain.anthropicKey] { kc.delete(a) } }
    try kc.save("sk-ant-api03-first-" + String(repeating: "a", count: 30) + "AAAA", for: Keychain.anthropicKey)
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-keys-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    #expect(app.prefs.apiKeys.map(\.name) == ["Ключ 1"] && app.prefs.apiKeys.first?.tail == "AAAA")
    let first = try #require(app.prefs.apiKeys.first)
    #expect(app.prefs.activeKeyID == first.id)

    // второй ключ (как после «Проверить и добавить»)
    let second = ApiKeyEntry(name: "Ключ 2", tail: "BBBB")
    try kc.save("sk-ant-api03-second-" + String(repeating: "b", count: 30) + "BBBB", for: AppModel.keyAccount(second.id))
    app.update { $0.apiKeys.append(second) }
    app.useKey(second.id)
    #expect(app.prefs.activeKeyID == second.id)
    #expect(kc.read(Keychain.anthropicKey)?.hasSuffix("BBBB") == true)
    app.renameKey(second.id, "Рабочий")
    #expect(app.prefs.apiKeys.last?.name == "Рабочий")
    app.deleteKey(second.id)
    #expect(app.prefs.activeKeyID == first.id && kc.read(Keychain.anthropicKey)?.hasSuffix("AAAA") == true)
    for e in app.prefs.apiKeys { kc.delete(AppModel.keyAccount(e.id)) }
}


/// «Повторить»: ошибочный ответ и вопрос убираются, вопрос уходит снова
@MainActor @Test func retryResendsQuestion() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-retry-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let c = Conversation(title: "t", backend: .subscription, model: .sonnet, effort: .low)
    try app.store.save(c)
    _ = try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Вопрос"))
    let bad = try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "", error: "Claude Code завершился без ответа."))
    app.reloadConversations()
    app.openChat(c)
    app.chat.retry(bad)
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
    let msgs = try app.store.messages(in: c.id)
    // старые две строки ушли, вопрос отправлен заново (здесь нет claude — новая ошибка, но одна)
    #expect(msgs.filter { $0.role == .user }.map(\.text) == ["Вопрос"])
    #expect(msgs.count == 2 && msgs.last?.id != bad.id)
}
