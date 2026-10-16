import AppKit
import Foundation
import LumenCore
import LumenProviders

// Кастомизация: коннекторы MCP и хуки (навыки — SkillModel.swift). Файлы — в customize/, в формате Claude Code.
// Секреты коннекторов — в Связке ключей под именем переменной (`secret.GITHUB_TOKEN`), в mcp.json — `${GITHUB_TOKEN}`.

enum CustomizeTab: Hashable { case skills, connectors, hooks }

/// Что показала проверка коннектора
enum ConnectorStatus: Equatable {
    case checking
    case ok([MCPClient.Tool])
    case failed(String)
    /// Сайт просит войти — кнопка «Войти через браузер»
    case needsLogin
}

extension AppModel {
    // MARK: коннекторы

    func reloadCustomize() {
        connectors = MCPFile.load(paths.mcp)
        hooks = HooksFile.load(paths.hooks)
    }

    private func saveConnectors() {
        do { try connectors.save(paths.mcp) } catch { log("Не сохранился mcp.json: \(error.localizedDescription)") }
        chat.restartIdle()
        mcpPool.closeAll()
    }

    /// Уникальное имя: github, github-2…
    func freeConnectorName(_ base: String) -> String {
        let clean = MCPServer.cleanName(base).isEmpty ? "server" : MCPServer.cleanName(base)
        var name = clean
        var i = 2
        while connectors.mcpServers[name] != nil || name == "lumen" { name = "\(clean)-\(i)"; i += 1 }
        return name
    }

    /// Сохранить коннектор. Значения env и заголовков с токенами уходят в Связку ключей, в файле — `${ИМЯ}`.
    @discardableResult
    func saveConnector(_ server: MCPServer, name: String, replacing old: String? = nil) -> String {
        var s = server
        let prefix = name.uppercased().replacingOccurrences(of: "-", with: "_")
        for (k, v) in s.env where !v.isEmpty && !v.hasPrefix("${") && MCPServer.looksSecret(k) {
            setSecret(k, v)
            s.env[k] = "${\(k)}"
        }
        for (k, v) in s.headers where !v.isEmpty && !v.contains("${") {
            // «Bearer abc» → «Bearer ${GITHUB_AUTHORIZATION}»: слово схемы остаётся видно
            let parts = v.split(separator: " ", maxSplits: 1).map(String.init)
            let scheme = parts.count == 2 && ["bearer", "token", "basic"].contains(parts[0].lowercased()) ? parts[0] + " " : ""
            let secret = scheme.isEmpty ? v : parts[1]
            let key = prefix + "_" + k.uppercased().replacingOccurrences(of: "-", with: "_")
            setSecret(key, secret)
            s.headers[k] = scheme + "${\(key)}"
        }
        if let old, old != name { connectors.mcpServers[old] = nil; connectorStatus[old] = nil }
        connectors.mcpServers[name] = s
        saveConnectors()
        return name
    }

    func setConnector(_ name: String, enabled: Bool) {
        guard var s = connectors.mcpServers[name] else { return }
        s.disabled = !enabled
        connectors.mcpServers[name] = s
        saveConnectors()
    }

    func removeConnector(_ name: String) {
        if connectors.mcpServers[name]?.oauth == true {
            keychain.delete("oauth.\(name)")
            keychain.delete("secret.\(Self.oauthSecret(name))")
        }
        connectors.mcpServers[name] = nil
        connectorStatus[name] = nil
        // боты, которым он был разрешён, его теряют
        for var b in bots where b.connectors.contains(name) {
            b.connectors.removeAll { $0 == name }
            saveBot(b)
        }
        saveConnectors()
    }

    func secret(_ name: String) -> String? { keychain.read("secret.\(name)") }

    func setSecret(_ name: String, _ value: String) {
        try? keychain.save(value, for: "secret.\(name)")
    }

