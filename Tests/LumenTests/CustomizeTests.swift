import AppKit
import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// Кастомизация: навыки, коннекторы MCP и хуки в одной папке, в формате Claude Code.
// Живая проверка (LUMEN_LIVE=1): Lumen через claude зовёт инструмент коннектора, хук срабатывает.

// MARK: вставка коннектора

@Test func pasteUnderstandsReadmeJSONClaudeAddURLAndCommand() {
    // JSON из README Claude Desktop, с хвостовой запятой
    let json = """
    {
      "mcpServers": {
        "github": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"],
          "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<TOKEN>" },
        },
        "Context 7": { "type": "http", "url": "https://mcp.context7.com/mcp" }
      }
    }
    """
    let a = ConnectorImport.parse(json)
    #expect(a.count == 2)
    #expect(a[0].name == "context-7" && a[0].server.type == .http && a[0].server.url == "https://mcp.context7.com/mcp")
    #expect(a[1].name == "github" && a[1].server.command == "npx" && a[1].server.args == ["-y", "@modelcontextprotocol/server-github"])
    #expect(a[1].server.env["GITHUB_PERSONAL_ACCESS_TOKEN"] == "<TOKEN>")

    // кусок без внешних скобок
    let piece = ConnectorImport.parse(#""fetch": {"command": "uvx", "args": ["mcp-server-fetch"]}"#)
    #expect(piece.first?.name == "fetch" && piece.first?.server.command == "uvx")

    // claude mcp add: сайт с заголовком
    let http = ConnectorImport.parse(#"claude mcp add --transport http sentry https://mcp.sentry.dev/mcp -H "Authorization: Bearer abc""#)
    #expect(http.first?.name == "sentry" && http.first?.server.type == .http)
    #expect(http.first?.server.headers["Authorization"] == "Bearer abc")

    // claude mcp add: программа с переменной и аргументами после --
    let stdio = ConnectorImport.parse("claude mcp add airtable -e AIRTABLE_API_KEY=key123 -- npx -y airtable-mcp-server")
    #expect(stdio.first?.name == "airtable" && stdio.first?.server.command == "npx")
    #expect(stdio.first?.server.args == ["-y", "airtable-mcp-server"] && stdio.first?.server.env["AIRTABLE_API_KEY"] == "key123")

    // просто адрес и просто команда
    #expect(ConnectorImport.parse("https://mcp.linear.app/sse").first?.server.type == .sse)
    #expect(ConnectorImport.parse("https://mcp.notion.com/mcp").first?.name == "notion")
    let cmd = ConnectorImport.parse("npx -y @playwright/mcp@latest")
    #expect(cmd.first?.name == "playwright" && cmd.first?.server.args == ["-y", "@playwright/mcp@latest"])
    #expect(ConnectorImport.parse("TOKEN=1 npx -y mcp-server-foo").first?.server.env["TOKEN"] == "1")
    #expect(ConnectorImport.parse("что-то непонятное с пробелами").isEmpty)
    #expect(ConnectorImport.parse("???").isEmpty)
    #expect(ConnectorImport.parse("   ").isEmpty)
}

@Test func connectorFileIsClaudeFormatAndSecretsArePlaceholders() throws {
    var f = MCPFile()
    f.mcpServers["github"] = MCPServer(type: .http, url: "https://api.githubcopilot.com/mcp/", headers: ["Authorization": "Bearer ${GITHUB_TOKEN}"])
    f.mcpServers["mem"] = MCPServer(command: "npx", args: ["-y", "x"], disabled: true, note: "граф")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try f.save(url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("\"mcpServers\"") && text.contains("\"type\" : \"http\""))
    #expect(MCPFile.load(url) == f)
    // выключенный в claude не уходит, поля Lumen — тоже
    #expect(f.enabled.map(\.name) == ["github"])
    #expect(f.mcpServers["mem"]!.claudeJSON["note"] == nil && f.mcpServers["mem"]!.claudeJSON["disabled"] == nil)
    #expect(f.mcpServers["github"]!.placeholders == ["GITHUB_TOKEN"])
    #expect(f.mcpServers["github"]!.resolved(["GITHUB_TOKEN": "t1"]).headers["Authorization"] == "Bearer t1")
}

@MainActor @Test func savingConnectorMovesTokensToKeychainAndBotsSeeOnlyTheirs() throws {
    setenv("LUMEN_KEYCHAIN", "com.roman.lumen.tests", 1)
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-cz-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    defer { app.keychain.delete("secret.API_KEY"); app.keychain.delete("secret.SITE_AUTHORIZATION") }

    let name = app.saveConnector(MCPServer(command: "npx", args: ["-y", "pkg"], env: ["API_KEY": "sk-123", "MODE": "fast"]), name: "tool")
    app.saveConnector(MCPServer(type: .http, url: "https://example.com/mcp", headers: ["Authorization": "Bearer abc"]), name: "site")
    let saved = MCPFile.load(app.paths.mcp)
    #expect(saved.mcpServers[name]?.env == ["API_KEY": "${API_KEY}", "MODE": "fast"])
    #expect(saved.mcpServers["site"]?.headers["Authorization"] == "Bearer ${SITE_AUTHORIZATION}")
    #expect(app.secret("API_KEY") == "sk-123" && app.secret("SITE_AUTHORIZATION") == "abc")
    #expect(!(try String(contentsOf: app.paths.mcp, encoding: .utf8)).contains("sk-123"))
    #expect(app.freeConnectorName("tool") == "tool-2" && app.freeConnectorName("lumen") == "lumen-2")

    // Lumen видит все включённые, бот — только разрешённые
    let chat = Conversation(title: "т", backend: .subscription, model: .haiku, effort: .low)
    #expect(app.connectorsFor(chat).map(\.name) == ["site", "tool"])
    app.saveBot(Bot(id: "helper", name: "Помощник", connectors: ["site"]))
    let bc = app.botConversation(for: app.bot("helper")!)
    #expect(app.connectorsFor(bc).map(\.name) == ["site"])
    #expect(BotPermissions(app.bot("helper")!).allowed.contains("mcp__site"))

    // в mcp.json для claude: lumen + коннекторы, секретов нет
    pointToMCP()
    let mcp = try app.writeMCPConfig(for: chat)
    let cfg = try String(contentsOf: mcp, encoding: .utf8)
    #expect(cfg.contains("\"lumen\"") && cfg.contains("\"site\"") && cfg.contains("${SITE_AUTHORIZATION}") && !cfg.contains("abc"))
    #expect(app.secretValues(for: app.connectorsFor(chat).map(\.server)) == ["API_KEY": "sk-123", "SITE_AUTHORIZATION": "abc"])

    // выключили — пропал из Lumen; удалили — пропал и у бота
    app.setConnector("tool", enabled: false)
    #expect(app.connectorsFor(chat).map(\.name) == ["site"])
    app.removeConnector("site")
    #expect(app.bot("helper")!.connectors.isEmpty)
}

// MARK: хуки

@Test func hooksRoundTripInClaudeFormat() throws {
    let rules = [
        HookRule(event: .preToolUse, matcher: "Bash", command: "exit 0", timeout: 10, name: "Проверка"),
        HookRule(event: .preToolUse, matcher: "Bash", command: "echo 2"),
        HookRule(event: .stop, matcher: "игнор", command: "afplay x.aiff", enabled: false),
    ]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try HooksFile.save(rules, to: url)
    let back = HooksFile.load(url)
    #expect(back.count == 3)
    #expect(back[0].name == "Проверка" && back[0].timeout == 10 && back[0].matcher == "Bash")
    #expect(back[2].event == .stop && !back[2].enabled && back[2].matcher == "")
    // для claude: одна группа на фильтр, выключенных нет, полей Lumen нет
    let c = HooksFile.json(rules, forClaude: true)["hooks"] as! [String: Any]
    let pre = c["PreToolUse"] as! [[String: Any]]
    #expect(pre.count == 1 && (pre[0]["hooks"] as! [[String: Any]]).count == 2)
    #expect(c["Stop"] == nil)
    #expect((pre[0]["hooks"] as! [[String: Any]])[0]["name"] == nil)
    // файл настроек Claude Code читается так же
    let claude: [String: Any] = ["hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": "say hi"]]]]], "theme": "dark"]
    #expect(HooksFile.parse(claude).first?.command == "say hi")
}

