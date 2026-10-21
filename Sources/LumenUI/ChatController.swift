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
    /// Идущие ходы — по разговорам: можно писать в другом чате, пока Lumen отвечает в этом.
    /// Ход не прерывается, если открыть другой разговор: ответ допишется в фоне и сохранится.
    private(set) var turns: [String: Turn] = [:]

    /// Один идущий ход: текст и шаги (в базу — по окончании), «Стоп», плавная печать
    @MainActor @Observable final class Turn {
        var conversation: Conversation
        var message: ChatMessage?
        var thinking = true
        /// Запускается процесс claude (первые секунды нового разговора: навыки, коннекторы) — это не «думает»
        var launching = false
        /// Чей ответ идёт: бот (его знак вместо сферы) или Lumen
        var bot: String?
        @ObservationIgnored var task: Task<Void, Never>?
        @ObservationIgnored var stopRequested = false
        @ObservationIgnored var start = Date()
        /// Плавная печать: claude присылает текст пачками раз в ~0,5 с, полученное копится здесь,
        /// а на экран выходит равномерно, раз в 30 мс (§10.1)
        @ObservationIgnored var received = ""
        @ObservationIgnored var revealTask: Task<Void, Never>?
        /// Разговор бота, который выполняет задачу из этого чата (@id) — для «Стоп»
        @ObservationIgnored var delegate: String?
        /// Был вызов инструмента — следующий текст с нового абзаца
        @ObservationIgnored var needBreak = false
        /// Последняя метка ответа в сессии claude
        @ObservationIgnored var anchor: String?
        /// Группа: человек написал, пока боты отвечали
        @ObservationIgnored var newInput = false
        /// Lumen позвал бота, и его ответ уже показан отдельным сообщением
        @ObservationIgnored var botShown = false
        /// План в этом ходе уже менялся (первое «добавить пункт» в ходе начинает план заново)
        @ObservationIgnored var planTouched = false
        /// Текст Lumen до вызова бота — уже сохранён отдельным сообщением над ответом бота
        @ObservationIgnored var flushed = ""

        init(_ c: Conversation) { conversation = c }
    }

    /// Разговор с идущим ходом: открытый, если в нём идёт ход, иначе любой
    var running: Conversation? { (conversation.flatMap { turns[$0.id] } ?? turns.values.first)?.conversation }
    func isRunning(_ id: String) -> Bool { turns[id] != nil }

    @ObservationIgnored private var sessions: [String: ClaudeSession] = [:]
    /// Идущие ходы ChatGPT — для «Стоп»
    @ObservationIgnored private var codexRuns: [String: CodexRun] = [:]
    /// Вопрос агента «можно?» — ждёт ответа человека (режимы «Спрашивать», «Принимать правки», «Авто», «План»)
    struct PendingPermission: Equatable {
        let conversationID: String
        let request: ClaudeEvent.PermissionRequest
    }
    /// Вопросы по разговорам: параллельные задачи не перебивают друг друга; виден вопрос открытого разговора
    private(set) var pendingPermissions: [String: PendingPermission] = [:]
    var pendingPermission: PendingPermission? {
        get { conversation.flatMap { pendingPermissions[$0.id] } }
        set { if let id = newValue?.conversationID ?? conversation?.id { pendingPermissions[id] = newValue } }
    }
    /// «Разрешать такое до конца разговора»: инструменты, на которые больше не спрашиваем
    @ObservationIgnored private var alwaysAllowed: [String: Set<String>] = [:]
    /// Режим, в котором сейчас живёт процесс разговора
    @ObservationIgnored private var sessionModes: [String: AgentMode] = [:]

    init(app: AppModel) {
        self.app = app
    }

    /// Журнал Claude Code по разговорам (последние 400 строк) и когда процесс подавал голос в последний раз
    private(set) var logs: [String: [ClaudeLog.Line]] = [:]
    private(set) var lastSign: [String: Date] = [:]
    /// Идёт инструмент (команда, чтение, позванный бот): тишина — это ожидание инструмента, а не API
    var toolRunning: [String: Bool] = [:]
    /// Что сейчас с надёжностью хода: «нет сети — жду», «повтор 1 из 2», «Claude повторяет запрос» (видно под перепиской)
    var retryNote: [String: String] = [:]
    /// Сколько раз Lumen сам повторяет ход Claude Code после сбоя сети или API, пока ответ не начался
    static let autoRetries = 2
    /// Сколько ждать, когда claude молчит не на инструменте (ждёт API), прежде чем прервать и повторить
    static let stallLimit: TimeInterval = 180
    /// Когда начался последний шаг хода — для живой строки «Запускает: … 12 с»
    private(set) var stepStarted: [String: Date] = [:]
    /// Что агент делает прямо сейчас (последний шаг идущего хода открытого разговора) и с какого времени.
    /// Время — с начала всего хода, а не шага: «сколько он уже работает» (Рома, 19.10)
    var liveStep: (step: AgentStep, since: Date)? {
        guard let c = conversation, let tr = turns[c.id], let s = tr.message?.steps.last else { return nil }
        return (s, tr.start)
    }

    /// С какого времени идёт ход открытого разговора (nil — ход не идёт)
    var turnStart: Date? { conversation.flatMap { turns[$0.id]?.start } }
    var openLog: [ClaudeLog.Line] { conversation.flatMap { logs[$0.id] } ?? [] }

    func appendLog(_ key: String, _ line: ClaudeLog.Line) {
        var keys = [key]
        // бот, позванный через @, работает в своей сессии — его журнал виден и в чате, откуда позвали
        if let t = turns.values.first(where: { $0.delegate == key }) { keys.append(t.conversation.id) }
        for k in keys {
            var l = logs[k] ?? []
            l.append(line)
            if l.count > 400 { l.removeFirst(l.count - 400) }
            logs[k] = l
            lastSign[k] = line.at
        }
    }

    /// Сколько секунд идущий ход открытого разговора молчит (nil — ход не идёт)
    func silence(now: Date = Date()) -> TimeInterval? {
        guard let c = conversation, let tr = turns[c.id] else { return nil }
        return now.timeIntervalSince(max(lastSign[c.id] ?? tr.start, tr.start))
    }

    /// Скрытое напоминание характера к сообщению (только Lumen в чате; у ботов — свой характер, у агента характера нет — Рома, 19.10)
    func styleReminder(_ c: Conversation) -> String {
        c.kind == .chat ? "\n\n" + app.persona.reminder : ""
    }

    /// Очередь, как в Claude Code: написанное во время ответа уходит само, когда ответ закончится
    struct Queued: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var attachments: [Attachment]
        /// Отправил сам Lumen (утро, «меня нет — реши сам»)
        var via: Via? = nil
    }

    // MARK: самостоятельная работа (Autonomy.swift)

    /// Модель на этот ход вместо выбранной (у выбранной кончился лимит) и пояснение для человека
    var modelOverride: [String: ChatModel] = [:]
    var modelNote: [String: String] = [:]
    /// Фоновые задачи агента по разговорам: субагенты, исследования, команды в терминале (BackgroundTasks.swift)
    var backgroundTasks: [String: [BackgroundJob]] = [:]
    /// Фоновые задачи открытого разговора
    var openBackgroundTasks: [BackgroundJob] { conversation.flatMap { backgroundTasks[$0.id] } ?? [] }
    /// Сколько раз подряд Lumen ответил за отошедшего человека «реши сам» — не больше трёх, дальше ждём его
    @ObservationIgnored var autoContinues: [String: Int] = [:]
    /// Разговоры агента, которые работали этой ночью: утром им — «заверши и напиши отчёт»
    @ObservationIgnored var nightConversations: Set<String> = []
    /// Ждём сброса лимита, чтобы продолжить (ночью)
    @ObservationIgnored var limitWaits: [String: Task<Void, Never>] = [:]
    private(set) var queue: [String: [Queued]] = [:]
    /// Очередь открытого разговора
    var openQueue: [Queued] { conversation.flatMap { queue[$0.id] } ?? [] }
    /// «Сейчас»: после остановки сразу отправить первое из очереди
    @ObservationIgnored private var sendAfterStop: Set<String> = []

    func unqueue(_ id: UUID) {
        guard let c = conversation else { return }
        queue[c.id]?.removeAll { $0.id == id }
    }

    /// Остановить ответ и сразу отправить это сообщение из очереди
    func sendNow(_ id: UUID) {
        guard let c = conversation, var q = queue[c.id], let i = q.firstIndex(where: { $0.id == id }) else { return }
        q.insert(q.remove(at: i), at: 0)
        queue[c.id] = q
        if turns[c.id] != nil {
            sendAfterStop.insert(c.id)
            stop(c.id)
        } else {
            dispatchQueue(c.id, stopped: false)
        }
    }

    /// Разговор затих в приложении Claude — отправить, что ждало в очереди (ChatView проверяет раз в 3 с)
    func claudeWentIdle(_ id: String) {
        guard turns[id] == nil, !app.claudeBusy(id) else { return }
        // ход в приложении Claude кончился — план уходит целиком
        clearPlan(id)
        guard queue[id]?.isEmpty == false else { return }
        dispatchQueue(id, stopped: false)
    }

    /// Ход кончился — следующее из очереди. После «Стоп» очередь ждёт (кроме «Сейчас»).
    private func dispatchQueue(_ id: String, stopped: Bool) {
        let now = sendAfterStop.remove(id) != nil
        guard !stopped || now, var q = queue[id], !q.isEmpty, turns[id] == nil,
              let c = app.conversations.first(where: { $0.id == id }) ?? (conversation?.id == id ? conversation : nil) else { return }
        let next = q.removeFirst()
        queue[id] = q.isEmpty ? nil : q
        begin(c, text: next.text, attachments: next.attachments, isNew: false, via: next.via)
    }

    private var openTurn: Turn? { conversation.flatMap { turns[$0.id] } }
    /// Ход идёт в открытом разговоре
    var busy: Bool { openTurn != nil }
    var streaming: ChatMessage? { openTurn?.message }
    var thinking: Bool { openTurn?.thinking ?? false }
    /// Ответа ещё нет, потому что claude только запускается
    var launching: Bool { (openTurn?.thinking ?? false) && (openTurn?.launching ?? false) }
    /// Чей ответ идёт в открытом разговоре
    var turnBot: String? { openTurn?.bot }
    private func isStopped(_ c: Conversation) -> Bool { turns[c.id]?.stopRequested ?? false }
    /// Сфера: думает, пока идёт хоть один ход
    private func settleOrb() { if turns.isEmpty { app.orb = .idle } }

    // MARK: открыть / новый

    func open(_ c: Conversation) {
        guard conversation?.id != c.id else { return }
        var c = c
        // в списке слева у разговора план мог остаться старым: идущий ход знает свежий. Без этого план «сбрасывался»,
        // если уйти в другой чат и вернуться, пока агент работает (Рома, 19.10)
        if let tr = turns[c.id] { c.plan = tr.conversation.plan }
        conversation = c
        messages = (try? app.store.messages(in: c.id)) ?? []
    }

    /// Разговор догнал Claude Code (ImportClaude.swift): новые сообщения на экран; сессия claude сменилась — тёплый процесс не годится
    func caughtUp(_ c: Conversation, sessionChanged: Bool) {
        if sessionChanged {
            sessions[c.id]?.close()
            sessions[c.id] = nil
        }
        guard conversation?.id == c.id else { return }
        conversation = c
        reloadMessages()
    }

    func moved(_ id: String, _ projectID: String?) {
        if conversation?.id == id { conversation?.projectID = projectID }
        turns[id]?.conversation.projectID = projectID
        promptChanged(conversationID: id)
    }

    /// Инструкции или файлы проекта поменялись — процессы его разговоров гасим, следующий ход возьмёт новый промпт
    func promptChanged(projectID: String? = nil, conversationID: String? = nil, all: Bool = false, except: String? = nil) {
        for (id, s) in sessions where id != except {
            let pid = id == conversation?.id ? conversation?.projectID : app.conversations.first { $0.id == id }?.projectID
            guard all || id == conversationID || (projectID != nil && pid == projectID) else { continue }
            // идущий ход не обрываем — процесс перезапустится сразу после ответа
            if turns[id] != nil { stalePrompt.insert(id); continue }
            s.close()
            sessions[id] = nil
        }
    }
    /// Разговоры, чей процесс claude живёт со старыми инструкциями — закрыть, когда ответ закончится
    @ObservationIgnored private var stalePrompt: Set<String> = []

    /// Обновить открытый разговор (бот поменял папку или «сколько думать»)
    func refresh(_ c: Conversation) {
        if conversation?.id == c.id { conversation = c }
    }

    func renamed(_ id: String, _ title: String) {
        if conversation?.id == id { conversation?.title = title }
        turns[id]?.conversation.title = title
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

    /// К чему откатить сессию claude перед следующим ходом
    @ObservationIgnored private var rewindAt: [String: String] = [:]
    /// Куда прокрутить переписку (оглавление глав)
    var scrollTarget: Int64?

    /// «Повторить» у ошибки и «Попробовать снова» у ответа: ответ и всё после него убираются, вопрос уходит заново
    func retry(_ answer: ChatMessage) {
        guard let i = messages.firstIndex(where: { $0.id == answer.id }),
              let u = messages[..<i].last(where: { $0.role == .user }), let c = conversation else { return }
        // прежний ответ не стирается: он и его варианты листаются у нового (‹ 1/3 ›), как в Claude
        let old = (answer.alternates ?? []) + (answer.error == nil || !answer.text.isEmpty ? [AnswerVariant(answer)] : [])
        pendingVariants[c.id] = old
        resend(from: u, text: u.text)
    }

    /// Что сейчас делает бот, которого позвали из этого разговора
    var liveWork: [String: LiveWork] = [:]

    /// Прежние ответы, которые станут вариантами следующего ответа в разговоре
    private var pendingVariants: [String: [AnswerVariant]] = [:]

    /// Доступ к другим папкам у начатой задачи поменялся — процесс поднимется заново с новыми --add-dir
    func setExtraPaths(_ paths: [String]) {
        guard var c = conversation else { return }
        c.extraPaths = paths
        try? app.store.save(c)
        conversation = c
        if !busy { sessions[c.id]?.close(); sessions[c.id] = nil }
    }

    /// Ещё папки (и файлы) для агента: папки — доступом рядом с рабочей, файлы — вложением в поле
    func addPaths(_ urls: [URL]) -> [URL] {
        let dirs = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let files = urls.filter { !dirs.contains($0) }
        if !dirs.isEmpty {
            if var c = conversation {
                var extra = c.extraPaths ?? []
                for d in dirs where d.path != c.folder && !extra.contains(d.path) { extra.append(d.path) }
                c.extraPaths = extra
                try? app.store.save(c)
                conversation = c
                // процесс claude запущен без этих папок — поднимется заново с --resume
                if !busy { sessions[c.id]?.close(); sessions[c.id] = nil }
            } else {
                // новая задача: первая папка — рабочая (если ещё не выбрана своя), остальные — рядом
                var rest = dirs
                if app.agentFolder == nil || app.agentFolder.map(AppModel.isHome) == true { app.agentFolder = rest.removeFirst() }
                for d in rest where !app.agentExtraDirs.contains(d) && d != app.agentFolder { app.agentExtraDirs.append(d) }
            }
            dirs.forEach(app.rememberFolder)
        }
        return files
    }

    /// «Изменить» и «Попробовать снова»: разговор откатывается к этому сообщению (в базе и в сессии claude —
    /// модель тоже забывает, что было после), и вопрос уходит заново — изменённый или тот же
    func resend(from user: ChatMessage, text: String) {
        guard !busy, var c = conversation, let i = messages.firstIndex(where: { $0.id == user.id }) else { return }
        let earlier = Array(messages[..<i])
        for m in messages[i...] { if let id = m.id { try? app.store.deleteMessage(id) } }
        messages.removeSubrange(i...)
        if c.usesCLI && !c.model.isGPT {
            sessions[c.id]?.close()
            sessions[c.id] = nil
            let mine = earlier.filter { $0.role == .assistant && ($0.botID == nil || c.kind == .bot) }
            if let anchor = mine.last(where: { $0.cliAnchor != nil && $0.error == nil })?.cliAnchor {
                rewindAt[c.id] = anchor
            } else if mine.isEmpty {
                // откат к самому началу — новая сессия
                c.cliSessionID = UUID().uuidString.lowercased()
                try? app.store.save(c)
                conversation = c
            }
        }
        send(text, attachments: user.attachments)
    }

    /// В группе: щелчок по участнику — «@id » в поле ввода
    var mentionRequest: String?
    func mention(_ id: String) { mentionRequest = "@\(id) " }

    /// Глава: сообщение попадает в оглавление разговора
    func toggleChapter(_ m: ChatMessage) {
        guard let i = messages.firstIndex(where: { $0.id == m.id }) else { return }
        messages[i].chapter.toggle()
        _ = try? app.store.save(messages[i])
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
        guard let p = pendingPermission else { return }
        guard let s = sessions[p.conversationID] else { pendingPermissions[p.conversationID] = nil; return }
        if allow && always { alwaysAllowed[p.conversationID, default: []].insert(p.request.tool) }
        s.respond(p.request.id, allow: allow, inputJSON: p.request.inputJSON, message: message)
        pendingPermissions[p.conversationID] = nil
        if turns[p.conversationID] != nil { app.orb = .thinking }
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
        guard !text.isEmpty || !attachments.isEmpty else { return }
        // человек сам написал — счёт ответов «реши сам» за него с нуля
        if let c = conversation { autoContinues[c.id] = nil }
        // группа уже отвечает — сообщение в комнату, раунды начнутся заново с ним после текущего бота
        if busy, let c = conversation, c.kind == .group, let tr = turns[c.id] {
            var u = ChatMessage(conversationID: c.id, role: .user, text: text)
            u.attachments = attachments
            if let saved = try? app.store.save(u) { messages.append(saved) }
            tr.newInput = true
            return
        }
        // идёт ответ (здесь или в приложении Claude) — в очередь
        if let c = conversation, busy || app.claudeBusy(c.id) {
            queue[c.id, default: []].append(Queued(text: text, attachments: attachments))
            return
        }
        var c: Conversation
        if let existing = conversation {
            c = existing
        } else if app.tab == .agent {
            guard let folder = app.agentFolder else { return }
            c = Conversation(title: Self.title(from: text.isEmpty ? attachments.first?.name ?? "Вложение" : text), kind: .agent, folder: folder.path, backend: app.prefs.backend,
                             model: app.defaultAgentModel, effort: app.prefs.agentEffort ?? .high)
            c.mode = app.prefs.agentMode
            if !app.agentExtraDirs.isEmpty { c.extraPaths = app.agentExtraDirs.map(\.path); app.agentExtraDirs = [] }
            app.rememberFolder(folder)
        } else {
            c = Conversation(title: Self.title(from: text.isEmpty ? attachments.first?.name ?? "Вложение" : text), backend: app.prefs.backend, model: app.prefs.model, effort: app.prefs.effort)
        }
        if conversation == nil { c.projectID = newProjectID }
        // ChatGPT идёт по подписке ChatGPT, не по ключу Anthropic
        if c.model.isGPT { c.backend = .subscription }
        begin(c, text: text, attachments: attachments, isNew: conversation == nil)
    }

    /// Начать ход в разговоре — открытом или (из очереди) в том, куда человек уже не смотрит
    func begin(_ conv: Conversation, text: String, attachments: [Attachment], isNew: Bool, via: Via? = nil) {
        var c = conv
        if c.kind == .agent, app.prefs.night.active() { nightConversations.insert(c.id) }
        let open = isNew || conversation?.id == c.id
        if c.usesCLI && c.cliSessionID == nil { c.cliSessionID = UUID().uuidString.lowercased() }
        do {
            try app.store.save(c)
            var u = ChatMessage(conversationID: c.id, role: .user, text: text)
            u.attachments = attachments
            u.via = via
            let user = try app.store.save(u)
            if open {
                conversation = c
                messages.append(user)
            }
        } catch {
            return
        }
        if isNew { app.reloadConversations() }
        // «@tester …» в обычном чате — задачу выполняет бот, ответ приходит сюда же (техплан §4.6)
        let delegate = c.kind == .bot || c.kind == .group ? nil : app.mention(in: text)

        let tr = Turn(c)
        tr.bot = delegate?.0.id ?? (c.kind == .bot ? c.botID : nil)
        turns[c.id] = tr
        if open { app.orb = .thinking }
        let history = open ? messages : ((try? app.store.messages(in: c.id)) ?? [])
        // позванный бот (Lumen сам позвал через delegate, или бот позвал бота) — что он делает, видно в чате
        Task { [weak self] in
            var delegateConv: String?
            while let self, self.turns[c.id] === tr {
                if delegateConv == nil, let d = tr.delegate, let b = self.app.bot(d) { delegateConv = self.app.botConversation(for: b).id }
                let ids = [c.id] + (delegateConv.map { [$0] } ?? [])
                let found = ids.lazy.compactMap { id in (try? Data(contentsOf: self.app.paths.liveWork(id))).flatMap { try? JSONDecoder().decode(LiveWork.self, from: $0) } }.first
                if self.liveWork[c.id] != found {
                    self.liveWork[c.id] = found
                    // пока бот пишет — сторож молчания не считает это тишиной
                    if found != nil { self.lastSign[c.id] = Date() }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            self?.liveWork[c.id] = nil
        }
        tr.task = Task { [weak self] in
            guard let self else { return }
            if c.kind == .group {
                await self.runGroup(c, attachments: attachments)
            } else if let (bot, task) = delegate {
                await self.runDelegation(c, bot: bot, task: task, attachments: attachments)
            } else if c.model.isGPT {
                await self.runCodex(c, text: self.unseenContext(history, c) + text + self.styleReminder(c), attachments: attachments)
            } else if c.usesCLI {
                // после своего сжатия — свежая сессия claude: первым скрытым сообщением идёт записка-передача
                let handoff = self.pendingHandoff(c.id)
                await self.runCLI(c, text: (handoff.map(Handoff.prefix) ?? "") + self.unseenContext(history, c) + text
                                  + self.styleReminder(c) + self.autonomyNote(c), attachments: attachments,
                                  hadTurnsBefore: handoff == nil && history.contains { $0.role == .assistant && $0.error == nil && ($0.botID == nil || c.kind == .bot) })
                if handoff != nil, (try? self.app.store.messages(in: c.id))?.last?.error == nil { self.clearHandoff(c.id) }
            } else {
                await self.runAPI(c, history: history)
            }
            let stopped = tr.stopRequested
            self.turns[c.id] = nil
            self.clearPlan(c.id)
            if self.stalePrompt.remove(c.id) != nil {
                self.sessions[c.id]?.close()
                self.sessions[c.id] = nil
            }
            self.settleOrb()
            self.app.reloadConversations()
            // сжать окно, ответить «реши сам», если человек отошёл, ночью — дождаться лимита (Autonomy.swift)
            if c.usesCLI, delegate == nil { await self.afterTurn(c, stopped: stopped) }
            self.dispatchQueue(c.id, stopped: stopped)
        }
    }

    // MARK: группа ботов (как в Hermes Agent: раунды по кругу, «(pass)», @ — кто отвечает)

    private func runGroup(_ c: Conversation, attachments: [Attachment]) async {
        guard var g = app.group(c.groupID), let cli = app.cli else {
            await finish(c, text: "", error: app.cli == nil ? "Claude Code не найден." : "Группа не найдена.")
            return
        }
        let members = app.groupMembers(g)
        guard !members.isEmpty else { await finish(c, text: "", error: "В группе нет ботов — добавь их в настройках группы."); return }
        var sent = 0
        // человек написал посреди раундов — начинаем раунды заново с его сообщением
        repeat {
        turns[c.id]?.newInput = false
        sent = 0
        rounds: for round in 0..<BotGroup.maxRounds {
            let start = (try? app.store.messages(in: c.id)) ?? []
            let speakers = GroupRoom.rotate(GroupRoom.responders(log: start, members: members), round: round)
            let addressed = round == 0 ? GroupRoom.addressed(log: start, members: members) : []
            var spoke = false
            for bot in speakers {
                if isStopped(c) || sent >= BotGroup.maxMessages || turns[c.id]?.newInput == true { break rounds }
                let log = (try? app.store.messages(in: c.id)) ?? []
                let delta = GroupRoom.delta(log, after: g.seen[bot.id], viewer: bot, userName: app.profile.name, members: members)
                guard !delta.isEmpty else { continue }
                let prompt = GroupRoom.prompt(group: g, viewer: bot, members: members, delta: delta)
                // вложения — только тому, кто видит их впервые
                let fresh = log.filter { ($0.id ?? 0) > (g.seen[bot.id] ?? 0) }.flatMap(\.attachments)
                var reply = await memberTurn(c, bot: bot, prompt: prompt, attachments: fresh, cli: cli, resume: g.seen[bot.id] != nil)
                g.seen[bot.id] = log.last?.id ?? 0
                if let r = reply, GroupRoom.isPass(r), addressed.contains(bot.id), !isStopped(c) {
                    reply = await memberTurn(c, bot: bot, prompt: GroupRoom.addressedNudge, attachments: [], cli: cli, resume: true)
                }
                if let r = reply, !GroupRoom.isPass(r) {
                    var m = ChatMessage(conversationID: c.id, role: .assistant, text: r.trimmingCharacters(in: .whitespacesAndNewlines), model: bot.model)
                    m.botID = bot.id
                    if let saved = try? app.store.save(m) {
                        if conversation?.id == c.id { messages.append(saved) }
                        g.seen[bot.id] = saved.id
                    }
                    sent += 1
                    spoke = true
                }
                g = app.saveGroup(g)
            }
            // раунд, где все промолчали, — комната затихла
            if !spoke { break }
        }
        } while turns[c.id]?.newInput == true && !isStopped(c)
        turns[c.id]?.message = nil
    }

    /// Ход одного участника: его процесс claude в этой группе; текст печатается в чат от его имени.
    /// «(pass)» на экран не попадает. nil — не ответил (ошибка, стоп).
    private func memberTurn(_ c: Conversation, bot: Bot, prompt: String, attachments: [Attachment], cli: ClaudeCLI, resume: Bool,
                            retried: Bool = false) async -> String? {
        guard let tr = turns[c.id] else { return nil }
        let mc = app.memberConversation(c, bot: bot)
        tr.bot = bot.id
        tr.thinking = true
        tr.message = nil
        tr.received = ""
        tr.delegate = mc.id
        defer { tr.delegate = nil }
        var text = ""
        var shown = false
        var result: ClaudeEvent.TurnResult?
        do {
            let session = try cliSession(for: mc, cli: cli, resume: resume)
            let turn = attachments.isEmpty ? try session.send(prompt)
                : try session.send(content: Attachment.userContent(text: prompt, attachments: attachments, agent: true))
            for await ev in turn {
                switch ev {
                case .textDelta(let t):
                    text += t
                    // пока это может оказаться «(pass)» — не показываем
                    let head = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !shown, BotGroup.pass.hasPrefix(head) || "pass".hasPrefix(head) { continue }
                    if !shown { shown = true; appendStreaming(text, c) } else { appendStreaming(t, c) }
                case .finished(let r): result = r
                default: break
                }
            }
            if result?.ok != true, !retried, (session.errorOutput + (result?.text ?? "")).localizedCaseInsensitiveContains("no conversation found") {
                sessions[mc.id] = nil
                return await memberTurn(c, bot: bot, prompt: prompt, attachments: attachments, cli: cli, resume: false, retried: true)
            }
        } catch {
            app.log("Участник @\(bot.id) не запустился: \(error.localizedDescription)", conversation: c)
            return nil
        }
        await drainReveal(c, instant: isStopped(c))
        tr.message = nil
        tr.received = ""
        guard result?.ok == true else {
            if !isStopped(c) { app.log("Участник @\(bot.id) не ответил: \(result?.text ?? "")", conversation: c) }
            sessions[mc.id] = nil
            return isStopped(c) && !text.isEmpty ? text : nil
        }
        return text.isEmpty ? (result?.text ?? "") : text
    }

    /// Lumen сам позвал бота (чат по ключу API): бот работает в своём разговоре, ответ уходит Lumen инструментом
    func askBot(_ raw: String, task: String, from c: Conversation) async -> String {
        let id = raw.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
        guard let bot = app.bot(id) else { return "Нет такого бота: @\(id). Есть: " + app.bots.map { "@\($0.id)" }.joined(separator: ", ") + "." }
        guard !task.isEmpty else { return "Пустая задача." }
        guard let cli = app.cli else { return "Claude Code не найден — бот не может работать." }
        let b = app.botConversation(for: bot)
        if turns[b.id] != nil { return "@\(bot.id) сейчас отвечает в своём разговоре." }
        let hadTurns = ((try? app.store.messages(in: b.id)) ?? []).contains { $0.role == .assistant && $0.error == nil }
        var asked = ChatMessage(conversationID: b.id, role: .user, text: task)
        asked.via = Via(conversationID: c.id, title: c.title)
        _ = try? app.store.save(asked)
        app.botRuns[bot.id] = c.title
        defer { app.botRuns[bot.id] = nil }
        turns[c.id]?.delegate = b.id
        defer { turns[c.id]?.delegate = nil }
        var answer = ""
        var result: ClaudeEvent.TurnResult?
        do {
            let session = try cliSession(for: b, cli: cli, resume: hadTurns)
            for await ev in try session.send(Via.modelText(task: task, from: "Lumen, разговор «\(c.title)»", context: "")) {
                switch ev {
                case .textDelta(let t): answer += t
                case .finished(let r): result = r
                default: break
                }
            }
        } catch {
            return "@\(bot.id) не запустился: \(error.localizedDescription)"
        }
        let ok = result?.ok == true
        let text = answer.isEmpty ? (result?.text ?? "") : answer
        var m = ChatMessage(conversationID: b.id, role: .assistant, text: text, model: bot.model, error: ok ? nil : Self.cliError(result?.text ?? ""))
        m.botID = bot.id
        _ = try? app.store.save(m)
        if !ok { sessions[b.id] = nil; return "@\(bot.id) не справился: \(text)" }
        // как при «@id …»: ответ бота — отдельным сообщением с его знаком (текст Lumen до вызова — над ним)
        flushPreText(c)
        var shown = ChatMessage(conversationID: c.id, role: .assistant, text: text, model: bot.model)
        shown.botID = bot.id
        if let saved = try? app.store.save(shown) {
            if conversation?.id == c.id { messages.append(saved) }
            turns[c.id]?.botShown = true
            return "Ответ @\(bot.id) человек уже видит в чате отдельным сообщением бота. Не повторяй, не пересказывай и не упоминай, "
                + "что он показан. Если есть что добавить по сути — одной-двумя фразами; если нечего — ответь пустым сообщением.\n\nЧто он ответил (для тебя):\n\(text)"
        }
        return "@\(bot.id) ответил:\n\(text)"
    }

    /// Ответы ботов, которых Lumen позвал сам (lumen-mcp пишет их в этот чат), — сразу на экран
    private func pullBotReplies(_ c: Conversation) {
        guard c.kind != .bot, let tr = turns[c.id] else { return }
        let all = (try? app.store.messages(in: c.id)) ?? []
        let fresh = all.filter { m in m.botID != nil && m.role == .assistant && m.createdAt >= tr.start
            && !messages.contains { $0.id == m.id } }
        guard !fresh.isEmpty else { return }
        // текст Lumen до вызова — своим сообщением над ответом бота; ответы бота переписываются под него
        if flushPreText(c) {
            for m in fresh {
                if let id = m.id { try? app.store.deleteMessage(id) }
                var copy = m
                copy.id = nil
                if let saved = try? app.store.save(copy), conversation?.id == c.id { messages.append(saved) }
            }
        } else if conversation?.id == c.id {
            messages += fresh
        }
        tr.botShown = true
    }

    /// Сохранить уже написанный текст хода отдельным сообщением (перед ответом бота). true — было что сохранить.
    @discardableResult
    private func flushPreText(_ c: Conversation) -> Bool {
        guard let tr = turns[c.id] else { return false }
        let pre = tr.received.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pre.isEmpty else { return false }
        tr.revealTask?.cancel()
        tr.revealTask = nil
        var m = ChatMessage(conversationID: c.id, role: .assistant, text: pre, model: c.model,
                            steps: c.kind == .chat ? (tr.message?.steps ?? []).filter(\.shownInChat) : (tr.message?.steps ?? []))
        m.attachments = tr.message?.attachments ?? []
        m.botID = tr.bot
        if let saved = try? app.store.save(m), conversation?.id == c.id { messages.append(saved) }
        tr.flushed += tr.received
        tr.received = ""
        tr.message = nil
        tr.needBreak = false
        return true
    }

    /// Что было в чате без Lumen: вопросы ботам через @ и их ответы шли в процессах ботов, сессия Lumen их не видела.
    /// Перед своим ходом Lumen получает это скрытым блоком — на экране его нет.
    func unseenContext(_ history: [ChatMessage], _ c: Conversation) -> String {
        guard c.kind != .bot, history.count > 1 else { return "" }
        let before = history.dropLast()
        let lastOwn = before.lastIndex { $0.role == .assistant && $0.botID == nil && $0.error == nil }
        let missed = before[(lastOwn.map { $0 + 1 } ?? before.startIndex)...]
        guard missed.contains(where: { $0.botID != nil }) else { return "" }
        let name = app.profile.name.isEmpty ? "Человек" : app.profile.name
        var lines: [String] = []
        for m in missed where m.error == nil {
            let files = m.attachments.isEmpty ? "" : " [вложения: \(m.attachments.map(\.name).joined(separator: ", "))]"
            if m.role == .user {
                lines.append("\(name): \(m.text.prefix(2000))\(files)")
            } else if let id = m.botID {
                let b = app.bot(id)
                // сделанные ботом файлы — с путями: агент сможет их открыть
                let made = m.attachments.isEmpty ? "" : "\n[файлы от бота: " + m.attachments.map { "\($0.name) — \($0.path)" }.joined(separator: "; ") + "]"
                lines.append("@\(id)\(b.map { " (\($0.name))" } ?? ""): \(m.text.prefix(6000))\(made)")
            }
        }
        var block = lines.joined(separator: "\n\n")
        if block.count > 16_000 { block = "…" + block.suffix(16_000) }
        return "<lumen-chat-context>\nПока ты не отвечал, в этом чате было (ботов звали через @, ты этого не видел):\n\n"
            + block + "\n</lumen-chat-context>\n\n"
    }

    /// Под ответом появился предложенный навык
    func attachSkillDraft(_ d: SkillDraft?, to messageID: Int64, conversationID: String) {
        guard var m = ((try? app.store.messages(in: conversationID)) ?? []).first(where: { $0.id == messageID }) else { return }
        m.skillDraft = d
        _ = try? app.store.save(m)
        if let i = messages.firstIndex(where: { $0.id == messageID }) { messages[i].skillDraft = d }
    }

    /// Карточки предложений Lumen под ответом: подключил / не надо
    func setProposals(_ list: [CustomizeProposal], messageID: Int64, conversationID: String) {
        guard var m = (try? app.store.messages(in: conversationID))?.first(where: { $0.id == messageID }) else { return }
        m.proposals = list
        _ = try? app.store.save(m)
        if let i = messages.firstIndex(where: { $0.id == messageID }) { messages[i].proposals = list }
    }

    /// Бот изменён — его процесс гасим, следующий ход поднимет его с новыми правами (`--resume`)
    func restart(_ id: String) {
        guard turns[id] == nil else { return }
        sessions[id]?.close()
        sessions[id] = nil
    }

    /// Задача боту из чужого чата: бот работает в своём постоянном разговоре (туда пишется задача и ответ),
    /// а ответ с его знаком появляется в этом чате.
    private func runDelegation(_ c: Conversation, bot: Bot, task: String, attachments: [Attachment] = []) async {
        guard let cli = app.cli else {
            await finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        let b = app.botConversation(for: bot)
        // у бота свой процесс: пока он отвечает в своём разговоре, второй ход туда не пустить
        if turns[b.id] != nil {
            await finish(c, text: "", error: "@\(bot.id) сейчас отвечает в своём разговоре. Позови его, когда закончит.")
            return
        }
        let earlier = (try? app.store.messages(in: b.id)) ?? []
        let hadTurns = earlier.contains { $0.role == .assistant && $0.error == nil }
        // в разговоре бота — твоё сообщение как есть и пометка «из чата …»; что было в том чате, бот получает скрыто
        let context = ((try? app.store.messages(in: c.id)) ?? []).dropLast().suffix(6).map { m -> String in
            let who = m.role == .user ? (app.profile.name.isEmpty ? "Человек" : app.profile.name) : (m.botID.map { "@\($0)" } ?? "Lumen")
            return "\(who): \(m.text.prefix(600))"
        }.joined(separator: "\n")
        let shownTask = task.isEmpty && attachments.isEmpty ? "@\(bot.id)" : task
        let modelTask = task.isEmpty
            ? (attachments.isEmpty ? "(Тебя позвали без задачи — поздоровайся коротко и спроси, чем помочь по твоей роли.)"
                                   : "(Задачи словами нет — посмотри вложения и скажи, что о них думаешь по своей роли.)")
            : task
        let taskText = Via.modelText(task: modelTask, from: c.title, context: context)
        var asked = ChatMessage(conversationID: b.id, role: .user, text: shownTask)
        asked.attachments = attachments
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
            turns[c.id]?.delegate = b.id
            defer { turns[c.id]?.delegate = nil }
            // картинки и файлы из сообщения — боту тоже
            let turn = attachments.isEmpty ? try session.send(taskText)
                : try session.send(content: Attachment.userContent(text: taskText, attachments: attachments, agent: true))
            if isStopped(c) { session.interrupt() }
            for await ev in turn {
                switch ev {
                case .textDelta(let t):
                    answer += appendStreaming(t, c)
                case .plan(let change):
                    // план бота виден в чате, откуда его позвали
                    updatePlan(change, c)
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
            let stopped = isStopped(c)
            let error = stopped ? nil : (ok ? nil : Self.cliError(result?.text ?? session.errorOutput))
            let text = answer.isEmpty ? (ok ? result?.text ?? "" : "") : answer
            // в постоянный разговор бота — весь ход
            var m = ChatMessage(conversationID: b.id, role: .assistant, text: text, model: b.model, stopped: stopped, error: error,
                                steps: turns[c.id]?.message?.steps ?? [], changes: changes)
            m.botID = bot.id
            _ = try? app.store.save(m)
            if !ok && !stopped { sessions[b.id] = nil }
            await finish(c, text: text, stopped: stopped, error: error, changes: changes)
        } catch {
            await finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// «Стоп»: подписка — сообщение `interrupt` процессу, API — обрыв соединения
    func stop(_ id: String? = nil) {
        guard let id = id ?? conversation?.id, let tr = turns[id] else { return }
        let c = tr.conversation
        tr.stopRequested = true
        if let p = pendingPermissions[c.id] {
            sessions[c.id]?.respond(p.request.id, allow: false, message: "Человек остановил задачу.")
            pendingPermissions[c.id] = nil
        }
        if let d = tr.delegate { sessions[d]?.interrupt() } else if c.model.isGPT { codexRuns[c.id]?.stop() } else if c.usesCLI { sessions[c.id]?.interrupt() } else { tr.task?.cancel() }
        // не послушался за 3 с — процесс закрываем: ход кончится, следующий продолжит разговор (--resume)
        let key = tr.delegate ?? c.id
        Task { [weak self, weak tr] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let tr, self.turns[id] === tr else { return }
            self.app.log("«Стоп» не сработал за 3 с — закрываю процесс", conversation: c)
            self.sessions[key]?.close()
            self.sessions[key] = nil
        }
    }

    /// «Сжать разговор»: своё сжатие — агент пишет записку-передачу, дальше свежая сессия (Autonomy.swift).
    /// Не вышло — как раньше, `/compact` у самого claude
    func compact() {
        guard let c = conversation, c.usesCLI, !busy else { return }
        Task {
            // остановили — ничего не делать; не вышло — сжать силами claude
            if let done = await handoffCompact(c), !done { compactByClaude(c) }
        }
    }

    /// `/compact` у claude: он пересказывает старое и освобождает окно (проверено в спайке)
    func compactByClaude(_ c: Conversation) {
        guard c.usesCLI, turns[c.id] == nil, let cli = app.cli else { return }
        turns[c.id] = Turn(c)
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
            turns[c.id] = nil
            settleOrb()
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
        if turns[id] != nil { stop(id) }
        sessions[id]?.close()
        sessions[id] = nil
        if conversation?.id == id { startNew() }
    }

    /// Поменялись коннекторы или хуки — гасим процессы без хода, следующий ход поднимет их с новыми (`--resume`)
    func restartIdle() {
        for id in Array(sessions.keys) where turns[id] == nil {
            sessions[id]?.close()
            sessions[id] = nil
        }
    }

    /// Выход из приложения: погасить все процессы claude
    func closeAll() {
        for s in sessions.values { s.close() }
        sessions.removeAll()
    }

    private func runCLI(_ c: Conversation, text: String, attachments: [Attachment] = [], hadTurnsBefore: Bool, retried: Bool = false,
                        attempt: Int = 0) async {
        // нет сети — не падать сразу: подождать до 2 минут, вдруг Wi‑Fi вернётся
        if !app.online {
            retryNote[c.id] = "Нет сети — отправлю, как только появится"
            let until = Date().addingTimeInterval(120)
            while !app.online, Date() < until, !isStopped(c) { try? await Task.sleep(for: .seconds(1)) }
            retryNote[c.id] = nil
            if isStopped(c) { await finish(c, text: "", stopped: true); return }
        }
        guard let cli = app.cli else {
            await finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        // у выбранной модели кончился лимит на неделю — ход ответит следующая по силе (автовыбор модели)
        if !retried { chooseModel(c) }
        // вход в сайты коннекторов продлевается до хода; продлили — процесс поднимется с новым токеном (--resume)
        if await app.freshenOAuth(app.connectorsFor(c)) { restart(c.id) }
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
            // «Стоп» нажали, пока ход готовился (вход в коннекторы, запуск claude) — процесса ещё не было
            if isStopped(c) {
                await finish(c, text: "", stopped: true)
                return
            }
            let turn = attachments.isEmpty ? try session.send(text)
                : try session.send(content: Attachment.userContent(text: text, attachments: attachments, agent: c.kind != .chat || c.projectID != nil))
            if isStopped(c) { session.interrupt() }
            // сторож: claude молчит не на инструменте (значит, ждёт API) дольше stallLimit — прервать, потом повторить.
            // Команды считаются поштучно: при нескольких сразу одна закончилась — остальные ещё идут (Рома, 19.10:
            // команда ждала блокировку, а Lumen писал «ждёт ответа API» и на третьей минуте прерывал её).
            // Любой вывод claude (и размышление) — признак жизни.
            var openTools = 0
            var stalled = false
            let watchdog = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, self.turns[c.id] != nil else { return }
                    if session.lastOutput > (self.lastSign[c.id] ?? .distantPast) { self.lastSign[c.id] = session.lastOutput }
                    let quiet = Date().timeIntervalSince(max(self.lastSign[c.id] ?? .distantPast, self.turns[c.id]?.start ?? Date()))
                    if openTools == 0, self.pendingPermissions[c.id] == nil, quiet > Self.stallLimit {
                        stalled = true
                        self.app.log("claude молчит \(Int(quiet)) с без инструмента — прерываю ход", conversation: c)
                        session.interrupt()
                        return
                    }
                }
            }
            defer { watchdog.cancel() }
            for await ev in turn {
                switch ev {
                case .started:
                    // claude поднялся (навыки и коннекторы загружены) — дальше ждём ответ модели
                    turns[c.id]?.launching = false
                case .textDelta(let t):
                    if openTools == 0 { toolRunning[c.id] = nil }
                    retryNote[c.id] = nil
                    answer += appendStreaming(t, c)
                case .step(let step):
                    openTools += 1
                    toolRunning[c.id] = true
                    retryNote[c.id] = nil
                    appendStep(step, c)
                case .retry(let n, let err):
                    // claude сам повторяет запрос к API — показать, что не завис
                    retryNote[c.id] = "Claude повторяет запрос к API (\(n))" + (err.isEmpty ? "" : " — " + String(err.prefix(80)))
                case .anchor(let a):
                    turns[c.id]?.anchor = a
                case .toolDone:
                    openTools = max(0, openTools - 1)
                    if openTools == 0 { toolRunning[c.id] = nil }
                    // позванный Lumen бот ответил — его сообщение уже в базе
                    pullBotReplies(c)
                case .plan(let change):
                    updatePlan(change, c)
                case .permission(let req):
                    // разрешено «до конца разговора» — не спрашиваем снова
                    if alwaysAllowed[c.id]?.contains(req.tool) == true {
                        session.respond(req.id, allow: true, inputJSON: req.inputJSON)
                    } else {
                        pendingPermissions[c.id] = PendingPermission(conversationID: c.id, request: req)
                        if conversation?.id == c.id { app.orb = .idle }
                        // человек отошёл или спит — не ждать его вечно (Autonomy.swift)
                        watchPermission(c, req, session)
                    }
                case .finished(let r):
                    result = r
                default: break
                }
            }
            pendingPermissions[c.id] = nil
            toolRunning[c.id] = nil
            watchdog.cancel()
            retryNote[c.id] = nil
            // сбой сети или API, а ответ ещё не начался (ни слова, ни шага) — повторить самим, без дублей в сессии
            let nothingDone = answer.isEmpty && (turns[c.id]?.message?.steps.isEmpty ?? true)
            let failure: String?
            if stalled { failure = "stall" } else if let r = result { failure = r.ok ? nil : r.text } else { failure = session.errorOutput }
            if let failure, nothingDone, !isStopped(c), attempt < Self.autoRetries, stalled || Self.transient(failure) {
                await autoRetry(c, text: text, attachments: attachments, hadTurnsBefore: hadTurnsBefore, attempt: attempt + 1,
                                why: stalled ? "Claude не отвечал \(Int(Self.stallLimit / 60)) мин" : "Сбой связи с API")
                return
            }
            if stalled {
                await finish(c, text: answer, error: "Claude Code не отвечал \(Int(Self.stallLimit / 60)) мин и был прерван. Нажми «Повторить».")
                return
            }
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
            if isStopped(c) {
                await finish(c, text: answer, stopped: true, changes: changes, context: ctx)
            } else if result.ok {
                await finish(c, text: answer.isEmpty ? result.text : answer, changes: changes, context: ctx)
            } else {
                // лимит у этой модели кончился — сразу ответить другой, у которой он есть (автовыбор модели)
                let failure = result.text.isEmpty ? session.errorOutput : result.text
                if !retried, answer.isEmpty, await switchModelAfterLimit(c, failure) {
                    await runCLI(c, text: text, attachments: attachments, hadTurnsBefore: hadTurnsBefore, retried: true)
                    return
                }
                app.log("claude ответил ошибкой: \(result.text)\nstderr:\n\(session.errorOutput)", conversation: c)
                await finish(c, text: answer, error: Self.cliError(result.text.isEmpty ? session.errorOutput : result.text), changes: changes, context: ctx)
            }
        } catch {
            await finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// Повтор хода после сбоя: сессия откатывается к последнему хорошему ответу (claude забывает неудачный вопрос),
    /// пауза растёт, без сети — ждём её
    private func autoRetry(_ c: Conversation, text: String, attachments: [Attachment], hadTurnsBefore: Bool, attempt: Int, why: String) async {
        var c = c
        let wait = attempt == 1 ? 3 : 10
        app.log("\(why) — повтор \(attempt) из \(Self.autoRetries) через \(wait) с", conversation: c)
        for left in stride(from: wait, to: 0, by: -1) {
            retryNote[c.id] = "\(why) — повтор \(attempt) из \(Self.autoRetries) через \(left) с"
            try? await Task.sleep(for: .seconds(1))
            if isStopped(c) { retryNote[c.id] = nil; await finish(c, text: "", stopped: true); return }
        }
        retryNote[c.id] = "\(why) — повторяю (\(attempt) из \(Self.autoRetries))"
        sessions[c.id]?.close()
        sessions[c.id] = nil
        var resume = hadTurnsBefore
        if hadTurnsBefore {
            let earlier = ((try? app.store.messages(in: c.id)) ?? []).filter { $0.role == .assistant && $0.error == nil && ($0.botID == nil || c.kind == .bot) }
            if let anchor = earlier.last(where: { $0.cliAnchor != nil })?.cliAnchor { rewindAt[c.id] = anchor }
        } else {
            // первый ход не удался — начать с чистой сессии
            c.cliSessionID = UUID().uuidString.lowercased()
            try? app.store.save(c)
            turns[c.id]?.conversation.cliSessionID = c.cliSessionID
            if conversation?.id == c.id { conversation?.cliSessionID = c.cliSessionID }
            resume = false
        }
        await runCLI(c, text: text, attachments: attachments, hadTurnsBefore: resume, attempt: attempt)
    }

    /// Сбой, который стоит повторить: сеть, DNS, обрыв, перегрузка, 5xx, процесс умер молча
    static func transient(_ raw: String) -> Bool {
        let s = raw.lowercased()
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return ["enotfound", "econnreset", "econnrefused", "etimedout", "eai_again", "socket hang up", "fetch failed",
                "can't reach", "cannot reach", "connection error", "network", "timed out", "timeout", "overloaded",
                "internal server error", "bad gateway", "service unavailable",
                "api error: connection", "premature close", "terminated"].contains { s.contains($0) }
            // коды ответа — отдельным числом, а не куском другого («250000 tokens» — не 500)
            || s.range(of: #"\b(500|502|503|504|529)\b"#, options: .regularExpression) != nil
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
                    answer += appendStreaming(t, c)
                case .step(let step):
                    appendStep(step, c)
                case .anchor(let a):
                    turns[c.id]?.anchor = a
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
            if isStopped(c) {
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
        let model = effectiveModel(c)
        if let s = sessions[c.id], s.isRunning, s.config.model == model.rawValue, s.config.effort == c.effort.rawValue {
            // режим меняется на ходу, без перезапуска (ночью — обход разрешений)
            if c.kind == .agent, let mode = effectiveMode(c), sessionModes[c.id] != mode {
                s.setMode(mode.rawValue)
                sessionModes[c.id] = mode
            }
            return s
        }
        sessions[c.id]?.close()
        turns[c.id]?.launching = true
        // не больше трёх живых процессов: старые гасим, их ход продолжится через --resume
        // гасим только простаивающие: идущий ход в другом разговоре не трогаем
        if sessions.count >= 3, let oldest = sessions.keys.first(where: { $0 != c.id && turns[$0] == nil }) {
            sessions[oldest]?.close()
            sessions[oldest] = nil
        }
        let sid = c.cliSessionID ?? UUID().uuidString.lowercased()
        let resumeAt = rewindAt.removeValue(forKey: c.id)
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
            let mode = effectiveMode(c) ?? app.prefs.agentMode
            config = .agent(model: model.rawValue, effort: c.effort.rawValue, persona: app.agentPrompt(for: c),
                            folder: URL(fileURLWithPath: folder), sessionID: sid, resume: resume, mode: mode.rawValue)
            sessionModes[c.id] = mode
            config.addDirs = (c.extraPaths ?? []).filter { FileManager.default.fileExists(atPath: $0) }
            // страж готовности: не даёт закончить, пока не проверено сделанное (Рома, 19.10)
            app.syncGuardFlag()
            config.guardCommand = app.guardCommand
            // агент по ключу: тот же claude, но платит ключ (§2.4 техплана)
            if c.backend == .api, let key = app.keychain.read(Keychain.anthropicKey) { config.extraEnv["ANTHROPIC_API_KEY"] = key }
        } else {
            // у чата своя папка для временного (а не «/», откуда запущено приложение)
            config = .init(model: model.rawValue, effort: c.effort.rawValue, systemPrompt: app.systemPrompt(for: c),
                           tools: [], userSettings: false, sessionID: sid, resume: resume, cwd: app.chatFolder(c))
        }
        // перегрузка или недоступность модели — claude сам ответит запасной (автовыбор модели)
        if bot == nil, app.prefs.autoModel { config.fallbackModels = ModelChoice.chain(after: model).prefix(2).map(\.rawValue) }
        // память: lumen-mcp с инструментами remember и recall
        if let mcp = try? app.writeMCPConfig(for: c, memoryReadOnly: bot.map { !$0.can.contains(.memory) } ?? false) {
            config.mcpConfig = mcp.path
            // у бота разрешённое уже посчитано в BotPermissions
            if bot == nil {
                config.allowedTools += ["mcp__lumen__remember", "mcp__lumen__recall", "mcp__lumen__load_skill", "mcp__lumen__read_skill_file", "mcp__lumen__add_to_project",
                                        "mcp__lumen__list_skills", "mcp__lumen__create_skill", "mcp__lumen__find_skills", "mcp__lumen__install_skill"]
                    + CustomizeAdmin.names.sorted().map { "mcp__lumen__\($0)" }
                    + BrowserTools.names.map { "mcp__lumen__\($0)" }
                // включённые коннекторы — без вопросов: их подключил сам человек
                config.allowedTools += app.connectorsFor(c).map { "mcp__\($0.name)" }
                // Lumen сам зовёт ботов (delegate): бот может работать минутами
                if !app.bots.isEmpty {
                    config.allowedTools.append("mcp__lumen__delegate")
                    config.extraEnv["MCP_TOOL_TIMEOUT"] = "900000"
                }
            }
        }
        // инструменты коннекторов — по требованию (ToolSearch): иначе их описания целиком лежат в контексте
        // (Notion и Playwright — десятки тысяч токенов на пустой чат)
        if !app.connectorsFor(c).isEmpty, let t = config.tools, !t.contains("ToolSearch") {
            config.tools = t + ["ToolSearch"]
            config.allowedTools.append("ToolSearch")
        }
        // секреты коннекторов — в окружение claude, в файлах их нет
        config.extraEnv.merge(app.secretValues(for: app.connectorsFor(c).map(\.server))) { a, _ in a }
        // хуки из «Кастомизации»
        config.settings = app.hooksSettingsFile()?.path
        if resume { config.resumeAt = resumeAt }
        let s = try ClaudeSession(cli: cli, config: config)
        let key = c.id
        s.onLog = { [weak self] line in Task { @MainActor in self?.appendLog(key, line) } }
        // фоновые задачи агента: субагенты, исследования, команды (приходят и между ходами)
        s.onTask = { [weak self] event in Task { @MainActor in self?.applyTask(event, to: key) } }
        appendLog(key, ClaudeLog.Line(kind: .info, text: (resume ? "Продолжаю сессию " : "Новая сессия ") + String(sid.prefix(8)) + " · " + c.model.name))
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
        var tools = MemoryTools(store: app.store, conversationID: c.id, conversationTitle: c.title, skills: app.skillLibrary)
        tools.paths = app.paths
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
        request.tools = (MemoryTools.definitions + (tools.availableSkills.isEmpty ? [] : MemoryTools.skillDefinitions)
                         + (tools.project == nil ? [] : MemoryTools.projectDefinitions) + SkillAdmin.definitions + CustomizeAdmin.definitions).map {
            JSONBox(["name": $0.name, "description": $0.description, "input_schema": $0.schema, "strict": true])
        }
        // Lumen сам зовёт ботов — как delegate у lumen-mcp
        if !app.bots.isEmpty, c.kind != .bot {
            request.tools.append(JSONBox(["name": "delegate",
                "description": "Передать задачу боту Lumen и дождаться его ответа. Указывай задачу полностью: бот не видит этот разговор.",
                "input_schema": ["type": "object", "additionalProperties": false, "required": ["bot", "task"],
                                 "properties": ["bot": ["type": "string", "description": "id бота без @"],
                                                "task": ["type": "string", "description": "Что сделать, с нужным контекстом"]]]] as [String: Any]))
        }
        // коннекторы из «Кастомизации»: Lumen сам держит их клиенты (MCPPool), модель видит «сервер__инструмент»
        let wanted = app.connectorsFor(c)
        if !wanted.isEmpty {
            _ = await app.freshenOAuth(wanted)
            let problems = await app.mcpPool.prepare(wanted.map { ($0.name, $0.server.resolved(app.secretValues(for: [$0.server]))) })
            for p in problems { app.log("Коннектор не подключился: \(p)", conversation: c) }
            request.tools = (request.tools ?? []) + app.mcpPool.definitions(for: wanted.map(\.name))
        }
        var answer = ""
        // ход целиком (с вызовами инструментов) — чтобы в истории он повторился как был
        var turn: [[String: Any]] = []
        do {
            var api = AnthropicAPI(key: key)
            api.session = app.urlSession
            for _ in 0..<6 {
                var finished: (String, String)?
                let cid = c.id
                let stream = api.chat(request) { [weak self] n, why in
                    Task { @MainActor in self?.retryNote[cid] = "\(why) Повтор \(n) из \(AnthropicAPI.maxRetries)…" }
                }
                defer { retryNote[cid] = nil }
                for try await ev in stream {
                    if retryNote[cid] != nil { retryNote[cid] = nil }
                    switch ev {
                    case .textDelta(let t):
                        answer += appendStreaming(t, c)
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
                    let out: String
                    if name == "delegate" {
                        out = await askBot(input["bot"] as? String ?? "", task: input["task"] as? String ?? "", from: c)
                    } else if app.mcpPool.handles(name) {
                        out = await app.mcpPool.call(name, JSONBox(input))
                    } else if CustomizeAdmin.names.contains(name) {
                        out = await CustomizeAdmin.call(name, CustomizeAdmin.Args(input), paths: app.paths, conversationID: c.id, session: app.urlSession)
                    } else if SkillAdmin.names.contains(name) {
                        out = await SkillAdmin.call(name, SkillAdmin.Args(input), library: app.skillLibrary, session: app.urlSession)
                    } else {
                        out = (try? tools.call(name, input)) ?? "Ошибка памяти"
                    }
                    results.append(["type": "tool_result", "tool_use_id": call["id"] as? String ?? "", "content": out])
                }
                turn.append(["role": "user", "content": results])
                request.messages.append(["role": "assistant", "content": JSONBox(blocks)])
                request.messages.append(["role": "user", "content": JSONBox(results)])
            }
            await finish(c, text: answer, apiContent: Self.turnJSON(turn))
        } catch {
            await finish(c, text: answer, stopped: isStopped(c), error: isStopped(c) ? nil : error.localizedDescription)
        }
    }

    /// Один ход для истории: обычный — блоки ответа; с инструментами — вся цепочка в обёртке lumen_turn
    static func turnJSON(_ turn: [[String: Any]]) -> String? {
        let value: Any = turn.count == 1 ? (turn[0]["content"] ?? []) : [["lumen_turn": turn]]
        guard let d = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /// Текст хода: на экран — плавно; возвращает то, что добавилось (после инструмента — с нового абзаца)
    @discardableResult
    private func appendStreaming(_ t: String, _ c: Conversation) -> String {
        guard let tr = turns[c.id] else { return t }
        if tr.thinking {
            tr.thinking = false
            tr.launching = false
            if conversation?.id == c.id { app.orb = .writing }
        }
        if tr.message == nil { tr.message = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model); tr.message?.botID = tr.bot }
        lastSign[c.id] = Date()
        var chunk = t
        if tr.needBreak {
            tr.needBreak = false
            let head = t.drop { $0 == " " }
            if !tr.received.isEmpty && !tr.received.hasSuffix("\n\n") && !head.hasPrefix("\n") {
                chunk = (tr.received.hasSuffix("\n") ? "\n" : "\n\n") + t
            }
        }
        tr.received += chunk
        if tr.revealTask == nil {
            tr.revealTask = Task { @MainActor [weak tr] in
                while let tr, !Task.isCancelled {
                    let shown = tr.message?.text.count ?? 0
                    let backlog = tr.received.count - shown
                    if backlog > 0 {
                        // хвост догоняется примерно за 0,4 с, но не быстрее символа за кадр
                        let step = max(1, Int((Double(backlog) / 12).rounded(.up)))
                        tr.message?.text = String(tr.received.prefix(shown + step))
                    }
                    try? await Task.sleep(for: .milliseconds(30))
                }
            }
        }
        return chunk
    }

    /// Дождаться, пока печать догонит полученное (не дольше 1,5 с), и остановить её
    private func drainReveal(_ c: Conversation, instant: Bool) async {
        guard let tr = turns[c.id] else { return }
        if !instant {
            let deadline = Date().addingTimeInterval(1.5)
            while (tr.message?.text.count ?? 0) < tr.received.count, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        tr.revealTask?.cancel()
        tr.revealTask = nil
        if tr.message != nil { tr.message?.text = tr.received }
        tr.received = ""
    }

    private func updatePlan(_ change: PlanItem.Change, _ c: Conversation) {
        let fresh = turns[c.id].map { !$0.planTouched } ?? false
        turns[c.id]?.planTouched = true
        // новый пункт ждёт настоящий номер из ответа claude: у него нумерация сквозная на всю сессию, а план у нас
        // после каждого хода сбрасывается — своя нумерация с 1 давала «сделано» не в том пункте (19.10)
        let items = PlanItem.apply(change, to: (turns[c.id]?.conversation ?? c).plan, freshTurn: fresh, live: true)
        turns[c.id]?.conversation.plan = items
        if conversation?.id == c.id { conversation?.plan = items }
        // и в списке разговоров: оттуда план берётся, когда чат открывают снова
        if let i = app.conversations.firstIndex(where: { $0.id == c.id }) { app.conversations[i].plan = items }
        try? app.store.updatePlan(c.id, items)
        // панель сбоку сама не открывается: план и так виден в переписке (Рома, 18.10)
    }

    /// Ход кончился — план убираем целиком, даже с несделанными шагами. Новый план агент составит сам и вернёт его
    func clearPlan(_ id: String) {
        let hasPlan = conversation?.id == id ? conversation?.plan.isEmpty == false : false
        let stored = app.conversations.first { $0.id == id }?.plan.isEmpty == false
        guard hasPlan || stored else { return }
        if conversation?.id == id { conversation?.plan = [] }
        if let i = app.conversations.firstIndex(where: { $0.id == id }) { app.conversations[i].plan = [] }
        try? app.store.updatePlan(id, [])
    }

    /// Картинка или файл от агента — под идущий ответ (снимок браузера, show_in_chat). Бот, позванный через @, кладёт в чат, откуда позвали.
    @discardableResult
    func addShot(_ id: String, _ a: Attachment) -> Bool {
        guard let tr = turns[id] ?? turns.values.first(where: { $0.delegate == id }) else { return false }
        if tr.message == nil {
            tr.message = ChatMessage(conversationID: tr.conversation.id, role: .assistant, text: "", model: tr.conversation.model)
            tr.message?.botID = tr.bot
        }
        tr.message?.attachments.append(a)
        // файл, что сделал агент или бот, — в базу сразу: если ход повиснет или Lumen закроют, вложение не пропадёт
        if var m = tr.message {
            m.text = tr.received
            if let saved = try? app.store.save(m) { tr.message?.id = saved.id }
        }
        return true
    }

    private func appendStep(_ step: AgentStep, _ c: Conversation) {
        guard let tr = turns[c.id] else { return }
        if tr.thinking {
            tr.thinking = false
            tr.launching = false
            if conversation?.id == c.id { app.orb = .idle }
        }
        if tr.message == nil { tr.message = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model); tr.message?.botID = tr.bot }
        lastSign[c.id] = Date()
        stepStarted[c.id] = Date()
        // место шага — конец уже написанного: следующий текст начнётся новым абзацем после шагов
        var step = step
        step.at = tr.received.count
        tr.message?.steps.append(step)
        tr.needBreak = true
    }

    private func finish(_ c: Conversation, text: String, apiContent: String? = nil, stopped: Bool = false, error: String? = nil,
                        changes: ChangeSet? = nil, context: (Int, Int)? = nil) async {
        // ответ допечатывается до конца; «Стоп» и ошибки — сразу
        await drainReveal(c, instant: stopped || error != nil)
        let tr = turns[c.id]
        // уже сохранённое до ответа бота — не повторять
        var text = text
        if let f = tr?.flushed, !f.isEmpty, text.hasPrefix(f) {
            text = String(text.dropFirst(f.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error { app.log("Ошибка в разговоре: \(error)", conversation: c) }
        // шаги показываем у агента; в чате вызовы памяти видны плашками «Запомнил» и «Опирался на»
        // у агента и ботов шаги видны; в чате вызовы памяти видны плашками «Запомнил» и «Опирался на»
        let turnBot = tr?.bot
        // в чате — только шаги в браузере: их человек должен видеть, память и так видна плашками
        let all = tr?.message?.steps ?? []
        let steps = c.kind != .chat || turnBot != nil ? all : all.filter(\.shownInChat)
        let shots = tr?.message?.attachments ?? []
        // уже сохранённый по ходу (сделал файл) — тот же ответ дописывается, а не появляется второй
        let earlyID = tr?.message?.id
        tr?.message = nil
        let since = tr?.start ?? Date()
        let remembered = (try? app.store.memoryUses(conversationID: c.id, since: since, action: "remember")) ?? []
        let recalled = (try? app.store.memoryUses(conversationID: c.id, since: since, action: "recall")) ?? []
        // «что дальше»: агент пишет блок в конце ответа — вынимаем его из текста в карточку
        let (visible, next) = c.kind == .agent ? NextStep.split(text) : (text, nil)
        var m = ChatMessage(conversationID: c.id, role: .assistant, text: visible, apiContent: apiContent,
                            model: c.model, stopped: stopped, error: error, steps: steps, changes: changes,
                            remembered: remembered, recalled: recalled.filter { !remembered.contains($0) })
        m.next = stopped ? nil : next
        m.attachments = shots
        m.id = earlyID
        m.botID = turnBot
        // «Попробовать снова»: прежние ответы — вариантами этого
        if let old = pendingVariants.removeValue(forKey: c.id), !old.isEmpty { m.alternates = old }
        if turnBot == nil || c.kind == .bot { m.cliAnchor = tr?.anchor }
        // коннекторы и хуки, которые Lumen предложил за ход, — карточками под ответом
        m.proposals = ProposalBox.take(paths: app.paths, conversationID: c.id)
        if let context, context.0 > 0 {
            m.contextTokens = context.0
            m.contextWindow = context.1 > 0 ? context.1 : nil
        }
        // Lumen позвал бота и сам ничего не добавил — его пустой ответ не нужен (ответ бота уже на экране)
        pullBotReplies(c)
        let skip = tr?.botShown == true && visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && error == nil && !stopped
        if skip, let id = earlyID { try? app.store.deleteMessage(id) }
        let saved = skip ? nil : try? app.store.save(m)
        if let saved, conversation?.id == c.id { messages.append(saved) }
        // первый ответ — название разговора от модели
        if error == nil && !stopped && !visible.isEmpty, c.kind != .bot,
           let all = try? app.store.messages(in: c.id), all.filter({ $0.role == .assistant }).count == 1,
           let q = all.first(where: { $0.role == .user })?.text {
            Task { await app.nameConversation(c, question: q, answer: visible) }
        }
        // Lumen в фоне — уведомление и звук «ответ готов» (Настройки → Общие)
        if error == nil && !stopped && !visible.isEmpty { app.answerReady(c, text: visible) }
        // контекст проекта: что поменялось и компакт этого чата — в PROJECT.md, фоном (Рома, 18.10)
        if error == nil && !stopped && c.projectID != nil && turnBot == nil { app.updateProjectContext(after: c) }
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
        for (id, s) in sessions where turns[id] == nil {
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
        r.append("Факт о проекте начинай с его названия («Lumen: …», «island: …») — так его найдут и разговоры других проектов.")
        r.append("Когда просят «запомни» — обязательно сохрани. Если ответ опирается на прошлое (что решили, что он просил, как зовут людей), сначала вызови recall. О вызовах не рассказывай: Lumen сам покажет, что запомнил.")
        return r.joined(separator: " ")
    }

    /// mcp.json для claude: lumen-mcp с базой и разговором
    func writeMCPConfig(for c: Conversation, memoryReadOnly: Bool = false) throws -> URL {
        let b = c.kind == .bot ? bot(c.botID) : nil
        guard let bin = mcpBinary else { throw CocoaError(.fileNoSuchFile) }
        let dir = paths.run.appendingPathComponent(c.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var servers: [String: Any] = ["lumen": [
            "command": bin.path, "args": [],
            "env": ["LUMEN_DB": paths.database.path, "LUMEN_CONVERSATION_ID": c.id, "LUMEN_CONVERSATION_TITLE": c.title,
                    "LUMEN_MEMORY_READONLY": memoryReadOnly ? "1" : "0",
                    "LUMEN_SKILLS_DIR": paths.skills.path, "LUMEN_SKILLS": b.map { $0.skills.joined(separator: ",") } ?? "*",
                    "LUMEN_BOT_ID": b?.id ?? "", "LUMEN_DEPTH": "0"],
        ]]
        // коннекторы из «Кастомизации»: секреты остаются `${…}`, claude подставит их из окружения процесса
        for (name, s) in connectorsFor(c) { servers[name] = s.claudeJSON }
        let config: [String: Any] = ["mcpServers": servers]
        let url = dir.appendingPathComponent("mcp.json")
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted]).write(to: url)
        return url
    }

    /// Выключатель стража готовности: пока файл лежит, хук ничего не проверяет. Переключатель в настройках
    /// действует сразу, без перезапуска claude: хук встроен в сессию агента всегда, а решает этот файл.
    var guardFlag: URL { paths.run.appendingPathComponent("guard-off") }

    func syncGuardFlag() {
        let fm = FileManager.default
        if prefs.agentGuard {
            try? fm.removeItem(at: guardFlag)
        } else {
            try? fm.createDirectory(at: paths.run, withIntermediateDirectories: true)
            fm.createFile(atPath: guardFlag.path, contents: Data())
        }
    }

    /// Команда хука Stop для агента — «страж готовности» (lumen-mcp guard, см. ReadinessGuard)
    var guardCommand: String? {
        guard let bin = mcpBinary else { return nil }
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return quoted(bin.path) + " guard " + quoted(guardFlag.path) + " " + quoted(nightFile.path)
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
        return p.promptBlock(files: files(of: p), context: projectContext(p), contextPath: contextURL(p).path)
    }

    /// Что Lumen знает к этому разговору: закреплённые факты и — в проекте — факты о самом проекте.
    /// Агенту и чату одно и то же: память общая для всех проектов, проект только добавляет своё.
    func knownBlock(for c: Conversation?) -> String? {
        let all = (try? store.memories()) ?? []
        let pinned = all.filter(\.pinned)
        var lines: [String] = []
        if !pinned.isEmpty {
            lines.append("Что ты знаешь о нём:")
            lines += pinned.map { "- \($0.text)" }
        }
        if let p = project(c?.projectID) {
            let ids = Set(pinned.compactMap(\.id))
            let about = ((try? store.searchMemories(p.name, limit: 10, anyWord: true)) ?? []).filter { !ids.contains($0.id ?? -1) }
            if !about.isEmpty {
                lines.append("Что известно о проекте «\(p.name)»:")
                lines += about.map { "- \($0.text)" }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func agentPrompt(for c: Conversation? = nil) -> String {
        // у агента нет характера (Рома, 19.10): правила работы — зашитые в код и свои из настроек (AgentRules)
        var lines = [AgentRules.core(userName: profile.name, ty: profile.address == .ty, russianOnly: persona.language == .ru)]
        if let mine = AgentRules.user(prefs.agentRules) { lines.append(mine) }
        lines.append("Всегда веди план, даже для маленькой задачи из двух шагов: первым действием составь его (TaskCreate на каждый шаг или TodoWrite), перед шагом отмечай его начатым, после — сделанным (TaskUpdate). Lumen показывает план человеку под перепиской. Только ответ на вопрос без действий — без плана.")
        lines.append("""
            В самом конце каждого ответа добавь блок для карточки «что дальше» — строго JSON внутри тегов, без markdown:
            <lumen-next>{"recap": "два-три коротких предложения: что теперь сделано, как проверено и что не сделано или не проверено", "ask": "один вопрос, ТОЛЬКО если без решения человека нельзя продолжать (необратимое, чужое, деньги, push или публикация), иначе null", "primary": {"label": "1–3 слова", "reply": "что отправится от человека"} или null, "secondary": такая же вторая кнопка, только если это реальная альтернатива, иначе null}</lumen-next>
            Этот блок Lumen показывает отдельной карточкой — в тексте ответа итог не повторяй. Если вопроса нет, не придумывай его: ask — null.
            """)
        if let known = knownBlock(for: c) { lines.append(known) }
        if let block = projectBlock(for: c) { lines.append(block) }
        if let skills = SkillLibrary.promptBlock(skillLibrary.enabled()) { lines.append(skills) }
        lines.append(selfRules)
        lines.append(memoryRules)
        lines.append(BrowserTools.rules)
        lines.append(Visuals.rules)
        return lines.joined(separator: "\n")
    }

    /// Что Lumen умеет сам с собой: навыки (создать, найти, поставить)
    var selfRules: String {
        """
        Ты умеешь достраивать себя навыками (SKILL.md, формат agentskills.io): list_skills — какие есть; create_skill — создать новый; \
        find_skills и install_skill — найти и поставить готовый из каталога skills.sh. Когда просят научиться чему-то, сделать навык \
        или приём повторяется — сделай навык сам, не отказывайся. Ботов человек создаёт во вкладке «Боты» — подскажи, если спрашивают. \
        Коннекторы (серверы MCP: сайты и программы — браузер, GitHub, Notion, базы) и хуки (команды на события Claude Code: \
        звук после ответа, запрет опасных команд) ты тоже умеешь: list_customization — что подключено; find_connectors — найти \
        готовый в реестре MCP; propose_connector — предложить готовый (config) или написать свой MCP-сервер на Python (script); \
        propose_hook — предложить хук. Предложение появляется карточкой под ответом, подключает человек одним нажатием \
        («Кастомизация» в Lumen). Когда просят коннектор, MCP или хук — делай это сам этими инструментами, не отказывайся и не \
        отправляй делать руками; не говори, что уже подключено, пока человек не нажал. \(connectorLine)
        \(botLine)
        """
    }

    /// Боты Lumen — чтобы он знал их и подсказывал, кого позвать
    private var botLine: String {
        guard !bots.isEmpty else { return "Ботов пока нет — их создают во вкладке «Боты»." }
        return "Твои боты (свои роли, свои права): " + bots.map { "@\($0.id) — \($0.name)\($0.role.isEmpty ? "" : ": \($0.role)")" }.joined(separator: "; ")
            + ". Человек зовёт бота сам, написав в начале сообщения @id и задачу. Ты тоже можешь: инструмент delegate (bot, task) — "
            + "передай задачу полностью, с нужным контекстом (бот не видит этот разговор) "
            + "— его ответ человек увидит сам, отдельным сообщением бота. Перед вызовом ничего не пиши; после — только своё короткое мнение, "
            + "если оно нужно. Когда просят спросить или позвать бота — зови сам, не пиши «@id …» в ответ."
    }

    /// Какие коннекторы подключены сейчас — чтобы Lumen не говорил «нет», когда есть
    private var connectorLine: String {
        let on = connectors.enabled.map(\.name)
        return on.isEmpty ? "Сейчас коннекторов нет." : "Сейчас подключены: " + on.joined(separator: ", ") + " — их инструменты у тебя есть."
    }

    /// Библиотека навыков Lumen
    var skillLibrary: SkillLibrary { SkillLibrary(root: paths.skills) }

    /// Системный промпт Lumen (SOUL v0): кто он, с кем говорит, закреплённые факты.
    /// Детерминированный — одинаковый от хода к ходу, поэтому кэшируется.
    func systemPrompt(for c: Conversation? = nil) -> String {
        // характер — из настроек «Характер» (Persona.swift)
        var lines = [persona.soul(userName: profile.name, ty: profile.address == .ty), "\n## Где ты\nТы — Lumen, личный помощник на Маке."]
        if let known = knownBlock(for: c) { lines.append(known) }
        lines.append("Это чат: у тебя нет доступа к файлам и командам этого Мака, но есть браузер сбоку. "
                     + "Файлы для человека делай инструментом make_file — они приходят вложением. Про папки, пути и временные каталоги "
                     + "из описания окружения не рассказывай: это служебное, у чата своя папка в Lumen.")
        if let block = projectBlock(for: c) { lines.append(block) }
        if let skills = SkillLibrary.promptBlock(skillLibrary.enabled()) { lines.append(skills) }
        lines.append(selfRules)
        lines.append(memoryRules)
        lines.append(BrowserTools.rules)
        lines.append(Visuals.rules)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Самостоятельная работа (Рома, 19.10): присутствие, ночь, автовыбор модели, своё сжатие
// Правила без интерфейса — LumenCore/Autonomy.swift, выбор модели — LumenProviders/ModelChoice.swift

extension ChatController {
    /// Модель этого хода: выбранная или та, что подменила её из-за лимита
    func effectiveModel(_ c: Conversation) -> ChatModel { modelOverride[c.id] ?? c.model }

    /// Режим агента: ночью — обход разрешений (человек спит, спрашивать некого), иначе выбранный
    func effectiveMode(_ c: Conversation) -> AgentMode? {
        c.kind == .agent && app.prefs.night.active() ? .bypassPermissions : c.mode
    }

    /// Перед ходом: у выбранной модели кончился недельный лимит — взять следующую по силе, у которой он есть
    func chooseModel(_ c: Conversation) {
        guard app.prefs.autoModel, !c.model.isGPT else {
            modelOverride[c.id] = nil
            modelNote[c.id] = nil
            return
        }
        let pick = ModelChoice.pick(c.model, usage: app.usage)
        modelOverride[c.id] = pick.model == c.model ? nil : pick.model
        modelNote[c.id] = pick.why
    }

    /// Ход упал на лимите: обновить лимиты и, если другая модель может ответить, — ответить ею (true)
    func switchModelAfterLimit(_ c: Conversation, _ failure: String) async -> Bool {
        guard app.prefs.autoModel, UsageLimit.isLimit(failure), !c.model.isGPT else { return false }
        let now = effectiveModel(c)
        await app.refreshUsage()
        var usage = app.usage
        // claude сказал «лимит», а /usage этого у модели ещё не показал — считаем её исчерпанной
        if !usage.contains(where: { $0.kind == .weekModel(now.name) && $0.percent >= 100 }) {
            usage.append(UsageWindow(kind: .weekModel(now.name), percent: 100, resetsAt: nil))
        }
        let pick = ModelChoice.pick(now, usage: usage)
        guard pick.model != now else { return false }
        app.log("Лимит у \(now.name) — отвечает \(pick.model.name)", conversation: c)
        modelOverride[c.id] = pick.model
        modelNote[c.id] = pick.why ?? "Лимит \(now.name) исчерпан — отвечает \(pick.model.name)"
        sessions[c.id]?.close()
        sessions[c.id] = nil
        return true
    }

    /// Скрытая пометка к сообщению агенту: ночь или человек отошёл (правила к ним — в AgentRules)
    func autonomyNote(_ c: Conversation) -> String {
        guard c.kind == .agent else { return "" }
        if let until = app.prefs.night.until, app.prefs.night.active() { return Night.note(until: until) }
        if app.prefs.presence, app.away { return Presence.awayNote }
        return ""
    }

    /// Агент ждёт разрешения, а человека нет (отошёл дольше 30 с) или он спит — ответить «пропусти, сделай остальное»
    func watchPermission(_ c: Conversation, _ req: ClaudeEvent.PermissionRequest, _ session: ClaudeSession) {
        Task { @MainActor [weak self] in
            var waited: TimeInterval = 0
            while let self, self.pendingPermissions[c.id]?.request.id == req.id {
                let away = self.app.prefs.presence && self.app.away
                if self.app.prefs.night.active() || (away && waited >= 30) {
                    session.respond(req.id, allow: false, message: Presence.deniedWhileAway)
                    self.pendingPermissions[c.id] = nil
                    self.app.log("«\(req.tool)» ждал разрешения, а человека нет — ответил «пропусти»", conversation: c)
                    return
                }
                try? await Task.sleep(for: .seconds(5))
                waited += 5
            }
        }
    }

    /// После хода: своё сжатие, «реши сам» за отошедшего человека, ночью — ждать сброса лимита
    func afterTurn(_ c: Conversation, stopped: Bool) async {
        guard !stopped, c.kind == .agent || c.kind == .chat,
              let last = (try? app.store.messages(in: c.id))?.last, last.role == .assistant else { return }
        let night = app.prefs.night.active()
        if let err = last.error {
            // ночью кончился лимит подписки — дождаться сброса и продолжить
            if UsageLimit.isLimit(err), night, app.prefs.night.waitForLimits, c.kind == .agent { waitForLimit(c) }
            return
        }
        if app.prefs.autoCompact, let used = last.contextTokens, let window = last.contextWindow,
           Handoff.due(used: used, window: window, percent: app.prefs.compactAt) {
            _ = await handoffCompact(c)
        }
        // агент спросил, а человек отошёл (или спит) — ответить за него «реши сам», не больше трёх раз подряд
        guard c.kind == .agent, last.next?.ask != nil, night || (app.prefs.presence && app.away),
              (autoContinues[c.id] ?? 0) < 3, queue[c.id]?.isEmpty ?? true, turns[c.id] == nil else { return }
        autoContinues[c.id, default: 0] += 1
        app.log("Агент спросил, а человека нет рядом — ответил «реши сам»", conversation: c)
        begin(app.conversations.first { $0.id == c.id } ?? c, text: Presence.autoAnswer, attachments: [], isNew: false,
              via: .auto("тебя не было рядом"))
    }

    /// Ночью кончился лимит: ждать сброса (по /usage) и написать агенту «продолжай»
    func waitForLimit(_ c: Conversation) {
        guard limitWaits[c.id] == nil else { return }
        modelNote[c.id] = "Лимит подписки кончился — жду сброса и продолжу сам"
        limitWaits[c.id] = Task { @MainActor [weak self] in
            var cleared = false
            while let self, self.app.prefs.night.active(), !Task.isCancelled {
                await self.app.refreshUsage()
                let full = self.app.usage.filter { $0.percent >= 100 }
                if !self.app.usage.isEmpty, full.isEmpty { cleared = true; break }
                let reset = full.compactMap(\.resetsAt).max() ?? Date().addingTimeInterval(15 * 60)
                try? await Task.sleep(for: .seconds(min(max(reset.timeIntervalSinceNow + 60, 60), 30 * 60)))
            }
            guard let self else { return }
            self.limitWaits[c.id] = nil
            self.modelNote[c.id] = nil
            // ночь кончилась раньше — утреннее сообщение отправится само
            guard cleared, !Task.isCancelled, self.turns[c.id] == nil else { return }
            self.begin(self.app.conversations.first { $0.id == c.id } ?? c, text: "Лимит подписки обновился — продолжай с того места, где остановился.",
                       attachments: [], isNew: false, via: .auto("лимит сбросился"))
        }
    }

    /// Ночь началась: идущие ходы агента — в обход разрешений, их разговоры получат утреннее сообщение
    func nightStarted() {
        for (id, tr) in turns where tr.conversation.kind == .agent {
            nightConversations.insert(id)
            if let s = sessions[id], s.isRunning {
                s.setMode(AgentMode.bypassPermissions.rawValue)
                sessionModes[id] = .bypassPermissions
            }
        }
    }

    /// Утро: разговорам, что работали ночью, — «заверши и напиши отчёт». Идёт ход — встанет в очередь и уйдёт после него
    func morning(_ text: String) {
        let ids = nightConversations
        nightConversations = []
        for id in ids {
            limitWaits[id]?.cancel()
            limitWaits[id] = nil
            modelNote[id] = nil
            guard let c = app.conversations.first(where: { $0.id == id }) else { continue }
            if turns[id] != nil {
                queue[id, default: []].append(Queued(text: text, attachments: [], via: .auto("утро")))
            } else {
                begin(c, text: text, attachments: [], isNew: false, via: .auto("утро"))
            }
        }
    }

    // MARK: своё сжатие

    func handoffFile(_ id: String) -> URL {
        app.paths.run.appendingPathComponent(id, isDirectory: true).appendingPathComponent("handoff.md")
    }

    /// Записка ждёт первого хода свежей сессии
    func pendingHandoff(_ id: String) -> String? { try? String(contentsOf: handoffFile(id), encoding: .utf8) }

    func clearHandoff(_ id: String) { try? FileManager.default.removeItem(at: handoffFile(id)) }

    /// Своё сжатие: агент пишет себе записку-передачу, Lumen хранит её и начинает свежую сессию claude —
    /// записка уйдёт первым скрытым сообщением следующего хода. true — сжато, false — не вышло, nil — остановили
    func handoffCompact(_ conv: Conversation) async -> Bool? {
        guard conv.usesCLI, turns[conv.id] == nil, let cli = app.cli else { return false }
        var c = app.conversations.first { $0.id == conv.id } ?? conv
        let tr = Turn(c)
        tr.thinking = false
        turns[c.id] = tr
        retryNote[c.id] = "Сжимаю разговор: агент пишет себе записку-передачу"
        defer {
            retryNote[c.id] = nil
            turns[c.id] = nil
            settleOrb()
        }
        var note = ""
        do {
            let session = try cliSession(for: c, cli: cli, resume: true)
            for await ev in try session.send(Handoff.request) {
                if case .textDelta(let t) = ev { note += t }
                if case .finished(let r) = ev {
                    if !r.text.isEmpty { note = r.text }
                    break
                }
            }
        } catch {
            app.log("Сжатие: \(error.localizedDescription)", conversation: c)
        }
        if tr.stopRequested { return nil }
        note = NextStep.split(note).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count > 300 else {
            app.log("Сжатие не удалось: записка пустая или слишком короткая (\(note.count) знаков)", conversation: c)
            return false
        }
        // свежая сессия: прошлая остаётся в claude, но к ней больше не возвращаемся
        sessions[c.id]?.close()
        sessions[c.id] = nil
        rewindAt[c.id] = nil
        c.cliSessionID = UUID().uuidString.lowercased()
        try? app.store.save(c)
        if conversation?.id == c.id { conversation?.cliSessionID = c.cliSessionID }
        if let i = app.conversations.firstIndex(where: { $0.id == c.id }) { app.conversations[i].cliSessionID = c.cliSessionID }
        let file = handoffFile(c.id)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? note.write(to: file, atomically: true, encoding: .utf8)
        let words = note.split(whereSeparator: \.isWhitespace).count
        var m = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: effectiveModel(c),
                            note: "Lumen сжал разговор: агент записал себе главное (\(words) слов) и продолжит с этой запиской в свежей сессии — окно контекста свободно")
        // окно теперь почти пустое: в нём только записка
        m.contextTokens = note.count / 3
        m.contextWindow = (try? app.store.messages(in: c.id))?.last(where: { $0.contextWindow != nil })?.contextWindow
        if let saved = try? app.store.save(m), conversation?.id == c.id { messages.append(saved) }
        app.log("Сжал разговор: записка \(words) слов, новая сессия \(c.cliSessionID ?? "")", conversation: c)
        return true
    }
}


// MARK: - Фоновые задачи агента (Рома, 19.10): субагенты, исследования, команды в терминале

extension ChatController {
    func applyTask(_ event: TaskEvent, to id: String) {
        backgroundTasks[id] = BackgroundJob.apply(event, to: backgroundTasks[id] ?? [])
        // задача работает — агент жив, хоть и молчит
        if case .progress = event { lastSign[id] = Date() }
        if case .finished(_, let status, _, _, _) = event {
            app.log("Фоновая задача закончилась: \(status)", conversation: app.conversations.first { $0.id == id })
        }
    }
}