    /// Значения `${…}` для коннекторов (из Связки ключей; чего нет — из окружения Lumen)
    func secretValues(for servers: [MCPServer]) -> [String: String] {
        var out: [String: String] = [:]
        for s in servers {
            for k in s.placeholders {
                if let v = secret(k) ?? ProcessInfo.processInfo.environment[k] { out[k] = v }
            }
        }
        return out
    }

    /// Каких секретов не хватает
    func missingSecrets(_ s: MCPServer) -> [String] {
        s.placeholders.filter { secret($0) == nil && ProcessInfo.processInfo.environment[$0] == nil }
    }

    /// Проверить: запустить, получить список инструментов
    func checkConnector(_ name: String) {
        guard let s = connectors.mcpServers[name] else { return }
        connectorStatus[name] = .checking
        let session = urlSession
        Task {
            _ = await freshenOAuth([(name, s)])
            let server = s.resolved(secretValues(for: [s]))
            let r = await MCPClient.probe(server, session: session)
            switch r {
            case .success(let tools): connectorStatus[name] = .ok(tools)
            case .failure(let f) where f.needsAuth: connectorStatus[name] = .needsLogin
            case .failure(let f):
                connectorStatus[name] = .failed(f.message)
                log("Коннектор \(name) не прошёл проверку: \(f.message)")
            }
        }
    }

    /// Коннекторы для разговора: у Lumen и агента — все включённые, у бота — только разрешённые ему
    func connectorsFor(_ c: Conversation) -> [(name: String, server: MCPServer)] {
        let on = connectors.enabled
        if c.kind == .bot { return on.filter { bot(c.botID)?.connectors.contains($0.name) == true } }
        return on
    }

    // MARK: вход через браузер (OAuth)

    /// Имя секрета с токеном: OAUTH_NOTION
    static func oauthSecret(_ name: String) -> String {
        "OAUTH_" + name.uppercased().replacingOccurrences(of: "-", with: "_")
    }

    /// Войти в сайт коннектора через браузер. Возвращает коннектор с заголовком `Bearer ${OAUTH_…}`.
    func loginConnector(_ name: String, server: MCPServer) async throws -> MCPServer {
        let t = try await MCPOAuth.login(serverURL: server.url, session: urlSession)
        storeTokens(t, for: name)
        var s = server
        s.oauth = true
        s.headers["Authorization"] = "Bearer ${\(Self.oauthSecret(name))}"
        return s
    }

    /// Войти у уже сохранённого коннектора и проверить
    func loginSaved(_ name: String) async {
        guard let s = connectors.mcpServers[name] else { return }
        connectorStatus[name] = .checking
        do {
            let updated = try await loginConnector(name, server: s)
            connectors.mcpServers[name] = updated
            saveConnectors()
            checkConnector(name)
        } catch {
            connectorStatus[name] = .failed((error as? MCPClient.Failure)?.message ?? error.localizedDescription)
        }
    }

    func storeTokens(_ t: MCPOAuth.Tokens, for name: String) {
        if let d = try? JSONEncoder().encode(t) { try? keychain.save(String(decoding: d, as: UTF8.self), for: "oauth.\(name)") }
        setSecret(Self.oauthSecret(name), t.accessToken)
    }

    /// Продлить токены, которые скоро истекут. true — что-то продлили (живые процессы надо перезапустить).
    func freshenOAuth(_ list: [(name: String, server: MCPServer)]) async -> Bool {
        var changed = false
        for (name, s) in list where s.oauth {
            guard let raw = keychain.read("oauth.\(name)"), let t = try? JSONDecoder().decode(MCPOAuth.Tokens.self, from: Data(raw.utf8)),
                  t.stale else { continue }
            do {
                storeTokens(try await MCPOAuth.refresh(t, session: urlSession), for: name)
                changed = true
            } catch {
                log("Коннектор \(name): не продлился вход — \((error as? MCPClient.Failure)?.message ?? error.localizedDescription)")
            }
        }
        return changed
    }