@MainActor @Test func hookTestRunsCommandWithEventOnStdin() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-hk-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let r = await app.testHook(HookRule(event: .preToolUse, matcher: "Bash", command: "python3 -c 'import json,sys; print(json.load(sys.stdin)[\"tool_name\"])'"))
    #expect(r.code == 0 && r.output == "Bash")
    // готовый «не удалять всё подряд» останавливает пример с rm -rf
    let guardHook = HookTemplate.all.first { $0.rule.event == .preToolUse }!.rule
    let blocked = await app.testHook(guardHook)
    #expect(blocked.code == 2)
    // есть хуки — есть файл для --settings, и он в формате Claude Code
    #expect(app.hooksSettingsFile() == nil)
    app.hooks = [HookRule(event: .stop, command: "true")]
    app.saveHooks()
    let f = try #require(app.hooksSettingsFile())
    #expect(try String(contentsOf: f, encoding: .utf8).contains("\"Stop\""))
    #expect(FileManager.default.fileExists(atPath: app.paths.hooks.path))
    var cfg = ClaudeSession.Config(model: "m")
    cfg.settings = f.path
    #expect(cfg.arguments.contains("--settings"))
}

// MARK: одна папка

@Test func oldSkillsFolderMovesIntoCustomize() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-mv-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("skills/hello", isDirectory: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try "---\nname: hello\ndescription: d\n---\n".write(to: old.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let paths = AppPaths(root: root)
    try paths.create()
    #expect(paths.skills.path.hasSuffix("customize/skills"))
    #expect(FileManager.default.fileExists(atPath: paths.skills.appendingPathComponent("hello/SKILL.md").path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("skills").path))
}

// MARK: свой клиент MCP

/// Крошечный MCP-сервер на Python: один инструмент secret_word
func tinyMCPServer(in dir: URL, word: String = "пингвин-42") throws -> MCPServer {
    let script = dir.appendingPathComponent("tiny_mcp.py")
    try """
    import json, sys
    for line in sys.stdin:
        m = json.loads(line)
        mid = m.get("id")
        if mid is None: continue
        meth = m.get("method")
        if meth == "initialize":
            r = {"protocolVersion": m["params"].get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}}, "serverInfo": {"name": "tiny", "version": "1"}}
        elif meth == "tools/list":
            r = {"tools": [{"name": "secret_word", "description": "Возвращает секретное слово дня", "inputSchema": {"type": "object", "properties": {}}}]}
        elif meth == "tools/call":
            r = {"content": [{"type": "text", "text": "\(word)"}]}
        else:
            r = {}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": r}, ensure_ascii=False) + "\\n")
        sys.stdout.flush()
    """.write(to: script, atomically: true, encoding: .utf8)
    return MCPServer(command: "python3", args: ["-u", script.path])
}

@Test func clientTalksToStdioServerAndPoolNamesTools() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-mcpc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = try tinyMCPServer(in: dir)

    let tools = try await MCPClient.probe(server).get()
    #expect(tools.map(\.name) == ["secret_word"])

    let pool = MCPPool()
    defer { pool.closeAll() }
    let errors = await pool.prepare([("tiny", server)])
    #expect(errors.isEmpty)
    let defs = pool.definitions(for: ["tiny"])
    #expect((defs.first?.value as? [String: Any])?["name"] as? String == "tiny__secret_word")
    #expect(pool.handles("tiny__secret_word"))
    #expect(await pool.call("tiny__secret_word", JSONBox([String: Any]())) == "пингвин-42")

    // не запускается — понятная ошибка, без зависания
    let bad = await MCPClient.probe(MCPServer(command: "no-such-binary-lumen"), timeout: 20)
    guard case .failure(let f) = bad else { Issue.record("должна быть ошибка"); return }
    #expect(!f.message.isEmpty)
}

