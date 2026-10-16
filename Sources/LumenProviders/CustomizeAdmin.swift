import Foundation
import LumenCore

/// Lumen про свои коннекторы и хуки: посмотреть, найти в реестре MCP, предложить коннектор (готовый или свой сервер)
/// и хук. Предложение — карточка под ответом; подключает человек (общий код для lumen-mcp и чата по ключу API).
public enum CustomizeAdmin {
    public static let names: Set<String> = ["list_customization", "find_connectors", "propose_connector", "propose_hook"]

    nonisolated(unsafe) public static let definitions: [(name: String, description: String, schema: [String: Any])] = [
        ("list_customization", "Что подключено в Lumen: коннекторы MCP (сайты и программы) и хуки.",
         ["type": "object", "properties": [String: Any]()]),
        ("find_connectors", "Найти готовый коннектор (MCP-сервер) в официальном реестре MCP. Запрос — по-английски, одно-два слова.",
         ["type": "object", "additionalProperties": false, "required": ["query"],
          "properties": ["query": ["type": "string", "description": "Например: notion, postgres, weather"]]]),
        ("propose_connector", """
         Предложить человеку подключить коннектор MCP — он увидит карточку под твоим ответом и нажмёт «Подключить». \
         Готовый: config — JSON с mcpServers, строка «claude mcp add …», адрес https://…/mcp или команда «npx -y пакет». \
         Свой: script — полный код MCP-сервера на Python 3 без внешних библиотек (JSON-RPC 2.0 построчно через stdin/stdout: \
         initialize → {protocolVersion, capabilities:{tools:{}}, serverInfo}, tools/list → {tools:[{name, description, inputSchema}]}, \
         tools/call → {content:[{type:"text", text}]}; на уведомления без id не отвечать; печатать с flush). \
         Токены не выдумывай: пиши ${ИМЯ_ТОКЕНА}, человек впишет сам.
         """,
         ["type": "object", "additionalProperties": false, "required": ["name", "why"],
          "properties": ["name": ["type": "string", "description": "Короткое имя латиницей: notion, weather"],
                         "why": ["type": "string", "description": "Одной фразой по-русски: что он даст"],
                         "config": ["type": "string", "description": "Для готового коннектора"],
                         "script": ["type": "string", "description": "Для своего: код server.py"]]]),
        ("propose_hook", """
         Предложить хук — команду, которую Claude Code сам запускает на событие; человек нажмёт «Добавить». \
         События: PreToolUse и PostToolUse (matcher — имя инструмента: Bash, Edit|Write), UserPromptSubmit, Stop, SessionStart, \
         Notification, SubagentStop, PreCompact, SessionEnd. Команда идёт в sh, на вход — JSON события; в PreToolUse код выхода 2 запрещает инструмент.
         """,
         ["type": "object", "additionalProperties": false, "required": ["event", "command", "name", "why"],
          "properties": ["event": ["type": "string", "enum": HookEvent.allCases.map(\.rawValue)],
                         "matcher": ["type": "string"], "command": ["type": "string"],
                         "name": ["type": "string", "description": "Название по-русски"],
                         "why": ["type": "string", "description": "Одной фразой: что он делает"]]]),
    ]

    public struct Args: @unchecked Sendable {
        let value: [String: Any]
        public init(_ v: [String: Any]) { value = v }
        func str(_ k: String) -> String { (value[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public static func call(_ name: String, _ a: Args, paths: AppPaths, conversationID: String, session: URLSession = .shared) async -> String {
        switch name {
        case "list_customization":
            let f = MCPFile.load(paths.mcp)
            let hooks = HooksFile.load(paths.hooks)
            var lines = ["Коннекторы:"]
            lines += f.mcpServers.isEmpty ? ["— нет"] : f.mcpServers.sorted { $0.key < $1.key }.map {
                "- \($0.key)\($0.value.disabled ? " (выключен)" : ""): \($0.value.summary)\($0.value.note.isEmpty ? "" : " — \($0.value.note)")"
            }
            lines.append("Хуки:")
            lines += hooks.isEmpty ? ["— нет"] : hooks.map {
                "- \($0.event.title)\($0.matcher.isEmpty ? "" : " [\($0.matcher)]")\($0.enabled ? "" : " (выключен)"): \($0.name.isEmpty ? $0.command : $0.name)"
            }
            return lines.joined(separator: "\n")

        case "find_connectors":
            let q = a.str("query")
            guard !q.isEmpty else { return "Пустой запрос." }
            do {
                let found = try await MCPRegistry.search(q, session: session).prefix(8)
                if found.isEmpty { return "В реестре MCP ничего не нашлось по «\(q)»." }
                return found.map { e in
                    let cfg = e.server.isRemote ? e.server.url : e.server.summary
                    return "- \(e.shortName): \(e.description.prefix(160)) · config: \(cfg)" + (e.asks.isEmpty ? "" : " · нужно: " + e.asks.map(\.key).joined(separator: ", "))
                }.joined(separator: "\n") + "\nПредложи подходящий через propose_connector (config — как выше)."
            } catch {
                return "Реестр MCP не ответил."
            }

        case "propose_connector":
            let n = MCPServer.cleanName(a.str("name"))
            guard !n.isEmpty, n != "lumen" else { return "Нужно имя латиницей." }
            let why = a.str("why")
            let script = a.str("script")
            var p: CustomizeProposal
            if !script.isEmpty {
                let file = paths.customize.appendingPathComponent("servers/\(n)/server.py").path
                p = CustomizeProposal(kind: .connector, name: n, why: why,
                                      server: MCPServer(command: "python3", args: ["-u", file], note: why), script: script, scriptFile: file)
            } else {
                guard let parsed = ConnectorImport.parse(a.str("config")).first else {
                    return "Не понял config: нужен JSON с mcpServers, «claude mcp add …», адрес https://… или команда."
                }
                var s = parsed.server
                if s.note.isEmpty { s.note = why }
                p = CustomizeProposal(kind: .connector, name: n, why: why, server: s)
            }
            do { try ProposalBox.put(p, paths: paths, conversationID: conversationID) } catch { return "Не получилось показать предложение." }
            return "Карточка «Подключить \(n)» будет под твоим ответом — подключит человек. Не говори, что уже подключено."

        case "propose_hook":
            guard let e = HookEvent(rawValue: a.str("event")) else { return "Неизвестное событие." }
            let cmd = a.str("command")
            guard !cmd.isEmpty else { return "Пустая команда." }
            let spec = HookSpec(event: e, matcher: a.str("matcher"), command: cmd, name: a.str("name"))
            let p = CustomizeProposal(kind: .hook, name: spec.name, why: a.str("why"), hook: spec)
            do { try ProposalBox.put(p, paths: paths, conversationID: conversationID) } catch { return "Не получилось показать предложение." }
            return "Карточка «Добавить хук» будет под твоим ответом — добавит человек. Не говори, что уже добавлено."

        default:
            return "Нет такого инструмента."
        }
    }
}
