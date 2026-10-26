import Foundation
import LumenCore

/// Свой клиент MCP: проверить коннектор («Проверить» — какие у него инструменты) и дать его инструменты
/// чату по ключу API. В разговорах через Claude Code коннекторы подключает сам claude (`--mcp-config`).
/// Транспорты: stdio (команда), streamable HTTP и старый SSE.
public final class MCPClient: @unchecked Sendable {
    public struct Tool: Sendable, Equatable {
        public let name: String
        public let description: String
        /// inputSchema как есть
        public let schema: JSONBox

        public static func == (a: Tool, b: Tool) -> Bool { a.name == b.name && a.description == b.description }
    }

    public struct Failure: Error, LocalizedError {
        public let message: String
        /// Сайт просит войти (401/403) — поможет «Войти через браузер»
        public var needsAuth = false
        public init(_ m: String, needsAuth: Bool = false) { message = m; self.needsAuth = needsAuth }
        public var errorDescription: String? { message }
    }

    private let server: MCPServer
    private let session: URLSession
    private let lock = NSLock()
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<Reply, Error>] = [:]

    /// Ответ JSON-RPC (словарь не Sendable — обёртка)
    struct Reply: @unchecked Sendable { let obj: [String: Any] }
    // stdio
    private var process: Process?
    private var input: FileHandle?
    private var stderrTail = ""
    // http
    private var sessionID: String?
    private var protocolVersion = "2025-06-18"
    // sse
    private var sseEndpoint: URL?
    private var sseTask: Task<Void, Never>?

    /// `server` — уже с подставленными секретами (`MCPServer.resolved`)
    public init(server: MCPServer, session: URLSession = .shared) {
        self.server = server
        self.session = session
    }

    deinit { close() }

    // MARK: общее

    /// Подключиться и поздороваться
    public func start(timeout: Double = 60) async throws {
        switch server.type {
        case .stdio: try startProcess()
        case .sse: try await startSSE()
        case .http: break
        }
        let r = try await request("initialize", ["protocolVersion": protocolVersion, "capabilities": [:] as [String: Any],
                                                 "clientInfo": ["name": "Lumen", "version": "1.0"]], timeout: timeout)
        if let v = r["protocolVersion"] as? String { protocolVersion = v }
        try await notify("notifications/initialized")
    }

    public func listTools() async throws -> [Tool] {
        var out: [Tool] = []
        var cursor: String?
        repeat {
            let r = try await request("tools/list", cursor.map { ["cursor": $0] } ?? [:])
            for t in r["tools"] as? [[String: Any]] ?? [] {
                guard let name = t["name"] as? String else { continue }
                out.append(Tool(name: name, description: t["description"] as? String ?? "",
                                schema: JSONBox(t["inputSchema"] as? [String: Any] ?? ["type": "object"])))
            }
            cursor = r["nextCursor"] as? String
        } while cursor != nil && out.count < 500
        return out
    }

    /// Вызвать инструмент; ответ — текстом (картинки и прочее — пометкой)
    public func call(_ tool: String, _ arguments: [String: Any], timeout: Double = 300) async throws -> (text: String, isError: Bool) {
        let r = try await request("tools/call", ["name": tool, "arguments": arguments], timeout: timeout)
        var parts: [String] = []
        for c in r["content"] as? [[String: Any]] ?? [] {
            switch c["type"] as? String {
            case "text": parts.append(c["text"] as? String ?? "")
            case "image": parts.append("[картинка \(c["mimeType"] as? String ?? "")]")
            case "resource":
                let res = c["resource"] as? [String: Any]
                parts.append(res?["text"] as? String ?? "[ресурс \(res?["uri"] as? String ?? "")]")
            case "resource_link": parts.append("[ссылка \(c["uri"] as? String ?? "")]")
            default: break
            }
        }
        if parts.isEmpty, let s = r["structuredContent"],
           let d = try? JSONSerialization.data(withJSONObject: s), let t = String(data: d, encoding: .utf8) { parts.append(t) }
        return (parts.joined(separator: "\n"), r["isError"] as? Bool ?? false)
    }

    public func close() {
        lock.lock()
        let p = process
        process = nil
        let pending = waiting
        waiting = [:]
        lock.unlock()
        sseTask?.cancel()
        if let p, p.isRunning { p.terminate() }
        for (_, c) in pending { c.resume(throwing: Failure("Коннектор закрыт")) }
    }

    private func take() -> Int {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return nextID
    }

    private func request(_ method: String, _ params: [String: Any], timeout: Double = 60) async throws -> [String: Any] {
        let id = take()
        let msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let reply: [String: Any]
        if server.type == .http {
            reply = try await postHTTP(msg, expect: id, timeout: timeout)
        } else {
            let timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                if !Task.isCancelled { self?.resolve(id, error: Failure("Коннектор не ответил за \(Int(timeout)) с")) }
            }
            defer { timer.cancel() }
            reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Reply, Error>) in
                lock.lock()
                waiting[id] = c
                lock.unlock()
                do { try sendRaw(msg) } catch { resolve(id, error: error) }
            }.obj
        }
        if let e = reply["error"] as? [String: Any] {
            throw Failure(e["message"] as? String ?? "Ошибка коннектора")
        }
        return reply["result"] as? [String: Any] ?? [:]
    }

    private func notify(_ method: String) async throws {
        let msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if server.type == .http { _ = try? await postHTTP(msg, expect: nil, timeout: 15) } else { try sendRaw(msg) }
    }

    private func resolve(_ id: Int, with reply: [String: Any]? = nil, error: Error? = nil) {
        lock.lock()
        let c = waiting.removeValue(forKey: id)
        lock.unlock()
        if let error { c?.resume(throwing: error) } else if let reply { c?.resume(returning: Reply(obj: reply)) }
    }

    private func handle(_ obj: [String: Any]) {
        // ответы на наши запросы; запросы сервера к нам (ping, sampling) — пустым ответом
        if let id = obj["id"] as? Int, obj["method"] == nil {
            resolve(id, with: obj)
        } else if let id = obj["id"], let method = obj["method"] as? String {
            let reply: [String: Any] = method == "ping" ? ["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]]
                : ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Lumen этого не умеет"]]
            try? sendRaw(reply)
        }
    }

    private func sendRaw(_ msg: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: msg)
        switch server.type {
        case .stdio:
            lock.lock()
            let h = input
            lock.unlock()
            guard let h else { throw Failure("Коннектор не запущен") }
            try h.write(contentsOf: data + Data([0x0A]))
        case .sse:
            guard let endpoint = sseEndpoint else { throw Failure("Коннектор не дал адрес для сообщений") }
            var r = URLRequest(url: endpoint)
            r.httpMethod = "POST"
            r.httpBody = data
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in server.headers { r.setValue(v, forHTTPHeaderField: k) }
            Task { _ = try? await session.data(for: r) }
        case .http:
            break
        }
    }

    // MARK: stdio

    private func startProcess() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [server.command] + server.args
        p.environment = Shell.env.merging(server.env) { $1 }
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let inp = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inp
        p.standardOutput = out
        p.standardError = err
        let lines = LineBuffer()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            for line in lines.append(chunk) {
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { self.handle(obj) }
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard let self, !s.isEmpty else { return }
            self.lock.lock()
            self.stderrTail = String((self.stderrTail + s).suffix(2000))
            self.lock.unlock()
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            self.lock.lock()
            let pending = self.waiting
            self.waiting = [:]
            let tail = self.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lock.unlock()
            let why = tail.split(separator: "\n").last.map(String.init) ?? "код \(proc.terminationStatus)"
            for (_, c) in pending { c.resume(throwing: Failure("Коннектор завершился: \(why)")) }
        }
        do { try p.run() } catch { throw Failure("Не запустилась команда «\(server.command)»: \(error.localizedDescription)") }
        lock.lock()
        process = p
        input = inp.fileHandleForWriting
        lock.unlock()
    }

    // MARK: streamable HTTP

    private func postHTTP(_ msg: [String: Any], expect id: Int?, timeout: Double) async throws -> [String: Any] {
        guard let url = URL(string: server.url) else { throw Failure("Неверный адрес: \(server.url)") }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.httpBody = try JSONSerialization.data(withJSONObject: msg)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { r.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        for (k, v) in server.headers { r.setValue(v, forHTTPHeaderField: k) }
        let (bytes, response) = try await session.bytes(for: r)
        let http = response as? HTTPURLResponse
        if let s = http?.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = s }
        let status = http?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw Failure("Сайт просит войти (\(status)).", needsAuth: true)
        }
        guard let id else { return [:] }
        if status >= 400 { throw Failure("Сайт ответил ошибкой \(status)") }
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if type.contains("text/event-stream") {
            for try await line in bytes.lines where line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], obj["id"] as? Int == id {
                    return obj
                }
            }
            throw Failure("Сайт закрыл поток без ответа")
        }
        var data = Data()
        for try await b in bytes { data.append(b) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("Сайт ответил не по протоколу MCP")
        }
        return obj
    }

    // MARK: старый SSE

    private func startSSE() async throws {
        guard let url = URL(string: server.url) else { throw Failure("Неверный адрес: \(server.url)") }
        var r = URLRequest(url: url)
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in server.headers { r.setValue(v, forHTTPHeaderField: k) }
        let (bytes, response) = try await session.bytes(for: r)
        if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw Failure(code == 401 || code == 403 ? "Сайт просит войти (\(code))." : "Сайт ответил ошибкой \(code)", needsAuth: code == 401 || code == 403)
        }
        let ready = AsyncStream<URL>.makeStream()
        sseTask = Task { [weak self] in
            var event = ""
            do {
                for try await line in bytes.lines {
                    guard let self else { return }
                    if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                    else if line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if event == "endpoint", let u = URL(string: payload, relativeTo: url) { ready.continuation.yield(u.absoluteURL) }
                        else if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] { self.handle(obj) }
                    }
                }
            } catch {}
            ready.continuation.finish()
        }
        for await u in ready.stream { sseEndpoint = u; return }
        throw Failure("Сайт не прислал адрес для сообщений")
    }
}