// MARK: живая

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

@Suite(.serialized) struct LiveCustomizeSuite {
    /// Чат по подписке: claude видит коннектор и зовёт его без вопросов; хук «ответ готов» срабатывает
    @MainActor @Test(.enabled(if: live)) func liveChatUsesConnectorAndRunsHook() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-livecz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.saveConnector(try tinyMCPServer(in: root, word: "кашалот-7"), name: "tiny")
        let mark = root.appendingPathComponent("stop-fired")
        app.hooks = [HookRule(event: .stop, command: "touch '\(mark.path)'", name: "метка")]
        app.saveHooks()

        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("Вызови инструмент secret_word и напиши мне слово, которое он вернул. Только слово.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let reply = try #require(app.chat.messages.last)
        #expect(reply.error == nil, "\(reply.error ?? "")")
        #expect(reply.text.contains("кашалот-7"), "\(reply.text)")
        try await Task.sleep(for: .seconds(1))
        #expect(FileManager.default.fileExists(atPath: mark.path))
    }

    /// Готовые коннекторы на деле запускаются и отдают инструменты (кроме GitHub — нужен токен)
    @Test(.enabled(if: live)) func livePresetsStartAndListTools() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for preset in ConnectorPreset.popular where preset.asks.isEmpty {
            var s = preset.server
            s.args = s.args.map { $0 == "{folder}" ? dir.path : $0 }
            let r = await MCPClient.probe(s, timeout: 180)
            switch r {
            case .success(let tools): #expect(!tools.isEmpty, "\(preset.name): пусто")
            case .failure(let f): Issue.record("\(preset.name): \(f.message)")
            }
        }
    }
}

