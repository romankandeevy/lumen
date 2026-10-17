import Foundation
import LumenCore
import LumenProviders
import LumenStorage

// lumen-mcp — stdio MCP-сервер Lumen (§0, §7 техплана): память для claude.
// Окружение: LUMEN_DB — путь к базе, LUMEN_CONVERSATION_ID / LUMEN_CONVERSATION_TITLE — откуда факты.
// LUMEN_MEMORY_READONLY=1 — бот без права писать в память: remember не показывается и не выполняется
// (вторая линия защиты после --allowedTools, техплан §4.3).
// Протокол — JSON-RPC 2.0 построчно; нужны только initialize, tools/list, tools/call.

let env = ProcessInfo.processInfo.environment
guard let dbPath = env["LUMEN_DB"], let store = try? Store(path: URL(fileURLWithPath: dbPath)) else {
    FileHandle.standardError.write(Data("lumen-mcp: нет LUMEN_DB или база не открылась\n".utf8))
    exit(1)
}
var tools = MemoryTools(store: store, conversationID: env["LUMEN_CONVERSATION_ID"] ?? "",
                        conversationTitle: env["LUMEN_CONVERSATION_TITLE"] ?? "Разговор")
let readOnly = env["LUMEN_MEMORY_READONLY"] == "1"
// навыки: LUMEN_SKILLS_DIR — библиотека, LUMEN_SKILLS — «*» (все включённые) или имена через запятую
if let dir = env["LUMEN_SKILLS_DIR"], !dir.isEmpty {
    tools.skills = SkillLibrary(root: URL(fileURLWithPath: dir))
    let only = env["LUMEN_SKILLS"] ?? "*"
    tools.allowedSkills = only == "*" ? nil : Set(only.split(separator: ",").map(String.init))
}
var visible = MemoryTools.definitions.filter { !readOnly || $0.name != "remember" }
if !tools.availableSkills.isEmpty { visible += MemoryTools.skillDefinitions }

// delegate (§4.6): бот с правом «Звать других ботов» передаёт часть задачи другому боту.
// Только один шаг: у позванного бота LUMEN_DEPTH=1, и delegate у него нет.
let callerID = env["LUMEN_BOT_ID"] ?? ""
let depth = Int(env["LUMEN_DEPTH"] ?? "0") ?? 0
let caller = callerID.isEmpty ? nil : (try? store.bots())?.first { $0.id == callerID }
// звать ботов могут боты с этим правом и сам Lumen (чат и агент; у него LUMEN_BOT_ID пустой)
let canDelegate = (caller?.can.contains(.bots) == true || callerID.isEmpty) && depth < 1
    && !((try? store.bots()) ?? []).isEmpty
// Lumen достраивает себя сам (Рома, 16.10): смотрит, создаёт, находит на skills.sh и ставит навыки.
// Остальным ботам — нет: их навыки выбирает человек.
// …и боты с правом «Навыки и коннекторы» (Рома, 17.10: «Конструктор скиллов» не видел каталог)
let manageSkills = tools.skills != nil && (callerID.isEmpty || caller?.can.contains(.skills) == true)
if manageSkills { visible += SkillAdmin.definitions + CustomizeAdmin.definitions }

/// Дождаться асинхронного (сеть) внутри синхронного цикла сервера
final class TextBox: @unchecked Sendable { var value = "" }

func wait(_ work: @escaping @Sendable () async -> String) -> String {
    let box = TextBox()
    let done = DispatchSemaphore(value: 0)
    // отдельная задача, не на главном потоке: главный ждёт её здесь
    Task.detached { box.value = await work(); done.signal() }
    done.wait()
    return box.value
}

@MainActor func manageSkill(_ name: String, _ args: [String: Any]) -> String {
    guard let lib = tools.skills else { return "Навыки недоступны." }
    let a = SkillAdmin.Args(args)
    return wait { await SkillAdmin.call(name, a, library: lib) }
}

// встроенный браузер (панель сбоку) — у всех: Lumen, агента и ботов (Рома, 17.10). LUMEN_BROWSER=0 — выключить.
let browserOn = env["LUMEN_BROWSER"] != "0"
if browserOn { visible += BrowserTools.definitions }
let browserSocket = AppPaths(root: URL(fileURLWithPath: dbPath).deletingLastPathComponent()).browserSocket.path
let browserWho = caller.map { "@\($0.id)" } ?? "Lumen"