// MARK: проверка коннектора

extension MCPClient {
    /// Запустить, получить инструменты, закрыть
    public static func probe(_ server: MCPServer, session: URLSession = .shared, timeout: Double = 90) async -> Result<[Tool], Failure> {
        let c = MCPClient(server: server, session: session)
        defer { c.close() }
        do {
            try await c.start(timeout: timeout)
            return .success(try await c.listTools())
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(Failure(error.localizedDescription))
        }
    }
}

// MARK: коннекторы для чата по ключу API

/// Живые клиенты коннекторов: держатся между ходами (npx стартует секунды), пересоздаются, если коннектор поменялся.
/// Инструменты видны модели как `сервер__инструмент`.
public final class MCPPool: @unchecked Sendable {
    private struct Live { let server: MCPServer; let client: MCPClient; let tools: [MCPClient.Tool] }
    private var live: [String: Live] = [:]
    private var failed: [String: (MCPServer, String)] = [:]
    private let lock = NSLock()
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    /// Подключить нужные коннекторы (уже с секретами). Ошибки — в списке: модель о них не узнает, Lumen запишет в журнал.
    public func prepare(_ list: [(name: String, server: MCPServer)]) async -> [String] {
        var errors: [String] = []
        for (name, server) in list {
            let (have, bad) = lock.withLock { (live[name], failed[name]) }
            if let have, have.server == server { continue }
            if let bad, bad.0 == server { errors.append("\(name): \(bad.1)"); continue }
            have?.client.close()
            let c = MCPClient(server: server, session: session)
            do {
                try await c.start(timeout: 90)
                let tools = try await c.listTools()
                lock.withLock { live[name] = Live(server: server, client: c, tools: tools); failed[name] = nil }
            } catch {
                c.close()
                let msg = (error as? MCPClient.Failure)?.message ?? error.localizedDescription
                lock.withLock { live[name] = nil; failed[name] = (server, msg) }
                errors.append("\(name): \(msg)")
            }
        }
        return errors
    }