@Test func registryEntriesBecomeConnectors() {
    let npm: [String: Any] = ["name": "io.github.acme/weather", "description": "Погода",
        "packages": [["registryType": "npm", "identifier": "@acme/weather-mcp", "version": "1.2.0", "transport": ["type": "stdio"],
                      "environmentVariables": [["name": "WEATHER_KEY", "isRequired": true, "isSecret": true, "description": "ключ"]]]]]
    let e = MCPRegistry.entry(npm, uvx: false)!
    #expect(e.server.command == "npx" && e.server.args == ["-y", "@acme/weather-mcp@1.2.0"])
    #expect(e.server.env["WEATHER_KEY"] == "${WEATHER_KEY}" && e.asks.first?.key == "WEATHER_KEY")
    #expect(e.shortName == "weather")
    let remote: [String: Any] = ["name": "ai.example/docs", "remotes": [["type": "streamable-http", "url": "https://docs.example.ai/mcp",
        "headers": [["name": "Authorization", "value": "Bearer {api_key}", "isRequired": true, "isSecret": true]]]]]
    let r = MCPRegistry.entry(remote, uvx: false)!
    #expect(r.server.type == .http && r.server.headers["Authorization"] == "Bearer ${DOCS_AUTHORIZATION}")
    // PyPI без uv не предлагаем
    let py: [String: Any] = ["name": "x/y", "packages": [["registryType": "pypi", "identifier": "y-mcp", "transport": ["type": "stdio"]]]]
    #expect(MCPRegistry.entry(py, uvx: false) == nil)
}

// MARK: вход через браузер (OAuth)

final class FakeOAuthSite: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var tokenForms: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let u = request.url!
        var code = 200
        var headers = ["Content-Type": "application/json"]
        var body: [String: Any] = [:]
        switch (u.host!, u.path) {
        case ("mcp.test", "/mcp"):
            code = 401
            headers["WWW-Authenticate"] = #"Bearer realm="OAuth", resource_metadata="https://mcp.test/.well-known/oauth-protected-resource/mcp""#
        case ("mcp.test", "/.well-known/oauth-protected-resource/mcp"):
            body = ["resource": "https://mcp.test", "authorization_servers": ["https://auth.test"], "scopes_supported": ["default"]]
        case ("auth.test", "/.well-known/oauth-authorization-server"):
            body = ["authorization_endpoint": "https://auth.test/authorize", "token_endpoint": "https://auth.test/token",
                    "registration_endpoint": "https://auth.test/register"]
        case ("auth.test", "/register"):
            body = ["client_id": "cid-1"]
        case ("auth.test", "/token"):
            let form = String(decoding: request.httpBodyStream.map { s -> Data in
                s.open(); defer { s.close() }
                var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
                while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
                return d
            } ?? request.httpBody ?? Data(), as: UTF8.self)
            Self.tokenForms.append(form)
            body = form.contains("grant_type=refresh_token")
                ? ["access_token": "at-2", "expires_in": 3600]
                : ["access_token": "at-1", "refresh_token": "rt-1", "expires_in": 60]
        default:
            code = 404
        }
        let resp = HTTPURLResponse(url: u, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func oauthLoginDiscoversRegistersAndExchangesCode() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeOAuthSite.self]
    let session = URLSession(configuration: config)
    FakeOAuthSite.tokenForms = []
    // «браузер»: человек вошёл — сайт отправляет на redirect_uri с кодом и тем же state
    let t = try await MCPOAuth.login(serverURL: "https://mcp.test/mcp", session: session) { url in
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "auth.test" && q["client_id"] == "cid-1" && q["code_challenge_method"] == "S256" && q["resource"] == "https://mcp.test")
        #expect(q["redirect_uri"]?.hasPrefix("http://127.0.0.1:") == true && q["scope"] == "default")
        var back = URLComponents(string: q["redirect_uri"]!)!
        back.queryItems = [.init(name: "code", value: "c-9"), .init(name: "state", value: q["state"])]
        Task { _ = try? await URLSession.shared.data(from: back.url!) }
    }
    #expect(t.accessToken == "at-1" && t.refreshToken == "rt-1" && t.clientID == "cid-1" && t.stale)
    #expect(FakeOAuthSite.tokenForms.first?.contains("code=c-9") == true && FakeOAuthSite.tokenForms.first?.contains("code_verifier=") == true)
    let r = try await MCPOAuth.refresh(t, session: session)
    #expect(r.accessToken == "at-2" && r.refreshToken == "rt-1" && !r.stale)
}

