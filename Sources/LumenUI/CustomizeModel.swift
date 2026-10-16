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
        let server = s.resolved(secretValues(for: [s]))
        let session = urlSession
        Task {
            let r = await MCPClient.probe(server, session: session)
            switch r {
            case .success(let tools): connectorStatus[name] = .ok(tools)
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
