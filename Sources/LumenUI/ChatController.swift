import Foundation
import LumenCore
import LumenProviders
import LumenStorage
import Observation

/// Ход чата (turn pipeline, §0 техплана): собрать системный промпт → движок → стрим → база.
/// Подписка — тёплый процесс `claude` на разговор, API — запрос со всей историей.
@MainActor @Observable
final class ChatController {
    unowned let app: AppModel

    /// Открытый разговор и его сообщения
    private(set) var conversation: Conversation?
    private(set) var messages: [ChatMessage] = []
    /// Разговор, в котором сейчас идёт ход. Ход один на всё приложение и не прерывается,
    /// если открыть другой разговор: ответ допишется в фоне и сохранится.
    private(set) var running: Conversation?
    /// Текст и шаги идущего хода; в базу — по окончании
    private var turnMessage: ChatMessage?
    private var turnThinking = false

    @ObservationIgnored private var sessions: [String: ClaudeSession] = [:]
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var turnStart = Date()
    /// Дельты текста копятся и уходят в интерфейс раз в 40 мс (§10.1): без этого окно перерисовывается на каждый токен
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var flushScheduled = false

    init(app: AppModel) {
        self.app = app
    }

    private var here: Bool { running != nil && running?.id == conversation?.id }
    /// Ход идёт в открытом разговоре
    var busy: Bool { here }
    /// Ход идёт в другом разговоре — отправить сейчас нельзя
    var busyElsewhere: Bool { running != nil && !here }
    var streaming: ChatMessage? { here ? turnMessage : nil }
    var thinking: Bool { here && turnThinking }

    // MARK: открыть / новый

    func open(_ c: Conversation) {
        guard conversation?.id != c.id else { return }
        conversation = c
        messages = (try? app.store.messages(in: c.id)) ?? []
    }

    func reloadMessages() {
        guard let c = conversation else { return }
        messages = (try? app.store.messages(in: c.id)) ?? []
    }

    /// Новый чат ещё не в базе: появится в списке после первого сообщения
    func startNew() {
        conversation = nil
        messages = []
    }

    /// Модель и «сколько думать» для следующего хода
    func set(model: ChatModel? = nil, effort: Effort? = nil) {
        app.update {
            if let model { $0.model = model }
            if let effort { $0.effort = effort }
        }
        guard var c = conversation else { return }
        if let model { c.model = model }
        if let effort { c.effort = effort }
        conversation = c
        try? app.store.save(c)
    }