@Test func registryNamesFromOwnerWhenPackageNameIsGeneric() {
    let e = MCPRegistry.entry(["name": "com.notion/mcp", "remotes": [["type": "streamable-http", "url": "https://mcp.notion.com/mcp"]]], uvx: false)!
    #expect(e.shortName == "notion")
}

// MARK: Lumen предлагает сам

@MainActor @Test func lumenProposesConnectorsAndHooksAndHumanAccepts() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-prop-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let c = Conversation(title: "т", backend: .subscription, model: .haiku, effort: .low)
    try app.store.save(c)

    // готовый — строкой из README; свой — кодом; хук
    var out = await CustomizeAdmin.call("propose_connector", .init(["name": "context7", "why": "Документация", "config": "https://mcp.context7.com/mcp"]),
                                        paths: app.paths, conversationID: c.id)
    #expect(out.contains("Карточка"))
    let code = try String(contentsOf: try tinyMCPServer(in: home, word: "сова-3").args[1].asURL, encoding: .utf8)
    out = await CustomizeAdmin.call("propose_connector", .init(["name": "Sova Test", "why": "Слово дня", "script": code]),
                                    paths: app.paths, conversationID: c.id)
    out = await CustomizeAdmin.call("propose_hook", .init(["event": "Stop", "command": "true", "name": "Тихий", "why": "проверка"]),
                                    paths: app.paths, conversationID: c.id)
    #expect(await CustomizeAdmin.call("propose_connector", .init(["name": "x", "why": "", "config": "???"]), paths: app.paths, conversationID: c.id).contains("Не понял"))
    #expect(app.connectors.mcpServers.isEmpty && app.hooks.isEmpty) // сам ничего не подключил

    let props = ProposalBox.take(paths: app.paths, conversationID: c.id)
    #expect(props.map(\.kind) == [.connector, .connector, .hook])
    #expect(ProposalBox.take(paths: app.paths, conversationID: c.id).isEmpty)
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "Вот")
    m.proposals = props
    m = try app.store.save(m)
    #expect(try app.store.messages(in: c.id).first?.proposals.count == 3)

    // человек нажал «Подключить» у своего сервера и «Добавить» у хука
    app.acceptProposal(props[1], in: m)
    let saved = try #require(app.connectors.mcpServers["sova-test"])
    let file = try #require(saved.args.last)
    #expect(FileManager.default.fileExists(atPath: file) && file.contains("customize/servers/"))
    #expect(try await MCPClient.probe(saved).get().first?.name == "secret_word")
    m = try #require(try app.store.messages(in: c.id).first)
    app.acceptProposal(m.proposals[2], in: m)
    #expect(app.hooks.first?.name == "Тихий")
    let after = try #require(try app.store.messages(in: c.id).first).proposals
    #expect(after[1].state == .accepted && after[2].state == .accepted && after[0].state == .pending)

    // список видит подключённое
    let list = await CustomizeAdmin.call("list_customization", .init([:]), paths: app.paths, conversationID: c.id)
    #expect(list.contains("python3") && list.contains("Тихий"))
}

private extension String { var asURL: URL { URL(fileURLWithPath: self) } }

