import Foundation

/// Один живой процесс `claude -p` со stream-json на входе и выходе (§2.2, спайк 1).
/// Процесс живёт, пока открыт разговор: ходы идут без холодного старта.
/// «Стоп» — управляющее сообщение `interrupt`: ход завершается за ~0,07 с, процесс принимает следующий ход.
public final class ClaudeSession: @unchecked Sendable {
    public struct Config: Sendable {
        public var model: String
        public var effort: String?
        public var systemPrompt: String?
        /// nil — все инструменты Claude Code (агент); [] — ни одного (чат)
        public var tools: [String]?
        /// false — не грузить ~/.claude: ни хуков, ни CLAUDE.md. Агенту оставляем true, чтобы он был виден на острове.
        public var userSettings: Bool
        public var sessionID: String
        /// Продолжить уже существующую сессию (после того как процесс погасили)
        public var resume: Bool
        public var cwd: URL?
        public var extraEnv: [String: String]
        /// Дописать к системному промпту Claude Code (агент), а не заменить его
        public var appendSystemPrompt: String?
        /// Что разрешено без вопросов и что запрещено даже при обходе (`--allowedTools` / `--disallowedTools`)
        public var allowedTools: [String]
        public var disallowedTools: [String]
        /// Файл с MCP-серверами (lumen-mcp — память)
        public var mcpConfig: String?
        /// `--permission-mode`; с вопросами (не dontAsk/bypass) разрешения спрашиваются у Lumen через stdio
        public var permissionMode = "dontAsk"
        public var asksHost: Bool { permissionMode != "dontAsk" && permissionMode != "bypassPermissions" }

        public init(model: String, effort: String? = nil, systemPrompt: String? = nil, tools: [String]? = [],
                    userSettings: Bool = false, sessionID: String = UUID().uuidString.lowercased(),
                    resume: Bool = false, cwd: URL? = nil, extraEnv: [String: String] = [:],
                    appendSystemPrompt: String? = nil, allowedTools: [String] = [], disallowedTools: [String] = []) {
            self.appendSystemPrompt = appendSystemPrompt
            self.allowedTools = allowedTools
            self.disallowedTools = disallowedTools
            self.model = model
            self.effort = effort
            self.systemPrompt = systemPrompt
            self.tools = tools
            self.userSettings = userSettings
            self.sessionID = sessionID
            self.resume = resume
            self.cwd = cwd
            self.extraEnv = extraEnv
        }

        /// Агент в папке проекта: все инструменты Claude Code, настройки пользователя (сессия видна на острове),
    /// push запрещён в любом режиме (docs/spikes.md, спайк агента). Режим решает, что спрашивать у человека:
    /// чтение и план всегда без вопросов, остальное — по режиму (`--permission-mode` + вопросы через stdio).
    public static func agent(model: String, effort: String?, persona: String, folder: URL, sessionID: String, resume: Bool,
                             mode: String = "auto") -> Config {
        let quiet = ["Read", "Glob", "Grep", "TodoWrite", "Task", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "ToolSearch", "WebSearch"]
        var c = Config(model: model, effort: effort, tools: nil, userSettings: true, sessionID: sessionID, resume: resume, cwd: folder,
                       appendSystemPrompt: persona, allowedTools: quiet, disallowedTools: ["Bash(git push:*)", "Bash(git push)"])
        c.permissionMode = mode
        return c
    }