    // MARK: ход

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, running == nil else { return }
        var c: Conversation
        if let existing = conversation {
            c = existing
        } else if app.tab == .agent {
            guard let folder = app.agentFolder else { return }
            c = Conversation(title: Self.title(from: text), kind: .agent, folder: folder.path, backend: app.prefs.backend,
                             model: app.defaultAgentModel, effort: .high)
            app.rememberFolder(folder)
        } else {
            c = Conversation(title: Self.title(from: text), backend: app.prefs.backend, model: app.prefs.model, effort: app.prefs.effort)
        }
        let isNew = conversation == nil
        if c.usesCLI && c.cliSessionID == nil { c.cliSessionID = UUID().uuidString.lowercased() }
        do {
            try app.store.save(c)
            let user = try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: text))
            conversation = c
            messages.append(user)
        } catch {
            return
        }
        if isNew { app.reloadConversations() }

        stopRequested = false
        turnStart = Date()
        running = c
        turnMessage = nil
        turnThinking = true
        app.orb = .thinking
        let history = messages
        turnTask = Task { [weak self] in
            guard let self else { return }
            if c.usesCLI {
                await self.runCLI(c, text: text, hadTurnsBefore: history.contains { $0.role == .assistant && $0.error == nil })
            } else {
                await self.runAPI(c, history: history)
            }
            self.turnThinking = false
            self.running = nil
            self.app.orb = .idle
            self.turnTask = nil
            self.app.reloadConversations()
        }
    }

    /// «Стоп»: подписка — сообщение `interrupt` процессу, API — обрыв соединения
    func stop() {
        guard let c = running else { return }
        stopRequested = true
        if c.usesCLI { sessions[c.id]?.interrupt() } else { turnTask?.cancel() }
    }

    /// «Сжать разговор»: claude пересказывает старое и освобождает окно (`/compact`, проверено в спайке)
    func compact() {
        guard let c = conversation, c.usesCLI, running == nil, let cli = app.cli else { return }
        running = c
        turnThinking = true
        turnStart = Date()
        app.orb = .thinking
        Task {
            var ok = false
            if let session = try? cliSession(for: c, cli: cli, resume: true), let turn = try? session.send("/compact") {
                for await ev in turn {
                    if case .compacted = ev { ok = true }
                    if case .finished = ev { break }
                }
            }
            let note = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model,
                                   error: ok ? nil : "Не получилось сжать разговор. Попробуй ещё раз.",
                                   note: ok ? "Разговор сжат: старое пересказано, место в окне освобождено" : nil)
            if let saved = try? app.store.save(note), conversation?.id == c.id { messages.append(saved) }
            turnThinking = false
            running = nil
            app.orb = .idle
        }
    }

    /// Ответ кнопкой из «что дальше»: карточка уходит, ответ отправляется
    func answer(_ choice: NextStep.Choice, on m: ChatMessage) {
        dismissNext(m)
        send(choice.reply)
    }

    func dismissNext(_ m: ChatMessage) {
        guard let i = messages.firstIndex(where: { $0.id == m.id }) else { return }
        messages[i].next = nil
        _ = try? app.store.save(messages[i])
    }

    /// Последний известный размер контекста открытого разговора
    var lastContext: (used: Int, window: Int)? {
        guard let m = messages.last(where: { $0.contextTokens != nil }), let used = m.contextTokens else { return nil }
        return (used, m.contextWindow ?? (conversation?.usesCLI == true ? 200_000 : 1_000_000))
    }

    /// Разговор удалён — его процесс больше не нужен
    func forget(_ id: String) {
        if running?.id == id { stop() }
        sessions[id]?.close()
        sessions[id] = nil
        if conversation?.id == id { startNew() }
    }

    /// Выход из приложения: погасить все процессы claude
    func closeAll() {
        for s in sessions.values { s.close() }
        sessions.removeAll()
    }

    private func runCLI(_ c: Conversation, text: String, hadTurnsBefore: Bool) async {
        guard let cli = app.cli else {
            finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        if c.backend == .api, let stop = app.limitReached {
            finish(c, text: "", error: stop)
            return
        }
        // агент: что было изменено в папке до хода — чтобы показать только его правки
        let git = c.folder.map { Git(folder: URL(fileURLWithPath: $0)) }
        var before: Git.Snapshot?
        if let git, await git.isRepo { before = try? await git.snapshot() }
        do {
            let session = try cliSession(for: c, cli: cli, resume: hadTurnsBefore)
            var answer = ""
            var result: ClaudeEvent.TurnResult?
            for await ev in try session.send(text) {
                switch ev {
                case .textDelta(let t):
                    answer += t
                    appendStreaming(t, c)
                case .step(let step):
                    appendStep(step, c)
                case .plan(let change):
                    updatePlan(change, c)
                case .finished(let r):
                    result = r
                default: break
                }
            }
            var changes: ChangeSet?
            if let git, let before, let files = try? await git.changes(since: before), !files.isEmpty {
                changes = ChangeSet(files: files)
            }
            guard let result else {
                sessions[c.id] = nil
                finish(c, text: answer, error: Self.cliError(session.errorOutput), changes: changes)
                return
            }
            // расход: по подписке claude даёт оценку «сколько стоило бы по API»; агент по ключу платит ключом
            let paidBy: Backend = c.kind == .agent && c.backend == .api ? .api : .subscription
            try? app.store.logSpend(conversationID: c.id, backend: paidBy, model: c.model.rawValue, input: result.inputTokens,
                                    output: result.outputTokens, cacheRead: result.cacheReadTokens,
                                    cacheWrite: result.cacheWriteTokens, usd: result.costUSD)
            let ctx = (result.contextTokens, result.contextWindow)
            if stopRequested {
                finish(c, text: answer, stopped: true, changes: changes, context: ctx)
            } else if result.ok {
                finish(c, text: answer.isEmpty ? result.text : answer, changes: changes, context: ctx)
            } else {
                finish(c, text: answer, error: Self.cliError(result.text), changes: changes, context: ctx)
            }
        } catch {
            finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// Тёплый процесс на разговор. Если сменились модель или effort — перезапуск с `--resume`.
    private func cliSession(for c: Conversation, cli: ClaudeCLI, resume: Bool) throws -> ClaudeSession {
        if let s = sessions[c.id], s.isRunning, s.config.model == c.model.rawValue, s.config.effort == c.effort.rawValue {
            return s
        }
        sessions[c.id]?.close()
        // не больше трёх живых процессов: старые гасим, их ход продолжится через --resume
        if sessions.count >= 3, let oldest = sessions.keys.first(where: { $0 != c.id }) {
            sessions[oldest]?.close()
            sessions[oldest] = nil
        }
        let sid = c.cliSessionID ?? UUID().uuidString.lowercased()
        var config: ClaudeSession.Config
        if c.kind == .agent, let folder = c.folder {
            config = .agent(model: c.model.rawValue, effort: c.effort.rawValue, persona: app.agentPrompt(),
                            folder: URL(fileURLWithPath: folder), sessionID: sid, resume: resume)
            // агент по ключу: тот же claude, но платит ключ (§2.4 техплана)
            if c.backend == .api, let key = app.keychain.read(Keychain.anthropicKey) { config.extraEnv["ANTHROPIC_API_KEY"] = key }
        } else {
            config = .init(model: c.model.rawValue, effort: c.effort.rawValue, systemPrompt: app.systemPrompt(),
                           tools: [], userSettings: false, sessionID: sid, resume: resume)
        }
        // память: lumen-mcp с инструментами remember и recall
        if let mcp = try? app.writeMCPConfig(for: c) {
            config.mcpConfig = mcp.path
            config.allowedTools += ["mcp__lumen__remember", "mcp__lumen__recall"]
        }
        let s = try ClaudeSession(cli: cli, config: config)
        sessions[c.id] = s
        return s
    }

    private func runAPI(_ c: Conversation, history: [ChatMessage]) async {
        guard let key = app.keychain.read(Keychain.anthropicKey) else {
            finish(c, text: "", error: APIChatError.noKey.localizedDescription)
            return
        }
        if let stop = app.limitReached {
            finish(c, text: "", error: stop)
            return
        }
        let tools = MemoryTools(store: app.store, conversationID: c.id, conversationTitle: c.title)
        var spent = APIChatEvent.Usage()
        var context = 0
        func log() {
            try? app.store.logSpend(conversationID: c.id, backend: .api, model: c.model.rawValue, input: spent.input, output: spent.output,
                                    cacheRead: spent.cacheRead, cacheWrite: spent.cacheWrite,
                                    usd: c.model.cost(input: spent.input, output: spent.output, cacheRead: spent.cacheRead, cacheWrite: spent.cacheWrite))
        }
        defer { log() }
        var request = AnthropicChatRequest(model: c.model, effort: c.effort, system: app.systemPrompt(),
                                           messages: AnthropicChatRequest.history(history))
        request.tools = MemoryTools.definitions.map {
            JSONBox(["name": $0.name, "description": $0.description, "input_schema": $0.schema, "strict": true])
        }
        var answer = ""
        // ход целиком (с вызовами инструментов) — чтобы в истории он повторился как был
        var turn: [[String: Any]] = []
        do {
            var api = AnthropicAPI(key: key)
            api.session = app.urlSession
            for _ in 0..<6 {
                var finished: (String, String)?
                for try await ev in api.chat(request) {
                    switch ev {
                    case .textDelta(let t):
                        answer += t
                        appendStreaming(t, c)
                    case .finished(let reason, let content, let usage):
                        finished = (reason, content)
                        spent.input += usage.input
                        spent.output += usage.output
                        spent.cacheRead += usage.cacheRead
                        spent.cacheWrite += usage.cacheWrite
                        context = usage.input + usage.cacheRead + usage.cacheWrite + usage.output
                    }
                }
                guard let (reason, content) = finished else {
                    // поток кончился без конца ответа — значит, нажали «Стоп»
                    finish(c, text: answer, stopped: true)
                    return
                }
                let blocks = (try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [[String: Any]]) ?? []
                turn.append(["role": "assistant", "content": blocks])
                if reason == "refusal" {
                    finish(c, text: answer, error: "Модель отказалась отвечать на это сообщение.")
                    return
                }
                let calls = blocks.filter { $0["type"] as? String == "tool_use" }
                guard reason == "tool_use", !calls.isEmpty else {
                    finish(c, text: answer, apiContent: Self.turnJSON(turn), context: (context, 1_000_000))
                    return
                }
                // выполнить инструменты памяти и продолжить ход
                var results: [[String: Any]] = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    appendStep(AgentStep.from(tool: name, input: [:]), c)
                    let out = (try? tools.call(name, call["input"] as? [String: Any] ?? [:])) ?? "Ошибка памяти"
                    results.append(["type": "tool_result", "tool_use_id": call["id"] as? String ?? "", "content": out])
                }
                turn.append(["role": "user", "content": results])
                request.messages.append(["role": "assistant", "content": JSONBox(blocks)])
                request.messages.append(["role": "user", "content": JSONBox(results)])
            }
            finish(c, text: answer, apiContent: Self.turnJSON(turn))
        } catch {
            finish(c, text: answer, stopped: stopRequested, error: stopRequested ? nil : error.localizedDescription)
        }
    }

    /// Один ход для истории: обычный — блоки ответа; с инструментами — вся цепочка в обёртке lumen_turn
    static func turnJSON(_ turn: [[String: Any]]) -> String? {
        let value: Any = turn.count == 1 ? (turn[0]["content"] ?? []) : [["lumen_turn": turn]]
        guard let d = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    private func appendStreaming(_ t: String, _ c: Conversation) {
        if turnThinking {
            turnThinking = false
            if here { app.orb = .writing }
        }
        if turnMessage == nil { turnMessage = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model) }
        pendingText += t
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.flushText()
        }
    }

    private func flushText() {
        flushScheduled = false
        guard !pendingText.isEmpty else { return }
        turnMessage?.text += pendingText
        pendingText = ""
    }

    private func updatePlan(_ change: PlanItem.Change, _ c: Conversation) {
        var updated = (running?.id == c.id ? running : nil) ?? c
        let items = PlanItem.apply(change, to: updated.plan)
        updated.plan = items
        running = updated
        if conversation?.id == c.id { conversation?.plan = items }
        try? app.store.updatePlan(c.id, items)
        // план — сбоку, как в макете: панель открывается сама
        if !app.prefs.contextOpen && conversation?.id == c.id { app.update { $0.contextOpen = true } }
    }

    private func appendStep(_ step: AgentStep, _ c: Conversation) {
        if turnThinking {
            turnThinking = false
            if here { app.orb = .idle }
        }
        if turnMessage == nil { turnMessage = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model) }
        turnMessage?.steps.append(step)
    }

    private func finish(_ c: Conversation, text: String, apiContent: String? = nil, stopped: Bool = false, error: String? = nil,
                        changes: ChangeSet? = nil, context: (Int, Int)? = nil) {
        // шаги показываем у агента; в чате вызовы памяти видны плашками «Запомнил» и «Опирался на»
        flushText()
        let steps = c.kind == .agent ? (turnMessage?.steps ?? []) : []
        turnMessage = nil
        let remembered = (try? app.store.memoryUses(conversationID: c.id, since: turnStart, action: "remember")) ?? []
        let recalled = (try? app.store.memoryUses(conversationID: c.id, since: turnStart, action: "recall")) ?? []
        // «что дальше»: агент пишет блок в конце ответа — вынимаем его из текста в карточку
        let (visible, next) = c.kind == .agent ? NextStep.split(text) : (text, nil)
        var m = ChatMessage(conversationID: c.id, role: .assistant, text: visible, apiContent: apiContent,
                            model: c.model, stopped: stopped, error: error, steps: steps, changes: changes,
                            remembered: remembered, recalled: recalled.filter { !remembered.contains($0) })
        m.next = stopped ? nil : next
        if let context, context.0 > 0 {
            m.contextTokens = context.0
            m.contextWindow = context.1 > 0 ? context.1 : nil
        }
        if let saved = try? app.store.save(m), conversation?.id == c.id { messages.append(saved) }
        if !remembered.isEmpty {
            app.reloadMemories()
            app.flash()
        }
    }

    /// Память поменялась: процессы чата гасим, следующий ход поднимет их с новым системным промптом (`--resume`)
    func memoryChanged() {
        for (id, s) in sessions where id != running?.id {
            if conversationKind(id) == .chat {
                s.close()
                sessions[id] = nil
            }
        }
    }

    private func conversationKind(_ id: String) -> ConversationKind {
        id == conversation?.id ? (conversation?.kind ?? .chat) : (app.conversations.first { $0.id == id }?.kind ?? .chat)
    }

    // MARK: карточка «Изменения»

    private func git(for m: ChatMessage) -> Git? {
        guard let folder = conversation?.folder, m.changes != nil else { return nil }
        return Git(folder: URL(fileURLWithPath: folder))
    }

    func diff(_ m: ChatMessage) async -> String {
        guard let git = git(for: m), let files = m.changes?.files else { return "" }
        do { return try await git.diff(files) } catch { return error.localizedDescription }
    }

    /// Ошибка последнего действия с изменениями — показывается в карточке
    private(set) var changeError: [Int64: String] = [:]

    func commit(_ m: ChatMessage) async {
        guard let git = git(for: m), let set = m.changes, set.state == .applied else { return }
        do {
            try await git.commit(set.files, message: conversation?.title ?? "Правки Lumen")
            update(m) { $0.changes?.state = .committed }
        } catch {
            if let id = m.id { changeError[id] = error.localizedDescription }
        }
    }

    func revert(_ m: ChatMessage) async {
        guard let git = git(for: m), let set = m.changes, set.state == .applied else { return }
        do {
            try await git.revert(set.files)
            update(m) { $0.changes?.state = .reverted }
        } catch {
            if let id = m.id { changeError[id] = error.localizedDescription }
        }
    }

    private func update(_ m: ChatMessage, _ change: (inout ChatMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == m.id }) else { return }
        change(&messages[i])
        if let id = m.id { changeError[id] = nil }
        _ = try? app.store.save(messages[i])
    }

    // MARK: мелочи

    /// Заголовок — начало первого сообщения
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 48 ? String(line.prefix(46)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// Ошибки `claude` — человеческими словами (docs/spikes.md: старая версия для Opus 5.5)
    static func cliError(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("or newer is required") {
            return "Для этой модели нужен Claude Code новее. Обнови в терминале: claude update"
        }
        if s.localizedCaseInsensitiveContains("rate limit") || s.contains("429") {
            return "Лимит подписки на сейчас исчерпан. Подожди сброса или переключи новый чат на API в Настройках."
        }
        if s.isEmpty || s.hasPrefix("[claude-code:unrecognized_model]") {
            return "Claude Code завершился без ответа. Отправь ещё раз."
        }
        return s
    }
}