extension LiveCustomizeSuite {
    /// «Сделай MCP» в чате: Lumen пишет свой сервер и показывает карточку; после «Подключить» сервер работает
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveLumenWritesOwnConnector() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-liveprop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.chat.set(model: .sonnet, effort: .low)
        app.chat.send("Сделай мне свой MCP-коннектор dice с одним инструментом roll, который возвращает случайное число от 1 до 6.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let reply = try #require(app.chat.messages.last)
        #expect(reply.error == nil, "\(reply.error ?? "")")
        let pr = try #require(reply.proposals.first { $0.kind == .connector }, "нет карточки: \(reply.text)")
        #expect(pr.script != nil)
        app.acceptProposal(pr, in: reply)
        let s = try #require(app.connectors.mcpServers.values.first)
        let tools = try await MCPClient.probe(s).get()
        #expect(tools.contains { $0.name == "roll" }, "\(tools.map(\.name))")
    }
}

extension LiveCustomizeSuite {
    /// Пока Lumen отвечает в одном чате, в новом можно писать — оба ответа приходят
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveTwoChatsAnswerAtOnce() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-par-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("Посчитай вслух от 1 до 40 через запятую.")
        let a = try #require(app.chat.conversation)
        try await Task.sleep(for: .milliseconds(300))
        #expect(app.chat.busy)
        app.chat.startNew()
        #expect(!app.chat.busy)
        app.chat.send("Ответь одним словом: привет")
        let b = try #require(app.chat.conversation)
        #expect(a.id != b.id && app.chat.isRunning(a.id) && app.chat.isRunning(b.id))
        while !app.chat.turns.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
        let la = try #require(try app.store.messages(in: a.id).last)
        let lb = try #require(try app.store.messages(in: b.id).last)
        #expect(la.role == .assistant && la.error == nil && la.text.contains("40"))
        #expect(lb.role == .assistant && lb.error == nil && !lb.text.isEmpty)
    }
}

// MARK: действия у сообщений

@MainActor @Test func chapterPersistsAndTimeReadsHuman() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let c = Conversation(title: "т", backend: .subscription, model: .haiku, effort: .low)
    try app.store.save(c)
    _ = try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "## План на неделю\nподробности"))
    app.openChat(c)
    let m = try #require(app.chat.messages.first)
    app.chat.toggleChapter(m)
    #expect(try app.store.messages(in: c.id).first?.chapter == true)
    #expect(ChapterMark.title(app.chat.messages[0]) == "План на неделю")
    #expect(MessageActions.when(Date()) == "сейчас")
    #expect(MessageActions.when(Date().addingTimeInterval(-86_400 * 400)).contains(","))
    // ClaudeEvent отдаёт метку сообщения и откат идёт флагом
    let line = Data(#"{"type":"assistant","uuid":"u-1","message":{"content":[{"type":"text","text":"x"}]}}"#.utf8)
    #expect(ClaudeEvent.decodeAll(line).contains(.anchor("u-1")))
    var cfg = ClaudeSession.Config(model: "m", resume: true)
    cfg.resumeAt = "u-1"
    #expect(cfg.arguments.joined(separator: " ").contains("--resume-session-at u-1"))
}

extension LiveCustomizeSuite {
    /// «Изменить» откатывает и саму сессию claude: модель не помнит то, что было после
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveEditRewindsClaudeSession() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.chat.set(model: .haiku, effort: .low)
        for t in ["Кодовое слово — ЛИМОН. Ответь: ок", "Новое кодовое слово — АРБУЗ. Ответь: ок"] {
            app.chat.send(t)
            while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        }
        #expect(app.chat.messages.last?.cliAnchor != nil)
        let second = try #require(app.chat.messages.last { $0.role == .user })
        app.chat.resend(from: second, text: "Какое сейчас кодовое слово? Одним словом.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let reply = try #require(app.chat.messages.last)
        #expect(app.chat.messages.count == 4)
        #expect(reply.error == nil && reply.text.uppercased().contains("ЛИМОН") && !reply.text.uppercased().contains("АРБУЗ"), "\(reply.text)")
    }
}

