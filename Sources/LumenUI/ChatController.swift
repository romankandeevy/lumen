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
    /// Идущие ходы ChatGPT — для «Стоп»
    @ObservationIgnored private var codexRuns: [String: CodexRun] = [:]
    /// Вопрос агента «можно?» — ждёт ответа человека (режимы «Спрашивать», «Принимать правки», «Авто», «План»)
    struct PendingPermission: Equatable {
        let conversationID: String
        let request: ClaudeEvent.PermissionRequest
    }
    var pendingPermission: PendingPermission?
    /// «Разрешать такое до конца разговора»: инструменты, на которые больше не спрашиваем
    @ObservationIgnored private var alwaysAllowed: [String: Set<String>] = [:]
    /// Режим, в котором сейчас живёт процесс разговора
    @ObservationIgnored private var sessionModes: [String: AgentMode] = [:]
    /// Разговор бота, который сейчас выполняет задачу из этого чата (@id) — для «Стоп»
    @ObservationIgnored private var delegateRunning: String?
    /// Чей ответ идёт: бот (его знак вместо сферы) или Lumen
    private(set) var turnBot: String?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var turnStart = Date()
    /// Плавная печать: claude присылает текст пачками раз в ~0,5 с (замер: 10–20 кусков сразу),
    /// поэтому полученное копится здесь, а на экран выходит равномерно, раз в 30 мс (§10.1)
    @ObservationIgnored private var received = ""
    @ObservationIgnored private var revealTask: Task<Void, Never>?

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

    func moved(_ id: String, _ projectID: String?) {
        if conversation?.id == id { conversation?.projectID = projectID }
        if running?.id == id { running?.projectID = projectID }
        promptChanged(conversationID: id)
    }

    /// Инструкции или файлы проекта поменялись — процессы его разговоров гасим, следующий ход возьмёт новый промпт
    func promptChanged(projectID: String? = nil, conversationID: String? = nil) {
        for (id, s) in sessions where id != running?.id {
            let pid = id == conversation?.id ? conversation?.projectID : app.conversations.first { $0.id == id }?.projectID
            if id == conversationID || (projectID != nil && pid == projectID) {
                s.close()
                sessions[id] = nil
            }
        }
    }

    /// Обновить открытый разговор (бот поменял папку или «сколько думать»)
    func refresh(_ c: Conversation) {
        if conversation?.id == c.id { conversation = c }
    }

    func renamed(_ id: String, _ title: String) {
        if conversation?.id == id { conversation?.title = title }
        if running?.id == id { running?.title = title }
    }

    func reloadMessages() {
        guard let c = conversation else { return }
        messages = (try? app.store.messages(in: c.id)) ?? []
    }

    /// Проект для нового разговора, пока он не начат
    private(set) var newProjectID: String?

    /// Новый чат ещё не в базе: появится в списке после первого сообщения
    func startNew(projectID: String? = nil) {
        newProjectID = projectID
        conversation = nil
        messages = []
    }

    /// «Повторить»: ошибочный ответ и вопрос к нему убираются, вопрос отправляется заново (с теми же вложениями)
    func retry(_ failed: ChatMessage) {
        guard running == nil, let i = messages.firstIndex(where: { $0.id == failed.id }),
              let u = messages[..<i].last(where: { $0.role == .user }) else { return }
        for m in [failed, u] {
            if let id = m.id { try? app.store.deleteMessage(id) }
        }
        messages.removeAll { $0.id == failed.id || $0.id == u.id }
        send(u.text, attachments: u.attachments)
    }

    /// Режим агента: у начатой задачи меняется сразу, на ходу; у новой — запоминается для следующей
    func set(mode: AgentMode) {
        app.update { $0.agentMode = mode }
        guard var c = conversation, c.kind == .agent else { return }
        c.mode = mode
        conversation = c
        try? app.store.save(c)
        if let s = sessions[c.id], s.isRunning, sessionModes[c.id] != mode {
            s.setMode(mode.rawValue)
            sessionModes[c.id] = mode
        }
    }

    /// Ответ на вопрос агента
    func answerPermission(allow: Bool, always: Bool = false, message: String? = nil) {
        guard let p = pendingPermission, let s = sessions[p.conversationID] else { pendingPermission = nil; return }
        if allow && always { alwaysAllowed[p.conversationID, default: []].insert(p.request.tool) }
        s.respond(p.request.id, allow: allow, inputJSON: p.request.inputJSON, message: message)
        pendingPermission = nil
        if running?.id == p.conversationID { app.orb = .thinking }
    }

    /// План готов: выполнить в выбранном режиме или доработать
    func answerPlan(run mode: AgentMode?, note: String? = nil) {
        guard let p = pendingPermission, p.request.tool == "ExitPlanMode" else { return }
        if let mode {
            answerPermission(allow: true)
            set(mode: mode)
        } else {
            answerPermission(allow: false, message: note.map { "Доработай план: \($0)" } ?? "Человек просит доработать план.")
        }
    }

    /// Модель и «сколько думать» для следующего хода
    func set(model: ChatModel? = nil, effort: Effort? = nil) {
        // новая задача агента помнит свои модель и «сколько думать», чат — свои
        let newAgent = conversation == nil && app.tab == .agent
        app.update {
            if let model { if newAgent { $0.agentModel = model } else { $0.model = model } }
            if let effort { if newAgent { $0.agentEffort = effort } else { $0.effort = effort } }
        }
        guard var c = conversation else { return }
        if let model { c.model = model }
        if let effort { c.effort = effort }
        conversation = c
        try? app.store.save(c)
    }

    // MARK: ход

    func send(_ raw: String, attachments: [Attachment] = []) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, running == nil else { return }
        var c: Conversation
        if let existing = conversation {
            c = existing
        } else if app.tab == .agent {
            guard let folder = app.agentFolder else { return }
            c = Conversation(title: Self.title(from: text.isEmpty ? attachments.first?.name ?? "Вложение" : text), kind: .agent, folder: folder.path, backend: app.prefs.backend,
                             model: app.defaultAgentModel, effort: app.prefs.agentEffort ?? .high)
            c.mode = app.prefs.agentMode
            app.rememberFolder(folder)
        } else {
            c = Conversation(title: Self.title(from: text.isEmpty ? attachments.first?.name ?? "Вложение" : text), backend: app.prefs.backend, model: app.prefs.model, effort: app.prefs.effort)
        }
        if conversation == nil { c.projectID = newProjectID }
        // ChatGPT идёт по подписке ChatGPT, не по ключу Anthropic
        if c.model.isGPT { c.backend = .subscription }
        let isNew = conversation == nil
        if c.usesCLI && c.cliSessionID == nil { c.cliSessionID = UUID().uuidString.lowercased() }
        do {
            try app.store.save(c)
            var u = ChatMessage(conversationID: c.id, role: .user, text: text)
            u.attachments = attachments
            let user = try app.store.save(u)
            conversation = c
            messages.append(user)
        } catch {
            return
        }
        if isNew { app.reloadConversations() }
        // «@tester …» в обычном чате — задачу выполняет бот, ответ приходит сюда же (техплан §4.6)
        let delegate = c.kind == .bot ? nil : app.mention(in: text)

        stopRequested = false
        turnStart = Date()
        running = c
        turnMessage = nil
        turnBot = delegate?.0.id ?? (c.kind == .bot ? c.botID : nil)
        turnThinking = true
        app.orb = .thinking
        let history = messages
        turnTask = Task { [weak self] in
            guard let self else { return }
            if let (bot, task) = delegate {
                await self.runDelegation(c, bot: bot, task: task)
            } else if c.model.isGPT {
                await self.runCodex(c, text: text, attachments: attachments)
            } else if c.usesCLI {
                await self.runCLI(c, text: text, attachments: attachments, hadTurnsBefore: history.contains { $0.role == .assistant && $0.error == nil && ($0.botID == nil || c.kind == .bot) })
            } else {
                await self.runAPI(c, history: history)
            }
            self.turnThinking = false
            self.running = nil
            self.turnBot = nil
            self.app.orb = .idle
            self.turnTask = nil
            self.app.reloadConversations()
        }
    }

    /// Под ответом появился предложенный навык
    func attachSkillDraft(_ d: SkillDraft?, to messageID: Int64, conversationID: String) {
        guard var m = ((try? app.store.messages(in: conversationID)) ?? []).first(where: { $0.id == messageID }) else { return }
        m.skillDraft = d
        _ = try? app.store.save(m)
        if let i = messages.firstIndex(where: { $0.id == messageID }) { messages[i].skillDraft = d }
    }

    /// Бот изменён — его процесс гасим, следующий ход поднимет его с новыми правами (`--resume`)
    func restart(_ id: String) {
        guard running?.id != id else { return }
        sessions[id]?.close()
        sessions[id] = nil
    }

    /// Задача боту из чужого чата: бот работает в своём постоянном разговоре (туда пишется задача и ответ),
    /// а ответ с его знаком появляется в этом чате.
    private func runDelegation(_ c: Conversation, bot: Bot, task: String) async {
        guard let cli = app.cli else {
            await finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        let b = app.botConversation(for: bot)
        let earlier = (try? app.store.messages(in: b.id)) ?? []
        let hadTurns = earlier.contains { $0.role == .assistant && $0.error == nil }
        // в разговоре бота — твоё сообщение как есть и пометка «из чата …»; что было в том чате, бот получает скрыто
        let context = ((try? app.store.messages(in: c.id)) ?? []).dropLast().suffix(6).map { m -> String in
            let who = m.role == .user ? (app.profile.name.isEmpty ? "Человек" : app.profile.name) : (m.botID.map { "@\($0)" } ?? "Lumen")
            return "\(who): \(m.text.prefix(600))"
        }.joined(separator: "\n")
        let taskText = Via.modelText(task: task, from: c.title, context: context)
        var asked = ChatMessage(conversationID: b.id, role: .user, text: task)
        asked.via = Via(conversationID: c.id, title: c.title)
        _ = try? app.store.save(asked)
        app.botRuns[bot.id] = c.title
        defer { app.botRuns[bot.id] = nil }
        let git = Git(folder: URL(fileURLWithPath: b.folder ?? app.botFolder(bot).path))
        var before: Git.Snapshot?
        if bot.can.contains(.write) || bot.can.contains(.run), await git.isRepo { before = try? await git.snapshot() }
        do {
            let session = try cliSession(for: b, cli: cli, resume: hadTurns)
            var answer = ""
            var result: ClaudeEvent.TurnResult?
            delegateRunning = b.id
            defer { delegateRunning = nil }
            for await ev in try session.send(taskText) {
                switch ev {
                case .textDelta(let t):
                    answer += t
                    appendStreaming(t, c)
                case .step(let step):
                    appendStep(step, c)
                case .finished(let r):
                    result = r
                default: break
                }
            }
            var changes: ChangeSet?
            if let before, let files = try? await git.changes(since: before), !files.isEmpty { changes = ChangeSet(files: files) }
            if let result {
                try? app.store.logSpend(conversationID: b.id, backend: .subscription, model: b.model.rawValue, input: result.inputTokens,
                                        output: result.outputTokens, cacheRead: result.cacheReadTokens,
                                        cacheWrite: result.cacheWriteTokens, usd: result.costUSD)
            }
            let ok = result?.ok == true
            let error = stopRequested ? nil : (ok ? nil : Self.cliError(result?.text ?? session.errorOutput))
            let text = answer.isEmpty ? (ok ? result?.text ?? "" : "") : answer
            // в постоянный разговор бота — весь ход
            var m = ChatMessage(conversationID: b.id, role: .assistant, text: text, model: b.model, stopped: stopRequested, error: error,
                                steps: turnMessage?.steps ?? [], changes: changes)
            m.botID = bot.id
            _ = try? app.store.save(m)
            if !ok && !stopRequested { sessions[b.id] = nil }
            await finish(c, text: text, stopped: stopRequested, error: error, changes: changes)
        } catch {
            await finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// «Стоп»: подписка — сообщение `interrupt` процессу, API — обрыв соединения
    func stop() {
        guard let c = running else { return }
        stopRequested = true
        if let p = pendingPermission, p.conversationID == c.id {
            sessions[c.id]?.respond(p.request.id, allow: false, message: "Человек остановил задачу.")
            pendingPermission = nil
        }
        if let d = delegateRunning { sessions[d]?.interrupt() } else if c.model.isGPT { codexRuns[c.id]?.stop() } else if c.usesCLI { sessions[c.id]?.interrupt() } else { turnTask?.cancel() }
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

    private func runCLI(_ c: Conversation, text: String, attachments: [Attachment] = [], hadTurnsBefore: Bool, retried: Bool = false) async {
        guard let cli = app.cli else {
            await finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        if c.backend == .api, let stop = app.limitReached {
            await finish(c, text: "", error: stop)
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
            let turn = attachments.isEmpty ? try session.send(text)
                : try session.send(content: Attachment.userContent(text: text, attachments: attachments, agent: c.kind != .chat))
            for await ev in turn {
                switch ev {
                case .textDelta(let t):
                    answer += t
                    appendStreaming(t, c)
                case .step(let step):
                    appendStep(step, c)
                case .plan(let change):
                    updatePlan(change, c)
                case .permission(let req):
                    // разрешено «до конца разговора» — не спрашиваем снова
                    if alwaysAllowed[c.id]?.contains(req.tool) == true {
                        session.respond(req.id, allow: true, inputJSON: req.inputJSON)
                    } else {
                        pendingPermission = PendingPermission(conversationID: c.id, request: req)
                        if here { app.orb = .idle }
                    }
                case .finished(let r):
                    result = r
                default: break
                }
            }
            if pendingPermission?.conversationID == c.id { pendingPermission = nil }
            var changes: ChangeSet?
            if let git, let before, let files = try? await git.changes(since: before), !files.isEmpty {
                changes = ChangeSet(files: files)
            }
            guard let result else {
                sessions[c.id] = nil
                let raw = session.errorOutput
                // продолжать было нечего (сессии claude для этого чата нет) — начать её заново, один раз
                if !retried, hadTurnsBefore, raw.localizedCaseInsensitiveContains("no conversation found") {
                    app.log("Сессия \(c.cliSessionID ?? "-") не нашлась — начинаю заново", conversation: c)
                    await runCLI(c, text: text, attachments: attachments, hadTurnsBefore: false, retried: true)
                    return
                }
                app.log("claude завершился без итога. stderr:\n\(raw)", conversation: c)
                await finish(c, text: answer, error: Self.cliError(raw), changes: changes)
                return
            }
            // расход: по подписке claude даёт оценку «сколько стоило бы по API»; агент по ключу платит ключом
            let paidBy: Backend = c.kind == .agent && c.backend == .api ? .api : .subscription
            try? app.store.logSpend(conversationID: c.id, backend: paidBy, model: c.model.rawValue, input: result.inputTokens,
                                    output: result.outputTokens, cacheRead: result.cacheReadTokens,
                                    cacheWrite: result.cacheWriteTokens, usd: result.costUSD)
            let ctx = (result.contextTokens, result.contextWindow)
            if stopRequested {
                await finish(c, text: answer, stopped: true, changes: changes, context: ctx)
            } else if result.ok {
                await finish(c, text: answer.isEmpty ? result.text : answer, changes: changes, context: ctx)
            } else {
                app.log("claude ответил ошибкой: \(result.text)\nstderr:\n\(session.errorOutput)", conversation: c)
                await finish(c, text: answer, error: Self.cliError(result.text.isEmpty ? session.errorOutput : result.text), changes: changes, context: ctx)
            }
        } catch {
            await finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// Ход через ChatGPT (codex). Разговор продолжается по thread_id, который хранится в `cliSessionID`.
    /// Свои правила Lumen передаёт в начале первого хода: системного промпта у `codex exec` нет.
    private func runCodex(_ c: Conversation, text: String, attachments: [Attachment] = []) async {
        guard let codex = app.codexCLI, app.codex == .signedIn else {
            await finish(c, text: "", error: "ChatGPT не подключён. Войди в Настройках → Модели и оплата → ChatGPT.")
            return
        }
        var c = c
        let folder: URL
        if let f = c.folder {
            folder = URL(fileURLWithPath: f)
        } else {
            // чату папка не нужна: пустая, только чтение
            folder = app.paths.run.appendingPathComponent(c.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let git = c.kind == .agent ? Git(folder: folder) : nil
        var before: Git.Snapshot?
        if let git, await git.isRepo { before = try? await git.snapshot() }

        var prompt = text
        let inline = Attachment.inlineText(attachments)
        if !inline.isEmpty { prompt = inline + "\n\n" + prompt }
        if c.cliSessionID == nil {
            let rules = c.kind == .agent ? app.agentPrompt(for: c) : app.systemPrompt(for: c)
            prompt = "<lumen-instructions>\n\(rules)\n</lumen-instructions>\n\n" + text
        }
        var memory: (command: String, env: [String: String])?
        if let bin = app.mcpBinary {
            memory = (bin.path, ["LUMEN_DB": app.paths.database.path, "LUMEN_CONVERSATION_ID": c.id, "LUMEN_CONVERSATION_TITLE": c.title,
                                 "LUMEN_SKILLS_DIR": app.paths.skills.path, "LUMEN_SKILLS": "*"])
        }
        // у ChatGPT нет вопросов на ходу: «План» — только чтение, остальные режимы — правка в своей папке
        var turn = CodexCLI.Turn(model: c.model.rawValue, effort: c.effort.rawValue, agent: c.kind == .agent && c.mode != .plan,
                                 folder: folder, threadID: c.cliSessionID, memoryServer: memory)
        turn.images = attachments.filter { $0.kind == .image }.map(\.path)
        do {
            let run = try codex.run(turn, prompt: prompt)
            codexRuns[c.id] = run
            defer { codexRuns[c.id] = nil }
            var answer = ""
            var result: ClaudeEvent.TurnResult?
            for await ev in run.events {
                switch ev {
                case .started(let thread, _, _) where c.cliSessionID == nil && !thread.isEmpty:
                    c.cliSessionID = thread
                    try? app.store.save(c)
                    if conversation?.id == c.id { conversation?.cliSessionID = thread }
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
            let ctx = result.map { ($0.contextTokens, $0.contextWindow) }
            if stopRequested {
                await finish(c, text: answer, stopped: true, changes: changes, context: ctx)
            } else if let result, result.ok {
                await finish(c, text: answer, changes: changes, context: ctx)
            } else {
                await finish(c, text: answer, error: Self.codexError(result?.text ?? run.errorOutput), changes: changes, context: ctx)
            }
        } catch {
            await finish(c, text: "", error: error.localizedDescription)
        }
    }

    static func codexError(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("401") || s.localizedCaseInsensitiveContains("unauthorized") {
            return "ChatGPT просит войти заново: Настройки → Модели и оплата → ChatGPT."
        }
        if s.localizedCaseInsensitiveContains("usage limit") || s.contains("429") {
            return "Лимит ChatGPT на сейчас исчерпан. Подожди сброса или выбери модель Claude."
        }
        if s.isEmpty { return "ChatGPT не ответил. Отправь ещё раз." }
        return s
    }

    /// Тёплый процесс на разговор. Если сменились модель или effort — перезапуск с `--resume`.
    private func cliSession(for c: Conversation, cli: ClaudeCLI, resume: Bool) throws -> ClaudeSession {
        if let s = sessions[c.id], s.isRunning, s.config.model == c.model.rawValue, s.config.effort == c.effort.rawValue {
            // режим меняется на ходу, без перезапуска
            if c.kind == .agent, let mode = c.mode, sessionModes[c.id] != mode {
                s.setMode(mode.rawValue)
                sessionModes[c.id] = mode
            }
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
        let bot = c.kind == .bot ? app.bot(c.botID) : nil
        if let bot {
            // бот: только инструменты его роли, без настроек пользователя; всё прочее отклоняется (dontAsk)
            let perms = BotPermissions(bot)
            config = .init(model: bot.model.rawValue, effort: bot.effort.rawValue, tools: perms.tools, userSettings: false,
                           sessionID: sid, resume: resume, cwd: app.botFolder(bot), appendSystemPrompt: app.botPrompt(bot),
                           allowedTools: perms.allowed, disallowedTools: perms.disallowed)
            if c.backend == .api, let key = app.keychain.read(Keychain.anthropicKey) { config.extraEnv["ANTHROPIC_API_KEY"] = key }
            // позванный бот может работать минутами — MCP-вызову delegate даём до 15 минут
            if bot.can.contains(.bots) { config.extraEnv["MCP_TOOL_TIMEOUT"] = "900000" }
        } else if c.kind == .agent, let folder = c.folder {
            let mode = c.mode ?? app.prefs.agentMode
            config = .agent(model: c.model.rawValue, effort: c.effort.rawValue, persona: app.agentPrompt(for: c),
                            folder: URL(fileURLWithPath: folder), sessionID: sid, resume: resume, mode: mode.rawValue)
            sessionModes[c.id] = mode
            // агент по ключу: тот же claude, но платит ключ (§2.4 техплана)
            if c.backend == .api, let key = app.keychain.read(Keychain.anthropicKey) { config.extraEnv["ANTHROPIC_API_KEY"] = key }
        } else {
            config = .init(model: c.model.rawValue, effort: c.effort.rawValue, systemPrompt: app.systemPrompt(for: c),
                           tools: [], userSettings: false, sessionID: sid, resume: resume)
        }
        // память: lumen-mcp с инструментами remember и recall
        if let mcp = try? app.writeMCPConfig(for: c, memoryReadOnly: bot.map { !$0.can.contains(.memory) } ?? false) {
            config.mcpConfig = mcp.path
            // у бота разрешённое уже посчитано в BotPermissions
            if bot == nil {
                config.allowedTools += ["mcp__lumen__remember", "mcp__lumen__recall", "mcp__lumen__load_skill", "mcp__lumen__read_skill_file",
                                        "mcp__lumen__list_skills", "mcp__lumen__create_skill", "mcp__lumen__find_skills", "mcp__lumen__install_skill"]
            }
        }
        let s = try ClaudeSession(cli: cli, config: config)
        sessions[c.id] = s
        return s
    }

    private func runAPI(_ c: Conversation, history: [ChatMessage]) async {
        guard let key = app.keychain.read(Keychain.anthropicKey) else {
            await finish(c, text: "", error: APIChatError.noKey.localizedDescription)
            return
        }
        if let stop = app.limitReached {
            await finish(c, text: "", error: stop)
            return
        }
        let tools = MemoryTools(store: app.store, conversationID: c.id, conversationTitle: c.title, skills: app.skillLibrary)
        var spent = APIChatEvent.Usage()
        var context = 0
        func log() {
            try? app.store.logSpend(conversationID: c.id, backend: .api, model: c.model.rawValue, input: spent.input, output: spent.output,
                                    cacheRead: spent.cacheRead, cacheWrite: spent.cacheWrite,
                                    usd: c.model.cost(input: spent.input, output: spent.output, cacheRead: spent.cacheRead, cacheWrite: spent.cacheWrite))
        }
        defer { log() }
        var request = AnthropicChatRequest(model: c.model, effort: c.effort, system: app.systemPrompt(for: c),
                                           messages: AnthropicChatRequest.history(history))
        request.tools = (MemoryTools.definitions + (tools.availableSkills.isEmpty ? [] : MemoryTools.skillDefinitions) + SkillAdmin.definitions).map {
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
                    await finish(c, text: answer, stopped: true)
                    return
                }
                let blocks = (try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [[String: Any]]) ?? []
                turn.append(["role": "assistant", "content": blocks])
                if reason == "refusal" {
                    await finish(c, text: answer, error: "Модель отказалась отвечать на это сообщение.")
                    return
                }
                let calls = blocks.filter { $0["type"] as? String == "tool_use" }
                guard reason == "tool_use", !calls.isEmpty else {
                    await finish(c, text: answer, apiContent: Self.turnJSON(turn), context: (context, 1_000_000))
                    return
                }
                // выполнить инструменты памяти и продолжить ход
                var results: [[String: Any]] = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    appendStep(AgentStep.from(tool: name, input: [:]), c)
                    let input = call["input"] as? [String: Any] ?? [:]
                    // навыки (создать, найти, поставить) — общий код с lumen-mcp; остальное — память и чтение навыков
                    let out = SkillAdmin.names.contains(name)
                        ? await SkillAdmin.call(name, SkillAdmin.Args(input), library: app.skillLibrary, session: app.urlSession)
                        : ((try? tools.call(name, input)) ?? "Ошибка памяти")
                    results.append(["type": "tool_result", "tool_use_id": call["id"] as? String ?? "", "content": out])
                }
                turn.append(["role": "user", "content": results])
                request.messages.append(["role": "assistant", "content": JSONBox(blocks)])
                request.messages.append(["role": "user", "content": JSONBox(results)])
            }
            await finish(c, text: answer, apiContent: Self.turnJSON(turn))
        } catch {
            await finish(c, text: answer, stopped: stopRequested, error: stopRequested ? nil : error.localizedDescription)
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
        if turnMessage == nil { turnMessage = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model); turnMessage?.botID = turnBot }
        received += t
        guard revealTask == nil else { return }
        revealTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let shown = self.turnMessage?.text.count ?? 0
                let backlog = self.received.count - shown
                if backlog > 0 {
                    // хвост догоняется примерно за 0,4 с, но не быстрее символа за кадр
                    let step = max(1, Int((Double(backlog) / 12).rounded(.up)))
                    let next = self.received.prefix(shown + step)
                    self.turnMessage?.text = String(next)
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// Дождаться, пока печать догонит полученное (не дольше 1,5 с), и остановить её
    private func drainReveal(instant: Bool) async {
        if !instant {
            let deadline = Date().addingTimeInterval(1.5)
            while (turnMessage?.text.count ?? 0) < received.count, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        revealTask?.cancel()
        revealTask = nil
        if turnMessage != nil { turnMessage?.text = received }
        received = ""
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
        if turnMessage == nil { turnMessage = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model); turnMessage?.botID = turnBot }
        turnMessage?.steps.append(step)
    }

    private func finish(_ c: Conversation, text: String, apiContent: String? = nil, stopped: Bool = false, error: String? = nil,
                        changes: ChangeSet? = nil, context: (Int, Int)? = nil) async {
        // ответ допечатывается до конца; «Стоп» и ошибки — сразу
        await drainReveal(instant: stopped || error != nil)
        if let error { app.log("Ошибка в разговоре: \(error)", conversation: c) }
        // шаги показываем у агента; в чате вызовы памяти видны плашками «Запомнил» и «Опирался на»
        // у агента и ботов шаги видны; в чате вызовы памяти видны плашками «Запомнил» и «Опирался на»
        let steps = c.kind != .chat || turnBot != nil ? (turnMessage?.steps ?? []) : []
        turnMessage = nil
        let remembered = (try? app.store.memoryUses(conversationID: c.id, since: turnStart, action: "remember")) ?? []
        let recalled = (try? app.store.memoryUses(conversationID: c.id, since: turnStart, action: "recall")) ?? []
        // «что дальше»: агент пишет блок в конце ответа — вынимаем его из текста в карточку
        let (visible, next) = c.kind == .agent ? NextStep.split(text) : (text, nil)
        var m = ChatMessage(conversationID: c.id, role: .assistant, text: visible, apiContent: apiContent,
                            model: c.model, stopped: stopped, error: error, steps: steps, changes: changes,
                            remembered: remembered, recalled: recalled.filter { !remembered.contains($0) })
        m.next = stopped ? nil : next
        m.botID = turnBot
        if let context, context.0 > 0 {
            m.contextTokens = context.0
            m.contextWindow = context.1 > 0 ? context.1 : nil
        }
        let saved = try? app.store.save(m)
        if let saved, conversation?.id == c.id { messages.append(saved) }
        // первый ответ — название разговора от модели
        if error == nil && !stopped && !visible.isEmpty, c.kind != .bot,
           let all = try? app.store.messages(in: c.id), all.filter({ $0.role == .assistant }).count == 1,
           let q = all.first(where: { $0.role == .user })?.text {
            Task { await app.nameConversation(c, question: q, answer: visible) }
        }
        // обучение на опыте: у ботов — выводы, у ботов и агента после большой задачи — предложенный навык
        if error == nil && !stopped && (c.kind != .chat || turnBot != nil) {
            let bot = app.bot(turnBot ?? (c.kind == .bot ? c.botID : nil))
            let task = ((try? app.store.messages(in: c.id)) ?? []).last(where: { $0.role == .user })?.text ?? ""
            let id = saved?.id
            Task { await app.learn(task: task, answer: visible, steps: steps, bot: bot, messageID: id, conversationID: c.id) }
        }
        app.reloadSkills()
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
        if s.localizedCaseInsensitiveContains("no conversation found") {
            return "Claude Code не нашёл прошлый разговор. Нажми «Повторить» — начну заново."
        }
        if s.localizedCaseInsensitiveContains("not logged in") || s.localizedCaseInsensitiveContains("/login") {
            return "Claude Code просит войти заново: Настройки → Модели и оплата → «Войти через браузер»."
        }
        if s.localizedCaseInsensitiveContains("overloaded") || s.contains("529") {
            return "Серверы Anthropic перегружены. Нажми «Повторить» через минуту."
        }
        if s.isEmpty || s.hasPrefix("[claude-code:unrecognized_model]") {
            return "Claude Code завершился без ответа. Нажми «Повторить»; подробности — в журнале."
        }
        // последняя содержательная строка — без простыни
        let line = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? s
        return "Claude Code: " + String(line.prefix(300))
    }
}

extension Conversation {
    /// Агент всегда работает через claude (и по подписке, и по ключу), чат — через claude только по подписке
    var usesCLI: Bool { !model.isGPT && (kind != .chat || backend == .subscription) }
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
    func writeMCPConfig(for c: Conversation, memoryReadOnly: Bool = false) throws -> URL {
        let b = c.kind == .bot ? bot(c.botID) : nil
        guard let bin = mcpBinary else { throw CocoaError(.fileNoSuchFile) }
        let dir = paths.run.appendingPathComponent(c.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config: [String: Any] = ["mcpServers": ["lumen": [
            "command": bin.path, "args": [],
            "env": ["LUMEN_DB": paths.database.path, "LUMEN_CONVERSATION_ID": c.id, "LUMEN_CONVERSATION_TITLE": c.title,
                    "LUMEN_MEMORY_READONLY": memoryReadOnly ? "1" : "0",
                    "LUMEN_SKILLS_DIR": paths.skills.path, "LUMEN_SKILLS": b.map { $0.skills.joined(separator: ",") } ?? "*",
                    "LUMEN_BOT_ID": b?.id ?? "", "LUMEN_DEPTH": "0"],
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
    /// Инструкции и файлы проекта разговора — в конец системного промпта
    func projectBlock(for c: Conversation?) -> String? {
        guard let p = project(c?.projectID) else { return nil }
        return p.promptBlock(files: files(of: p))
    }

    func agentPrompt(for c: Conversation? = nil) -> String {
        var lines = ["Ты — Lumen, агент на Маке. Отвечай по-русски, по делу."]
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name), обращайся на \(profile.address == .ty ? "«ты»" : "«вы»").") }
        lines.append("Push, публикацию и выкатку не делай: это только с явного OK, и делает их человек.")
        lines.append("""
            В самом конце каждого ответа добавь блок для карточки «что дальше» — строго JSON внутри тегов, без markdown:
            <lumen-next>{"recap": "два-три коротких предложения: что теперь сделано и что не сделано или не проверено", "ask": "один вопрос, если следующий шаг решает человек, иначе null", "primary": {"label": "1–3 слова", "reply": "что отправится от человека"} или null, "secondary": такая же вторая кнопка, только если это реальная альтернатива, иначе null}</lumen-next>
            Этот блок Lumen показывает отдельной карточкой — в тексте ответа итог не повторяй.
            """)
        if let block = projectBlock(for: c) { lines.append(block) }
        if let skills = SkillLibrary.promptBlock(skillLibrary.enabled()) { lines.append(skills) }
        lines.append(selfRules)
        lines.append(memoryRules)
        return lines.joined(separator: "\n")
    }

    /// Что Lumen умеет сам с собой: навыки (создать, найти, поставить)
    var selfRules: String {
        """
        Ты умеешь достраивать себя навыками (SKILL.md, формат agentskills.io): list_skills — какие есть; create_skill — создать новый; \
        find_skills и install_skill — найти и поставить готовый из каталога skills.sh. Когда просят научиться чему-то, сделать навык \
        или приём повторяется — сделай навык сам, не отказывайся. Ботов человек создаёт во вкладке «Боты» — подскажи, если спрашивают. \
        Коннекторов к внешним сервисам пока нет — так и скажи, если просят.
        """
    }

    /// Библиотека навыков Lumen
    var skillLibrary: SkillLibrary { SkillLibrary(root: paths.skills) }

    /// Системный промпт Lumen (SOUL v0): кто он, с кем говорит, закреплённые факты.
    /// Детерминированный — одинаковый от хода к ходу, поэтому кэшируется.
    func systemPrompt(for c: Conversation? = nil) -> String {
        var lines = ["Ты — Lumen, личный помощник на Маке. Отвечай по-русски, если тебя не попросили иначе. Пиши по делу, без воды."]
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name).") }
        lines.append(profile.address == .ty ? "Обращайся к нему на «ты»." : "Обращайся к нему на «вы».")
        let pinned = ((try? store.memories()) ?? []).filter(\.pinned).map(\.text)
        if !pinned.isEmpty {
            lines.append("Что ты знаешь о нём:")
            lines += pinned.map { "- \($0)" }
        }
        lines.append("Это чат: у тебя нет доступа к файлам и командам этого Мака.")
        if let block = projectBlock(for: c) { lines.append(block) }
        if let skills = SkillLibrary.promptBlock(skillLibrary.enabled()) { lines.append(skills) }
        lines.append(selfRules)
        lines.append(memoryRules)
        return lines.joined(separator: "\n")
    }
}