extension Conversation {
    /// Агент всегда работает через claude (и по подписке, и по ключу), чат — через claude только по подписке
    var usesCLI: Bool { kind == .agent || backend == .subscription }
}

extension AppModel {
    /// Как пользоваться памятью — одинаково в чате и у агента
    var memoryRules: String {
        var r = ["У тебя есть долгая память: инструменты remember (сохранить факт) и recall (найти в памяти)."]
        if prefs.autoRemember {
            r.append("Если узнал что-то важное и устойчивое о человеке, его проектах, решениях, людях вокруг или о том, как ему удобно, — сохрани через remember одной короткой фразой. Мелочи и разовое не сохраняй.")
        } else {
            r.append("Сохраняй через remember только когда человек прямо просит запомнить.")
        }
        r.append("Когда просят «запомни» — обязательно сохрани. Если ответ опирается на прошлое (что решили, что он просил, как зовут людей), сначала вызови recall. О вызовах не рассказывай: Lumen сам покажет, что запомнил.")
        return r.joined(separator: " ")
    }

    /// mcp.json для claude: lumen-mcp с базой и разговором
    func writeMCPConfig(for c: Conversation) throws -> URL {
        guard let bin = mcpBinary else { throw CocoaError(.fileNoSuchFile) }
        let dir = paths.run.appendingPathComponent(c.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config: [String: Any] = ["mcpServers": ["lumen": [
            "command": bin.path, "args": [],
            "env": ["LUMEN_DB": paths.database.path, "LUMEN_CONVERSATION_ID": c.id, "LUMEN_CONVERSATION_TITLE": c.title],
        ]]]
        let url = dir.appendingPathComponent("mcp.json")
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted]).write(to: url)
        return url
    }

    /// lumen-mcp лежит рядом с Lumen в бандле; в тестах — рядом с собранными продуктами (LUMEN_MCP)
    var mcpBinary: URL? {
        if let env = ProcessInfo.processInfo.environment["LUMEN_MCP"] { return URL(fileURLWithPath: env) }
        let near = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("lumen-mcp")
        if let near, FileManager.default.isExecutableFile(atPath: near.path) { return near }
        // swift test: тесты лежат в .build/…/Products/Debug, рядом с lumen-mcp
        for b in Bundle.allBundles {
            let u = b.bundleURL.deletingLastPathComponent().appendingPathComponent("lumen-mcp")
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        return nil
    }

    /// Дописывается к системному промпту Claude Code у агента: кто такой Lumen и правило про push
    func agentPrompt() -> String {
        var lines = ["Ты — Lumen, агент на Маке. Отвечай по-русски, по делу."]
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name), обращайся на \(profile.address == .ty ? "«ты»" : "«вы»").") }
        lines.append("Push, публикацию и выкатку не делай: это только с явного OK, и делает их человек.")
        lines.append("""
            В самом конце каждого ответа добавь блок для карточки «что дальше» — строго JSON внутри тегов, без markdown:
            <lumen-next>{"recap": "два-три коротких предложения: что теперь сделано и что не сделано или не проверено", "ask": "один вопрос, если следующий шаг решает человек, иначе null", "primary": {"label": "1–3 слова", "reply": "что отправится от человека"} или null, "secondary": такая же вторая кнопка, только если это реальная альтернатива, иначе null}</lumen-next>
            Этот блок Lumen показывает отдельной карточкой — в тексте ответа итог не повторяй.
            """)
        lines.append(memoryRules)
        return lines.joined(separator: "\n")
    }

    /// Системный промпт Lumen (SOUL v0): кто он, с кем говорит, закреплённые факты.
    /// Детерминированный — одинаковый от хода к ходу, поэтому кэшируется.
    func systemPrompt() -> String {
        var lines = ["Ты — Lumen, личный помощник на Маке. Отвечай по-русски, если тебя не попросили иначе. Пиши по делу, без воды."]
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name).") }
        lines.append(profile.address == .ty ? "Обращайся к нему на «ты»." : "Обращайся к нему на «вы».")
        let pinned = ((try? store.memories()) ?? []).filter(\.pinned).map(\.text)
        if !pinned.isEmpty {
            lines.append("Что ты знаешь о нём:")
            lines += pinned.map { "- \($0)" }
        }
        lines.append("Это чат: у тебя нет доступа к файлам и командам этого Мака.")
        lines.append(memoryRules)
        return lines.joined(separator: "\n")
    }
}
