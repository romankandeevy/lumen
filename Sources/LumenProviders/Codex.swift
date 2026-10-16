import Foundation
import LumenCore

/// ChatGPT через официальный `codex` (OpenAI) по подписке ChatGPT — так же, как Claude через `claude`.
/// Ход — отдельный запуск `codex exec --json`, продолжение разговора — `codex exec resume <thread>`.
/// События JSONL переводятся в те же `ClaudeEvent`, что у Claude: текст, шаги, план, итог.
public struct CodexCLI: Sendable {
    public let binary: URL

    public init(binary: URL) { self.binary = binary }

    public static func locate() -> CodexCLI? {
        Shell.which("codex").map(CodexCLI.init)
    }

    public func version() async throws -> String {
        let out = try await Shell.run(binary, ["--version"])
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `codex login status`: «Logged in using ChatGPT» или «Not logged in»
    public func signedIn() async -> Bool {
        guard let out = try? await Shell.run(binary, ["login", "status"]) else { return false }
        let text = (out.stdout + out.stderr).lowercased()
        return out.status == 0 && text.contains("logged in") && !text.contains("not logged in")
    }

    /// Вход через браузер аккаунтом ChatGPT. Ждёт, пока человек войдёт.
    public func login() async throws {
        let out = try await Shell.run(binary, ["login"])
        if out.status != 0 { throw ClaudeError.failed(out.stderr.isEmpty ? out.stdout : out.stderr) }
    }

    public func logout() async throws {
        _ = try await Shell.run(binary, ["logout"])
    }

    /// Аргументы одного хода
    public struct Turn: Sendable {
        public var model: String
        public var effort: String
        /// Агент правит файлы в папке; чат — только читает (и то в пустой папке)
        public var agent: Bool
        public var folder: URL
        /// Продолжение разговора
        public var threadID: String?
        /// MCP-сервер памяти Lumen: путь и переменные окружения
        public var memoryServer: (command: String, env: [String: String])?
        /// Не сохранять сессию (короткие служебные запросы: название разговора)
        public var ephemeral = false
        /// Картинки к ходу (`-i`)
        public var images: [String] = []

        public init(model: String, effort: String, agent: Bool, folder: URL, threadID: String? = nil,
                    memoryServer: (command: String, env: [String: String])? = nil) {
            self.model = model
            self.effort = effort
            self.agent = agent
            self.folder = folder
            self.threadID = threadID
            self.memoryServer = memoryServer
        }

        public var arguments: [String] {
            var a = ["exec", "--json", "--skip-git-repo-check", "--color", "never"] + (ephemeral ? ["--ephemeral"] : [])
                + images.flatMap { ["-i", $0] } + [
                     "-m", model, "-c", "model_reasoning_effort=\"\(effort)\"",
                     // агент: пишет только в своей папке, без сети — push невозможен
                     "-s", agent ? "workspace-write" : "read-only",
                     "-C", folder.path]
            if let m = memoryServer {
                a += ["-c", "mcp_servers.lumen.command=\(Self.toml(m.command))"]
                let env = m.env.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.toml($0.value))" }.joined(separator: ", ")
                a += ["-c", "mcp_servers.lumen.env={\(env)}"]
            }
            if let threadID { a += ["resume", threadID] }
            a.append("-")   // текст хода — из stdin
            return a
        }

        /// Строка TOML: JSON-строка — тоже правильная строка TOML
        static func toml(_ s: String) -> String {
            String(decoding: (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
        }
    }

    public func run(_ turn: Turn, prompt: String) throws -> CodexRun {
        try CodexRun(binary: binary, turn: turn, prompt: prompt)
    }

    /// Один короткий ответ без сохранения сессии
    public func ask(_ prompt: String, model: String, folder: URL) async -> String? {
        var t = Turn(model: model, effort: "low", agent: false, folder: folder)
        t.ephemeral = true
        guard let run = try? run(t, prompt: prompt) else { return nil }
        var text = ""
        for await ev in run.events {
            if case .textDelta(let s) = ev { text += s }
            if case .finished(let r) = ev, !r.ok { return nil }
        }
        return text.isEmpty ? nil : text
    }
}

/// Один ход `codex exec`. «Стоп» — завершить процесс: ход в codex живёт ровно столько, сколько процесс.
public final class CodexRun: @unchecked Sendable {
    public let events: AsyncStream<ClaudeEvent>
    private let cont: AsyncStream<ClaudeEvent>.Continuation
    private let process = Process()
    private let parser = CodexParser()
    private let lock = NSLock()
    private var stderrText = ""

    init(binary: URL, turn: CodexCLI.Turn, prompt: String) throws {
        (events, cont) = AsyncStream.makeStream(of: ClaudeEvent.self)
        process.executableURL = binary
        process.arguments = turn.arguments
        process.environment = Shell.env
        process.currentDirectoryURL = turn.folder
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let lines = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            for line in lines.append(chunk) {
                for ev in self.parser.parse(line) { self.cont.yield(ev) }
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
            guard let self else { return }
            if let tail = output.fileHandleForReading.readDataToEndOfFileSafely() {
                for line in lines.append(tail + Data([0x0A])) where !line.isEmpty {
                    for ev in self.parser.parse(line) { self.cont.yield(ev) }
                }
            }
            self.cont.finish()
        }
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try input.fileHandleForWriting.close()
    }

    public func stop() {
        if process.isRunning { process.terminate() }
    }

    public var errorOutput: String {
        lock.lock(); defer { lock.unlock() }
        return stderrText
    }
}

private extension FileHandle {
    func readDataToEndOfFileSafely() -> Data? {
        (try? readToEnd()) ?? nil
    }
}

/// Разбор строк `codex exec --json` (thread.started, item.*, turn.completed, turn.failed, error)
public final class CodexParser: @unchecked Sendable {
    private var thread = ""
    private var text = ""
    private var seenSteps = Set<String>()

    public init() {}

    public func parse(_ line: Data) -> [ClaudeEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return [] }
        switch type {
        case "thread.started":
            thread = obj["thread_id"] as? String ?? ""
            return [.started(sessionID: thread, model: "", tools: [])]
        case "item.started", "item.updated", "item.completed":
            return item(obj["item"] as? [String: Any] ?? [:], completed: type == "item.completed")
        case "turn.completed":
            let u = obj["usage"] as? [String: Any] ?? [:]
            let input = u["input_tokens"] as? Int ?? 0
            var r = ClaudeEvent.TurnResult(ok: true, text: text, sessionID: thread, costUSD: 0,
                                           inputTokens: input, outputTokens: u["output_tokens"] as? Int ?? 0,
                                           cacheReadTokens: u["cached_input_tokens"] as? Int ?? 0)
            r.contextTokens = input
            r.contextWindow = 272_000
            return [.finished(r)]
        case "turn.failed":
            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "ChatGPT не ответил"
            return [.finished(.init(ok: false, text: msg, sessionID: thread, costUSD: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0))]
        case "error":
            let msg = obj["message"] as? String ?? "ChatGPT не ответил"
            // codex пишет «Reconnecting…» как error и пробует снова — это не конец хода
            if msg.lowercased().contains("reconnecting") { return [.retry(attempt: 0, error: msg)] }
            return [.finished(.init(ok: false, text: msg, sessionID: thread, costUSD: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0))]
        default:
            return []
        }
    }

    private func item(_ it: [String: Any], completed: Bool) -> [ClaudeEvent] {
        let id = it["id"] as? String ?? UUID().uuidString
        switch it["type"] as? String {
        case "agent_message":
            guard completed, let t = it["text"] as? String, !t.isEmpty else { return [] }
            let piece = text.isEmpty ? t : "\n\n" + t
            text += piece
            return [.textDelta(piece)]
        case "command_execution":
            guard seenSteps.insert(id).inserted else { return [] }
            return [.step(AgentStep(kind: .run, text: "Запускает: " + String(Self.command(it["command"] as? String ?? "").prefix(80))))]
        case "file_change":
            guard completed, seenSteps.insert(id).inserted else { return [] }
            let changes = it["changes"] as? [[String: Any]] ?? []
            return changes.map { c in
                let name = (c["path"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
                let kind = c["kind"] as? String
                return .step(AgentStep(kind: .edit, text: (kind == "add" ? "Пишет " : (kind == "delete" ? "Удаляет " : "Правит ")) + name))
            }
        case "web_search":
            guard seenSteps.insert(id).inserted else { return [] }
            return [.step(AgentStep(kind: .web, text: "Ищет в сети: " + (it["query"] as? String ?? "")))]
        case "mcp_tool_call":
            guard seenSteps.insert(id).inserted else { return [] }
            let tool = it["tool"] as? String ?? ""
            return [.step(AgentStep(kind: .think, text: tool == "remember" ? "Запоминает" : (tool == "recall" ? "Вспоминает" : tool)))]
        case "todo_list":
            let items = it["items"] as? [[String: Any]] ?? []
            let todos = items.map { ["content": $0["text"] as? String ?? "", "status": ($0["completed"] as? Bool ?? false) ? "completed" : "pending"] }
            // первый незакрытый — «в работе»
            var plan = PlanItem.from(todos: todos)
            if let i = plan.firstIndex(where: { $0.state == .todo }), !completed { plan[i].state = .doing }
            return [.plan(.replace(plan))]
        default:
            return []
        }
    }

    /// `bash -lc 'ls -la'` → `ls -la`
    static func command(_ s: String) -> String {
        for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "bash -lc ", "zsh -lc "] where s.hasPrefix(prefix) {
            var rest = String(s.dropFirst(prefix.count))
            if rest.count >= 2, let f = rest.first, f == rest.last, f == "'" || f == "\"" { rest = String(rest.dropFirst().dropLast()) }
            return rest
        }
        return s
    }
}