    /// Определения инструментов для API (только перечисленных коннекторов)
    public func definitions(for names: [String]) -> [JSONBox] {
        lock.lock(); defer { lock.unlock() }
        var out: [JSONBox] = []
        for n in names {
            guard let l = live[n] else { continue }
            for t in l.tools {
                out.append(JSONBox(["name": Self.apiName(n, t.name), "description": String(t.description.prefix(1024)),
                                    // MCP-схемы не знают про strict API: у каждого object — additionalProperties: false
                                    "input_schema": AnthropicAPI.strict(t.schema.value)]))
            }
        }
        return out
    }

    public func handles(_ apiName: String) -> Bool { target(apiName) != nil }

    public func call(_ apiName: String, _ input: JSONBox) async -> String {
        guard let (client, tool) = target(apiName) else { return "Нет такого инструмента" }
        do {
            let r = try await client.call(tool, input.value as? [String: Any] ?? [:])
            return r.isError ? "Ошибка: " + r.text : (r.text.isEmpty ? "Готово" : String(r.text.prefix(100_000)))
        } catch {
            return "Коннектор не ответил: " + ((error as? MCPClient.Failure)?.message ?? error.localizedDescription)
        }
    }

    public func closeAll() {
        lock.lock()
        let all = live.values.map(\.client)
        live = [:]
        failed = [:]
        lock.unlock()
        all.forEach { $0.close() }
    }

    private func target(_ apiName: String) -> (MCPClient, String)? {
        lock.lock(); defer { lock.unlock() }
        for (n, l) in live {
            if let t = l.tools.first(where: { Self.apiName(n, $0.name) == apiName }) { return (l.client, t.name) }
        }
        return nil
    }

    /// Имя для API: латиница, цифры, «_» и «-», не длиннее 64
    public static func apiName(_ server: String, _ tool: String) -> String {
        let raw = server + "__" + tool
        let ok = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" ? Character($0) : "_" }
        return String(String(ok).prefix(64))
    }
}