    /// Аргументы командной строки. Флаги-списки (`--tools`) съедают следующий аргумент,
        /// поэтому текст запроса в аргументы не кладём никогда — он идёт через stdin.
        public var arguments: [String] {
            var a = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                     "--include-partial-messages", "--model", model, "--permission-mode", permissionMode]
            if asksHost { a += ["--permission-prompt-tool", "stdio"] }
            if let effort { a += ["--effort", effort] }
            // свой промпт чата меняется (закреплённые факты) — пусть claude берёт его заново при --resume
            if let systemPrompt { a += ["--system-prompt", systemPrompt, "--system-prompt-snapshot", "off"] }
            if let appendSystemPrompt { a += ["--append-system-prompt", appendSystemPrompt] }
            if !allowedTools.isEmpty { a += ["--allowedTools"] + allowedTools }
            if !disallowedTools.isEmpty { a += ["--disallowedTools"] + disallowedTools }
            if let tools { a += ["--tools", tools.joined(separator: ",")] }
            if !userSettings { a += ["--setting-sources", "", "--strict-mcp-config"] }
            if let mcpConfig { a += ["--mcp-config", mcpConfig] }
            a += resume ? ["--resume", sessionID] : ["--session-id", sessionID]
            return a
        }
    }

    public let config: Config
    private let process = Process()
    private let input = Pipe()
    private var stderrText = ""
    /// Поток событий текущего хода. Между ходами событий почти нет; что пришло — достаётся следующему ходу.
    private var turn: AsyncStream<ClaudeEvent>.Continuation?
    private let lock = NSLock()

    public init(cli: ClaudeCLI, config: Config) throws {
        self.config = config

        process.executableURL = cli.binary
        process.arguments = config.arguments
        process.environment = Shell.env.merging(config.extraEnv) { $1 }
        if let cwd = config.cwd { process.currentDirectoryURL = cwd }
        let output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let lines = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            for line in lines.append(chunk) {
                for ev in ClaudeEvent.decodeAll(line) { self.deliver(ev) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard let self, !s.isEmpty else { return }
            self.lock.lock(); self.stderrText += s; self.lock.unlock()
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            self?.endTurn()
        }
        try process.run()
    }

    /// Отправить сообщение пользователя — начинается ход. Поток кончается вместе с ходом
    /// (событие `.finished`) или если процесс умер.
    public func send(_ text: String) throws -> AsyncStream<ClaudeEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: ClaudeEvent.self)
        lock.lock()
        turn?.finish()
        turn = cont
        lock.unlock()
        let msg: [String: Any] = ["type": "user",
                                  "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        var data = try JSONSerialization.data(withJSONObject: msg)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
        return stream
    }

    private func deliver(_ ev: ClaudeEvent) {
        lock.lock(); let cont = turn; lock.unlock()
        cont?.yield(ev)
        if case .finished = ev { endTurn() }
    }

    private func endTurn() {
        lock.lock(); let cont = turn; turn = nil; lock.unlock()
        cont?.finish()
    }

    /// «Стоп»: прервать текущий ход, процесс остаётся жив.
    /// Управляющее сообщение `interrupt`, как у Agent SDK: ход кончается за ~0,07 с.
    /// SIGINT не годится — после него `claude` завершается целиком (docs/spikes.md).
    public func interrupt() {
        let msg: [String: Any] = ["type": "control_request",
                                  "request_id": "stop-" + UUID().uuidString.lowercased(),
                                  "request": ["subtype": "interrupt"]]
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// Ответ на запрос разрешения: разрешить (вход как был) или отклонить с объяснением для модели
    public func respond(_ id: String, allow: Bool, inputJSON: String? = nil, message: String? = nil) {
        var response: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if allow {
            response["updatedInput"] = (try? JSONSerialization.jsonObject(with: Data((inputJSON ?? "{}").utf8))) ?? [:]
        } else {
            response["message"] = message ?? "Человек не разрешил."
        }
        send(["type": "control_response", "response": ["subtype": "success", "request_id": id, "response": response]])
    }

    /// Сменить режим на ходу, без перезапуска (как setPermissionMode в Agent SDK)
    public func setMode(_ mode: String) {
        send(["type": "control_request", "request_id": "mode-" + UUID().uuidString.lowercased(),
              "request": ["subtype": "set_permission_mode", "mode": mode]])
    }

    private func send(_ msg: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// Погасить процесс. Следующий ход — новой сессией с `resume: true`.
    public func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    public var isRunning: Bool { process.isRunning }

    /// Что `claude` написал в stderr — для понятной ошибки, если процесс упал
    public var errorOutput: String {
        lock.lock(); defer { lock.unlock() }
        return stderrText
    }

    deinit { close() }
}

extension ClaudeSession {
    /// Один ход до конца: отправить, дождаться результата. Для проверок и фоновых вызовов.
    public func ask(_ text: String) async throws -> ClaudeEvent.TurnResult {
        for await ev in try send(text) {
            if case .finished(let r) = ev { return r }
        }
        throw ClaudeError.failed(errorOutput.isEmpty ? "Claude Code завершился без ответа" : errorOutput)
    }
}

/// Склеивает куски вывода в целые строки. Обработчик трубы вызывается на одной очереди, но компилятор этого не знает.
final class LineBuffer: @unchecked Sendable {
    private var data = Data()

    func append(_ chunk: Data) -> [Data] {
        data.append(chunk)
        var lines: [Data] = []
        while let nl = data.firstIndex(of: 0x0A) {
            lines.append(Data(data[data.startIndex..<nl]))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }
}