if canDelegate {
    visible.append(("delegate", "Передать часть задачи другому боту Lumen и дождаться его ответа. Указывай задачу полностью: бот не видит этот разговор.",
                    ["type": "object", "additionalProperties": false, "required": ["bot", "task"],
                     "properties": ["bot": ["type": "string", "description": "id бота без @"],
                                    "task": ["type": "string", "description": "Что сделать, с нужным контекстом"]]]))
}

/// Запустить позванного бота отдельным процессом claude с его правами и дождаться ответа
func delegate(_ args: [String: Any]) -> String {
    guard canDelegate else { return "Звать других ботов отсюда нельзя." }
    let id = (args["bot"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
    let task = (args["task"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let bots = (try? store.bots()) ?? []
    guard let target = bots.first(where: { $0.id == id }), target.id != caller?.id else {
        return "Нет такого бота: @\(id). Есть: " + bots.map { "@\($0.id)" }.joined(separator: ", ") + "."
    }
    guard !task.isEmpty else { return "Пустая задача." }
    guard let cli = ClaudeCLI.locate() else { return "Claude Code не найден." }
    let root = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
    let paths = AppPaths(root: root)
    var folder = paths.run.appendingPathComponent("bots/\(target.id)", isDirectory: true)
    if let f = target.folder, FileManager.default.fileExists(atPath: f) { folder = URL(fileURLWithPath: f) }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    var conv = (try? store.conversations())?.first { $0.kind == .bot && $0.botID == target.id }
    // у бота ещё нет своего разговора — создаём, как Lumen: задача и ответ должны остаться у него
    if conv == nil {
        var c = Conversation(title: target.name, kind: .bot, folder: folder.path, backend: store.preferences.backend,
                             model: target.model, effort: target.effort, cliSessionID: UUID().uuidString.lowercased())
        c.botID = target.id
        if (try? store.save(c)) != nil { conv = c }
    }
    let library = SkillLibrary(root: paths.skills)
    let perms = BotPermissions(target)
    let profile = store.profile
    let rules = target.rules(handoff: nil, userName: profile.name, ty: profile.address == .ty,
                             skills: SkillLibrary.promptBlock(library.enabled(only: Set(target.skills))))
    // MCP позванного бота: его память и навыки, глубина 1 — дальше звать нельзя
    let runDir = paths.run.appendingPathComponent("delegate-\(UUID().uuidString.lowercased())", isDirectory: true)
    try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: runDir) }
    var servers: [String: Any] = ["lumen": [
        "command": CommandLine.arguments[0], "args": [],
        "env": ["LUMEN_DB": dbPath, "LUMEN_CONVERSATION_ID": conv?.id ?? "", "LUMEN_CONVERSATION_TITLE": target.name,
                "LUMEN_MEMORY_READONLY": target.can.contains(.memory) ? "0" : "1",
                "LUMEN_SKILLS_DIR": paths.skills.path, "LUMEN_SKILLS": target.skills.joined(separator: ","),
                "LUMEN_BOT_ID": target.id, "LUMEN_DEPTH": "1"],
    ]]
    // коннекторы, разрешённые позванному боту (секреты `${…}` claude возьмёт из окружения)
    let file = MCPFile.load(paths.mcp)
    for (name, s) in file.enabled where target.connectors.contains(name) { servers[name] = s.claudeJSON }
    let mcp: [String: Any] = ["mcpServers": servers]
    let mcpURL = runDir.appendingPathComponent("mcp.json")
    try? JSONSerialization.data(withJSONObject: mcp).write(to: mcpURL)
    var config = ClaudeSession.Config(model: target.model.rawValue, effort: target.effort.rawValue, tools: perms.tools, userSettings: false,
                                      cwd: folder, appendSystemPrompt: rules,
                                      allowedTools: perms.allowed.filter { $0 != "mcp__lumen__delegate" }, disallowedTools: perms.disallowed)
    config.mcpConfig = mcpURL.path
    if file.enabled.contains(where: { target.connectors.contains($0.name) }), let t = config.tools, !t.contains("ToolSearch") {
        config.tools = t + ["ToolSearch"]
        config.allowedTools.append("ToolSearch")
    }
    let from = caller.map { "@\($0.id) — бот «\($0.name)»" } ?? "Lumen, разговор «\(env["LUMEN_CONVERSATION_TITLE"] ?? "")»"
    let asked = Via.modelText(task: task, from: from, context: "")

    final class Box: @unchecked Sendable { var text = "" }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    Task {
        do {
            let session = try ClaudeSession(cli: cli, config: config)
            let r = try await session.ask(asked)
            box.text = r.ok ? r.text : "Бот @\(target.id) не справился: \(r.text)"
            session.close()
        } catch {
            box.text = "Бот @\(target.id) не запустился: \(error.localizedDescription)"
        }
        done.signal()
    }
    done.wait()
    // в постоянный разговор позванного бота — задача и ответ
    if let conv {
        var q = ChatMessage(conversationID: conv.id, role: .user, text: task)
        q.via = caller.map { Via(title: "@\($0.id)") }
            ?? Via(conversationID: env["LUMEN_CONVERSATION_ID"], title: env["LUMEN_CONVERSATION_TITLE"] ?? "Lumen")
        _ = try? store.save(q)
        var m = ChatMessage(conversationID: conv.id, role: .assistant, text: box.text, model: target.model)
        m.botID = target.id
        _ = try? store.save(m)
    }
    // позвал Lumen — ответ бота виден в его чате отдельным сообщением, со знаком и цветом бота (как при «@id …»)
    if caller == nil, let chatID = env["LUMEN_CONVERSATION_ID"], !chatID.isEmpty {
        var shown = ChatMessage(conversationID: chatID, role: .assistant, text: box.text, model: target.model)
        shown.botID = target.id
        if (try? store.save(shown)) != nil {
            return "Ответ @\(target.id) человек уже видит в чате отдельным сообщением бота. Не повторяй, не пересказывай и не упоминай, "
                + "что он показан. Если есть что добавить по сути — одной-двумя фразами; если нечего — ответь пустым сообщением.\n\nЧто он ответил (для тебя):\n\(box.text)"
        }
    }
    return "@\(target.id) ответил:\n\(box.text)"
}

func reply(_ id: Any, _ result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func send(_ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

while let line = readLine(strippingNewline: true) {
    guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
    let id = msg["id"]
    let params = msg["params"] as? [String: Any] ?? [:]
    switch msg["method"] as? String {
    case "initialize":
        reply(id ?? 0, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                        "capabilities": ["tools": [:]],
                        "serverInfo": ["name": "lumen", "version": "1"]])
    case "tools/list":
        reply(id ?? 0, ["tools": visible.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        if manageSkills, CustomizeAdmin.names.contains(name) {
            let a = CustomizeAdmin.Args(args)
            let paths = AppPaths(root: URL(fileURLWithPath: dbPath).deletingLastPathComponent())
            let conv = env["LUMEN_CONVERSATION_ID"] ?? ""
            reply(id ?? 0, ["content": [["type": "text", "text": wait { await CustomizeAdmin.call(name, a, paths: paths, conversationID: conv) }]]])
            continue
        }
        if SkillAdmin.names.contains(name) {
            reply(id ?? 0, ["content": [["type": "text", "text": manageSkill(name, args)]]])
            continue
        }
        if browserOn, BrowserTools.names.contains(name) {
            let r = BrowserClient.call(socket: browserSocket, tool: name, args: args, who: browserWho, conv: env["LUMEN_CONVERSATION_ID"] ?? "")
            var content: [[String: Any]] = [["type": "text", "text": r.text]]
            if let png = r.image { content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]) }
            var out: [String: Any] = ["content": content]
            if r.error { out["isError"] = true }
            reply(id ?? 0, out)
            continue
        }
        if name == "delegate" {
            reply(id ?? 0, ["content": [["type": "text", "text": delegate(args)]]])
            continue
        }
        if readOnly && name == "remember" {
            reply(id ?? 0, ["content": [["type": "text", "text": "Этому боту запрещено писать в память."]], "isError": true])
            continue
        }
        do {
            let text = try tools.call(name, args)
            reply(id ?? 0, ["content": [["type": "text", "text": text]]])
        } catch {
            reply(id ?? 0, ["content": [["type": "text", "text": "Ошибка памяти: \(error.localizedDescription)"]], "isError": true])
        }
    case "ping":
        reply(id ?? 0, [:])
    default:
        // уведомления (без id) молча пропускаем, на неизвестные запросы — пустой ответ
        if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found"]]) }
    }
}