extension LiveCustomizeSuite {
    /// «@бот» без задачи и с картинкой: бот отвечает сам и видит картинку
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveBareMentionWithImageReachesBot() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-bare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.saveBot(Bot(id: "eye", name: "Глаз", role: "Описывает картинки", model: .haiku, effort: .low))
        // картинка: красный квадрат
        let img = NSImage(size: NSSize(width: 64, height: 64))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); img.unlockFocus()
        let a = try #require(app.importImage(img, name: "квадрат"))
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("@eye какого цвета квадрат? одним словом", attachments: [a])
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let r1 = try #require(app.chat.messages.last)
        #expect(r1.botID == "eye" && r1.error == nil)
        #expect(r1.text.lowercased().contains("красн"), "\(r1.text)")
        app.chat.send("@eye")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let r2 = try #require(app.chat.messages.last)
        #expect(r2.botID == "eye" && r2.error == nil && !r2.text.isEmpty)
    }
}

extension LiveCustomizeSuite {
    /// «Стоп» в чате посреди ответа: ход кончается быстро, ответ помечен «Остановлено», дальше можно писать
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveChatStopButtonStops() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-stop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("Напиши очень длинный рассказ про море, 3000 слов.")
        // ждём, пока пойдёт текст
        let start = Date()
        while app.chat.streaming == nil && Date().timeIntervalSince(start) < 30 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(app.chat.busy)
        let t = Date()
        app.chat.stop()
        while app.chat.busy && Date().timeIntervalSince(t) < 10 { try await Task.sleep(for: .milliseconds(50)) }
        print("DBG stop took", Date().timeIntervalSince(t))
        #expect(!app.chat.busy)
        #expect(app.chat.messages.last?.stopped == true)
        app.chat.send("Ответь одним словом: да")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        #expect(app.chat.messages.last?.error == nil && app.chat.messages.last?.stopped == false)
    }
}

extension LiveCustomizeSuite {
    /// «Стоп» сразу, пока claude ещё запускается («Думает…»): ход всё равно кончается
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveChatStopWhileStarting() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-stop0-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.saveConnector(MCPServer(command: "npx", args: ["-y", "@playwright/mcp@latest"]), name: "playwright")
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("Напиши очень длинный рассказ про море, 3000 слов.")
        try await Task.sleep(for: .milliseconds(300))
        let t = Date()
        app.chat.stop()
        while app.chat.busy && Date().timeIntervalSince(t) < 20 { try await Task.sleep(for: .milliseconds(50)) }
        print("DBG stop-early took", Date().timeIntervalSince(t), app.chat.messages.last?.text.count as Any)
        #expect(!app.chat.busy)
    }
}

@MainActor @Test func lumenGetsWhatBotsSaidWhileItWasAway() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-unseen-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.saveBot(Bot(id: "designer", name: "Дизайнер"))
    let c = Conversation(title: "т", backend: .subscription, model: .haiku, effort: .low)
    var bot = ChatMessage(conversationID: c.id, role: .assistant, text: "Беру вариант А")
    bot.botID = "designer"
    let h = [ChatMessage(conversationID: c.id, role: .user, text: "@designer что думаешь?"), bot,
             ChatMessage(conversationID: c.id, role: .user, text: "люмен согласен?")]
    let ctx = app.chat.unseenContext(h, c)
    #expect(ctx.contains("@designer (Дизайнер): Беру вариант А") && ctx.contains("@designer что думаешь?") && !ctx.contains("люмен согласен"))
    // Lumen уже ответил после бота — повторять не надо
    let seen = h.prefix(2) + [ChatMessage(conversationID: c.id, role: .assistant, text: "Согласен"), h[2]]
    #expect(app.chat.unseenContext(Array(seen), c).isEmpty)
    // в истории для API ответ бота подписан
    #expect((AnthropicChatRequest.history([bot]).first?["content"] as? String)?.hasPrefix("[Это ответил бот @designer") == true)
}

extension LiveCustomizeSuite {
    /// «люмен согласен?» после ответа бота: Lumen видит, что сказал бот
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveLumenSeesBotReply() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-seebot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.saveBot(Bot(id: "pick", name: "Выбиральщик", role: "Выбирает цвет", instructions: "На любой вопрос отвечай ровно: «Выбираю цвет БИРЮЗОВЫЙ».", model: .haiku, effort: .low))
        app.chat.set(model: .haiku, effort: .low)
        app.chat.send("@pick какой цвет взять?")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        app.chat.send("Lumen, какой цвет выбрал бот? Одним словом.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let r = try #require(app.chat.messages.last)
        #expect(r.botID == nil && r.text.uppercased().contains("БИРЮЗ"), "\(r.text)")
    }
}
