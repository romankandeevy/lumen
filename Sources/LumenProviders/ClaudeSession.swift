import Foundation
import LumenCore

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
        /// Продолжить с этого сообщения: всё, что было после, забыто («Изменить», «Попробовать снова»)
        public var resumeAt: String?
        public var cwd: URL?
        public var extraEnv: [String: String]
        /// Дописать к системному промпту Claude Code (агент), а не заменить его
        public var appendSystemPrompt: String?
        /// Что разрешено без вопросов и что запрещено даже при обходе (`--allowedTools` / `--disallowedTools`)
        public var allowedTools: [String]
        public var disallowedTools: [String]
        /// Файл с MCP-серверами (lumen-mcp — память, плюс коннекторы из «Кастомизации»)
        public var mcpConfig: String?
        /// Файл настроек с хуками из «Кастомизации» (`--settings`; работает и при `--setting-sources ""`)
        public var settings: String?
        /// Плагины Claude Code, выключенные в этой сессии: с ними приходят их навыки, агенты, хуки и коннекторы,
        /// а в Lumen — только своё (Рома, 17.10). По умолчанию — список, который Lumen снял с `claude plugin list`.
        public var pluginsOff: [String] = Config.claudePlugins()
        /// Ещё папки с доступом, кроме рабочей (`--add-dir`)
        public var addDirs: [String] = []
        /// Встроенный плагин Claude Code со своим навыком — его в списке `plugin list` нет
        static let builtinPlugins = ["cc-plugin-plugin-authoring@builtin"]

        public static func claudePlugins(_ paths: AppPaths = .standard) -> [String] {
            let saved = (try? Data(contentsOf: paths.claudePlugins)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            return saved + builtinPlugins.filter { !saved.contains($0) }
        }

        /// Команда хука Stop — «страж готовности» (`lumen-mcp guard <флаг>`); только у агента (Рома, 19.10)
        public var guardCommand: String?

        /// `--settings`: хуки из файла «Кастомизации», страж готовности и выключенные плагины — одной строкой JSON
        static func settings(file: String?, pluginsOff: [String], guardCommand: String? = nil) -> String? {
            var dict: [String: Any] = [:]
            if let file, let d = FileManager.default.contents(atPath: file),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { dict = o }
            else if let file { return file } // не JSON-файл — как есть
            if let guardCommand {
                var hooks = dict["hooks"] as? [String: Any] ?? [:]
                var stop = hooks["Stop"] as? [[String: Any]] ?? []
                stop.append(["hooks": [["type": "command", "command": guardCommand, "timeout": 30]]])
                hooks["Stop"] = stop
                dict["hooks"] = hooks
            }
            if !pluginsOff.isEmpty { dict["enabledPlugins"] = Dictionary(uniqueKeysWithValues: pluginsOff.map { ($0, false) }) }
            guard !dict.isEmpty, let d = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else { return nil }
            return String(decoding: d, as: UTF8.self)
        }

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
            // навыки — только свои, Lumen (через lumen-mcp): инструмента Skill у claude нет, навыки и плагины Claude Code
            // не видны и не вызываются (Рома, 17.10). Не --disable-slash-commands: он выключает и /compact.
            let never = disallowedTools + (disallowedTools.contains("Skill") ? [] : ["Skill"])
            a += ["--disallowedTools"] + never
            if let tools { a += ["--tools", tools.joined(separator: ",")] }
            if !userSettings { a += ["--setting-sources", ""] }
            // коннекторы — только свои, Lumen: ни MCP из ~/.claude, ни коннекторов аккаунта claude.ai (Рома, 17.10)
            if !userSettings || mcpConfig != nil { a += ["--strict-mcp-config"] }

            for d in addDirs { a += ["--add-dir", d] }
            if let mcpConfig { a += ["--mcp-config", mcpConfig] }
            if let s = Self.settings(file: settings, pluginsOff: pluginsOff, guardCommand: guardCommand) { a += ["--settings", s] }
            a += resume ? ["--resume", sessionID] : ["--session-id", sessionID]
            if resume, let resumeAt { a += ["--resume-session-at", resumeAt] }
            return a
        }
    }

    public let config: Config
    private let process = Process()
    private let input = Pipe()
    private var stderrText = ""
    /// Журнал процесса человеческими строками (ClaudeLog): Lumen показывает его в панели «Журнал Claude Code»
    private var logSink: (@Sendable (ClaudeLog.Line) -> Void)?
    private let logState = ClaudeLog.State()
    public var onLog: (@Sendable (ClaudeLog.Line) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return logSink }
        set { lock.lock(); logSink = newValue; lock.unlock() }
    }
    private func log(_ kind: ClaudeLog.Line.Kind, _ text: String) { onLog?(ClaudeLog.Line(kind: kind, text: text)) }
    /// Поток событий текущего хода. Между ходами событий почти нет; что пришло — достаётся следующему ходу.
    private var turn: AsyncStream<ClaudeEvent>.Continuation?
    private let lock = NSLock()

    public init(cli: ClaudeCLI, config: Config) throws {
        self.config = config

        process.executableURL = cli.binary
        process.arguments = config.arguments
        // коннекторы аккаунта claude.ai (Gmail, Notion…) в Lumen не подключаются: у него свои
        process.environment = Shell.env.merging(["ENABLE_CLAUDEAI_MCP_SERVERS": "false"]) { $1 }.merging(config.extraEnv) { $1 }
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
                if let sink = self.onLog, let l = ClaudeLog.summarize(line, state: self.logState) { sink(l) }
                for ev in ClaudeEvent.decodeAll(line) { self.deliver(ev) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard let self, !s.isEmpty else { return }
            self.lock.lock(); self.stderrText += s; self.lock.unlock()
            for l in s.split(separator: "\n") where !l.trimmingCharacters(in: .whitespaces).isEmpty {
                self.log(.error, "stderr: " + String(l.prefix(300)))
            }
        }
        process.terminationHandler = { [weak self] p in
            self?.log(p.terminationStatus == 0 ? .info : .error, "Процесс claude завершился (код \(p.terminationStatus))")
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            self?.endTurn()
        }
        try process.run()
    }

    /// Отправить сообщение пользователя — начинается ход. Поток кончается вместе с ходом
    /// (событие `.finished`) или если процесс умер.
    public func send(_ text: String) throws -> AsyncStream<ClaudeEvent> {
        try send(content: [["type": "text", "text": text]])
    }

    /// Сообщение с вложениями: блоки картинок, документов и текста
    public func send(content: [[String: Any]]) throws -> AsyncStream<ClaudeEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: ClaudeEvent.self)
        lock.lock()
        turn?.finish()
        turn = cont
        lock.unlock()
        let msg: [String: Any] = ["type": "user",
                                  "message": ["role": "user", "content": content]]
        var data = try JSONSerialization.data(withJSONObject: msg)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
        log(.wait, "Сообщение отправлено — ждёт ответа API")
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
        log(.info, "«Стоп» — прерываю ход")
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