    // MARK: предложения Lumen

    /// Подключить то, что предложил Lumen: коннектор (свой сервер — сначала код в customize/servers/) или хук
    func acceptProposal(_ pr: CustomizeProposal, in message: ChatMessage) {
        switch pr.kind {
        case .connector:
            guard var s = pr.server else { return }
            var name = freeConnectorName(pr.name)
            if let code = pr.script {
                let dir = paths.customize.appendingPathComponent("servers/\(name)", isDirectory: true)
                let file = dir.appendingPathComponent("server.py")
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try code.write(to: file, atomically: true, encoding: .utf8)
                } catch {
                    log("Не записался код коннектора \(name): \(error.localizedDescription)")
                    return
                }
                s.args = ["-u", file.path]
            }
            name = saveConnector(s, name: name)
            checkConnector(name)
            var accepted = pr
            accepted.name = name
            replaceProposal(accepted, state: .accepted, in: message)
        case .hook:
            guard let h = pr.hook else { return }
            hooks.append(h.rule)
            saveHooks()
            setProposal(pr.id, .accepted, in: message)
        }
    }

    func setProposal(_ id: String, _ state: CustomizeProposal.State, in message: ChatMessage) {
        guard let pr = message.proposals.first(where: { $0.id == id }) else { return }
        replaceProposal(pr, state: state, in: message)
    }

    private func replaceProposal(_ pr: CustomizeProposal, state: CustomizeProposal.State, in message: ChatMessage) {
        guard let mid = message.id else { return }
        var list = (chat.messages.first { $0.id == mid } ?? message).proposals
        guard let i = list.firstIndex(where: { $0.id == pr.id }) else { return }
        var next = pr
        next.state = state
        list[i] = next
        chat.setProposals(list, messageID: mid, conversationID: message.conversationID)
    }

    // MARK: хуки

    func saveHooks() {
        do { try HooksFile.save(hooks, to: paths.hooks) } catch { log("Не сохранился hooks.json: \(error.localizedDescription)") }
        chat.restartIdle()
    }

    /// Файл настроек с хуками для `claude --settings` (только включённые); nil — хуков нет
    func hooksSettingsFile() -> URL? {
        guard hooks.contains(where: \.enabled) else { return nil }
        let url = paths.run.appendingPathComponent("hooks-settings.json")
        guard let data = try? JSONSerialization.data(withJSONObject: HooksFile.json(hooks, forClaude: true), options: [.prettyPrinted]),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// «Проверить» хук: запустить команду с примером того, что пришлёт Claude Code
    func testHook(_ r: HookRule) async -> (code: Int32, output: String) {
        var sample: [String: Any] = ["session_id": "test", "hook_event_name": r.event.rawValue, "cwd": NSHomeDirectory()]
        switch r.event {
        case .preToolUse, .postToolUse:
            let tool = r.matcher.split(separator: "|").first.map(String.init) ?? "Bash"
            sample["tool_name"] = tool.contains("*") || tool.isEmpty ? "Bash" : tool
            sample["tool_input"] = ["command": "rm -rf ./build", "file_path": NSHomeDirectory() + "/example.txt"]
        case .userPromptSubmit: sample["prompt"] = "Пример сообщения"
        case .notification: sample["message"] = "Claude ждёт разрешения"
        default: break
        }
        let input = (try? JSONSerialization.data(withJSONObject: sample)) ?? Data()
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", r.command]
            p.environment = Shell.env
            let inp = Pipe(), out = Pipe()
            p.standardInput = inp
            p.standardOutput = out
            p.standardError = out
            p.terminationHandler = { proc in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: (proc.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try p.run()
                inp.fileHandleForWriting.write(input)
                try? inp.fileHandleForWriting.close()
            } catch {
                cont.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    /// Открыть папку кастомизации в Finder
    func revealCustomize() {
        NSWorkspace.shared.open(paths.customize)
    }
}
