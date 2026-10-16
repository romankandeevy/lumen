import Foundation

// Кастомизация — как в Claude Code, в одной папке `customize/`:
//   skills/      навыки (папки с SKILL.md)
//   mcp.json     коннекторы: {"mcpServers": {имя: {type, command, args, env, url, headers}}}
//   hooks.json   хуки: {"hooks": {Событие: [{matcher, hooks: [{type: "command", command, timeout}]}]}}
// Файлы в формате Claude Code: их можно переносить туда и обратно. Секреты (значения env и заголовков)
// лежат в Связке ключей, в файле вместо них `${ИМЯ}` — так же Claude Code подставляет переменные окружения.

// MARK: коннекторы (MCP)

public struct MCPServer: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case stdio, http, sse }

    public var type: Kind
    public var command: String
    public var args: [String]
    public var env: [String: String]
    public var url: String
    public var headers: [String: String]
    /// Lumen: выключен — в Claude Code не передаётся (в формате Claude такого поля нет, туда оно не уходит)
    public var disabled: Bool
    /// Lumen: что это и откуда (из каталога — его описание)
    public var note: String
    /// Lumen: вход через браузер (OAuth) — токен в Связке ключей, Lumen продлевает его сам
    public var oauth: Bool = false

    public init(type: Kind = .stdio, command: String = "", args: [String] = [], env: [String: String] = [:],
                url: String = "", headers: [String: String] = [:], disabled: Bool = false, note: String = "") {
        self.type = type
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
        self.disabled = disabled
        self.note = note
    }

    public var isRemote: Bool { type != .stdio }

    /// Одной строкой — команда или адрес
    public var summary: String {
        isRemote ? url : ([command] + args).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey { case type, command, args, env, url, headers, disabled, note, oauth }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        let raw = try c.decodeIfPresent(String.self, forKey: .type)
        // у Claude Desktop типа нет вовсе; «streamable-http» — так пишет реестр MCP
        switch raw {
        case "http", "streamable-http", "streamableHttp": type = .http
        case "sse": type = .sse
        case "stdio": type = .stdio
        default: type = url.isEmpty ? .stdio : .http
        }
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.url = url
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        oauth = try c.decodeIfPresent(Bool.self, forKey: .oauth) ?? false
    }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        if isRemote {
            try c.encode(url, forKey: .url)
            if !headers.isEmpty { try c.encode(headers, forKey: .headers) }
        } else {
            try c.encode(command, forKey: .command)
            if !args.isEmpty { try c.encode(args, forKey: .args) }
            if !env.isEmpty { try c.encode(env, forKey: .env) }
        }
        if disabled { try c.encode(true, forKey: .disabled) }
        if !note.isEmpty { try c.encode(note, forKey: .note) }
        if oauth { try c.encode(true, forKey: .oauth) }
    }

    /// Как это видит Claude Code: без полей Lumen
    public var claudeJSON: [String: Any] {
        if isRemote {
            var o: [String: Any] = ["type": type.rawValue, "url": url]
            if !headers.isEmpty { o["headers"] = headers }
            return o
        }
        var o: [String: Any] = ["type": "stdio", "command": command, "args": args]
        if !env.isEmpty { o["env"] = env }
        return o
    }

    /// Имена `${…}` в env, заголовках, адресе и аргументах — их значения берутся из Связки ключей
    public var placeholders: [String] {
        let all = Array(env.values) + Array(headers.values) + [url] + args
        var out: [String] = []
        for s in all {
            var rest = Substring(s)
            while let a = rest.range(of: "${"), let b = rest[a.upperBound...].firstIndex(of: "}") {
                let name = String(rest[a.upperBound..<b])
                if !name.isEmpty, !out.contains(name) { out.append(name) }
                rest = rest[rest.index(after: b)...]
            }
        }
        return out
    }

    /// Подставить значения `${…}` (для своего клиента MCP; Claude Code подставляет сам из окружения)
    public func resolved(_ values: [String: String]) -> MCPServer {
        func sub(_ s: String) -> String {
            var s = s
            for (k, v) in values { s = s.replacingOccurrences(of: "${\(k)}", with: v) }
            return s
        }
        var m = self
        m.env = env.mapValues(sub)
        m.headers = headers.mapValues(sub)
        m.url = sub(url)
        m.args = args.map(sub)
        return m
    }

    /// Имя сервера: как в Claude Code — латиница, цифры, «-» и «_»
    public static func cleanName(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let mapped = s.trimmingCharacters(in: .whitespaces).unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var out = String(mapped).lowercased()
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return String(out.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).prefix(40))
    }

    /// Секрет ли это: значения env и заголовков с токенами, ключами, паролями
    public static func looksSecret(_ key: String) -> Bool {
        let k = key.lowercased()
        return ["token", "key", "secret", "password", "pass", "auth", "bearer", "cookie", "credential"].contains { k.contains($0) }
    }
}

public struct MCPFile: Codable, Sendable, Equatable {
    public var mcpServers: [String: MCPServer]

    public init(mcpServers: [String: MCPServer] = [:]) {
        self.mcpServers = mcpServers
    }

    public static func load(_ url: URL) -> MCPFile {
        guard let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(MCPFile.self, from: data) else { return MCPFile() }
        return f
    }

    public func save(_ url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try e.encode(self).write(to: url, options: .atomic)
    }

    /// Включённые — по имени
    public var enabled: [(name: String, server: MCPServer)] {
        mcpServers.filter { !$0.value.disabled }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

// MARK: вставка: JSON из README, `claude mcp add …`, адрес, команда

public enum ConnectorImport {
    /// Разобрать то, что человек вставил. Понимает:
    /// - `{"mcpServers": {...}}`, `{"имя": {...}}`, `{"command": …}` (Claude Code, Claude Desktop, Cursor, README);
    /// - `claude mcp add [--transport http] [-e K=V] [-H "K: V"] имя <адрес | -- команда аргументы>`;
    /// - просто адрес `https://…/mcp` или команду `npx -y пакет`.
    public static func parse(_ text: String) -> [(name: String, server: MCPServer)] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [] }
        if t.hasPrefix("{") || t.hasPrefix("\"") { return parseJSON(t) }
        if t.hasPrefix("claude mcp add") || t.hasPrefix("claude mcp add-json") { return parseClaudeAdd(t) }
        if t.hasPrefix("http://") || t.hasPrefix("https://"), !t.contains(" ") {
            return [(nameFromURL(t), MCPServer(type: t.hasSuffix("/sse") ? .sse : .http, url: t))]
        }
        let words = shellWords(t)
        guard let cmd = words.first else { return [] }
        var env: [String: String] = [:]
        var rest = Array(words.dropFirst())
        var command = cmd
        // `KEY=value npx …`
        if cmd.contains("="), !cmd.hasPrefix("-") {
            var all = words
            while let w = all.first, w.contains("="), !w.hasPrefix("-") {
                let kv = w.split(separator: "=", maxSplits: 1).map(String.init)
                env[kv[0]] = kv.count > 1 ? kv[1] : ""
                all.removeFirst()
            }
            guard let c = all.first else { return [] }
            command = c
            rest = Array(all.dropFirst())
        }
        // команда — латиницей, без мусора: «???» или фраза по-русски — не команда
        guard command.range(of: #"^[A-Za-z0-9._/~+-]+$"#, options: .regularExpression) != nil else { return [] }
        return [(nameFromCommand(command, rest), MCPServer(command: command, args: rest, env: env))]
    }

    static func parseJSON(_ t: String) -> [(String, MCPServer)] {
        var text = t
        // кусок из README бывает без внешних скобок: `"github": {...}`
        if text.hasPrefix("\"") { text = "{" + text + "}" }
        // хвостовые запятые из README
        text = text.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
        guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let servers: [String: Any]
        if let s = obj["mcpServers"] as? [String: Any] { servers = s }
        else if let s = obj["servers"] as? [String: Any] { servers = s } // VS Code
        else if let s = (obj["mcp"] as? [String: Any])?["servers"] as? [String: Any] { servers = s }
        else if obj["command"] != nil || obj["url"] != nil { servers = ["server": obj] }
        else { servers = obj }
        var out: [(String, MCPServer)] = []
        for (name, v) in servers.sorted(by: { $0.key < $1.key }) {
            guard let d = v as? [String: Any], d["command"] != nil || d["url"] != nil || d["serverUrl"] != nil,
                  let data = try? JSONSerialization.data(withJSONObject: d.mapValues { $0 }.merging(
                      d["serverUrl"].map { ["url": $0] } ?? [:]) { a, _ in a }),
                  let s = try? JSONDecoder().decode(MCPServer.self, from: data) else { continue }
            out.append((MCPServer.cleanName(name).isEmpty ? "server" : MCPServer.cleanName(name), s))
        }
        return out
    }

    static func parseClaudeAdd(_ t: String) -> [(String, MCPServer)] {
        var words = shellWords(t)
        guard words.count >= 4 else { return [] }
        words.removeFirst(3) // claude mcp add
        if words.first == "-json" || t.hasPrefix("claude mcp add-json") {
            // claude mcp add-json имя '{"type":…}'
            let w = shellWords(t).dropFirst(3)
            guard w.count >= 2, let name = w.first else { return [] }
            return parseJSON("{\"\(name)\": \(w.dropFirst().joined(separator: " "))}")
        }
        var transport = "stdio"
        var env: [String: String] = [:]
        var headers: [String: String] = [:]
        var positional: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if w == "--" { positional += words[(i + 1)...]; break }
            switch w {
            case "--transport", "-t":
                if i + 1 < words.count { transport = words[i + 1]; i += 1 }
            case "-e", "--env":
                if i + 1 < words.count {
                    let kv = words[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
                    env[kv[0]] = kv.count > 1 ? kv[1] : ""
                    i += 1
                }
            case "-H", "--header":
                if i + 1 < words.count {
                    let kv = words[i + 1].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    headers[kv[0]] = kv.count > 1 ? kv[1] : ""
                    i += 1
                }
            case "-s", "--scope", "--client-id", "--callback-port":
                i += 1
            default:
                // после имени всё — команда и её аргументы (`npx -y пакет`); до имени флаги claude пропускаем
                if !positional.isEmpty { positional.append(w) }
                else if w.hasPrefix("--transport=") { transport = String(w.dropFirst(12)) }
                else if !w.hasPrefix("-") { positional.append(w) }
            }
            i += 1
        }
        guard let name = positional.first.map(MCPServer.cleanName), !name.isEmpty, positional.count >= 2 else { return [] }
        let target = Array(positional.dropFirst())
        if transport == "http" || transport == "sse" || target[0].hasPrefix("http") {
            return [(name, MCPServer(type: transport == "sse" ? .sse : .http, url: target[0], headers: headers))]
        }
        return [(name, MCPServer(command: target[0], args: Array(target.dropFirst()), env: env))]
    }

    static func nameFromURL(_ s: String) -> String {
        guard let host = URL(string: s)?.host else { return "server" }
        let parts = host.split(separator: ".").filter { !["mcp", "api", "www", "server", "com", "ai", "io", "dev", "app", "net", "org"].contains($0) }
        return MCPServer.cleanName(String(parts.last ?? Substring(host)))
    }

    static func nameFromCommand(_ cmd: String, _ args: [String]) -> String {
        // npx -y @org/server-github → github; uvx mcp-server-fetch → fetch
        let pkg = args.first { !$0.hasPrefix("-") } ?? cmd
        let parts = pkg.split(separator: "/").map(String.init)
        var n = parts.last ?? pkg
        if let at = n.firstIndex(of: "@"), at != n.startIndex { n = String(n[..<at]) }
        // @playwright/mcp → playwright: само имя пакета ничего не говорит, говорит организация
        if ["mcp", "server", "mcp-server"].contains(n.lowercased()), parts.count > 1 {
            n = parts[parts.count - 2].trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        }
        for p in ["mcp-server-", "server-", "mcp-"] where n.hasPrefix(p) { n = String(n.dropFirst(p.count)) }
        for s in ["-mcp-server", "-mcp", "-server"] where n.hasSuffix(s) { n = String(n.dropLast(s.count)) }
        let clean = MCPServer.cleanName(n)
        return clean.isEmpty ? "server" : clean
    }

    /// Слова командной строки с кавычками
    public static func shellWords(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        var has = false
        for ch in s.replacingOccurrences(of: "\\\n", with: " ") {
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                has = true
            } else if ch == " " || ch == "\n" || ch == "\t" {
                if has || !cur.isEmpty { out.append(cur); cur = ""; has = false }
            } else {
                cur.append(ch)
            }
        }
        if has || !cur.isEmpty { out.append(cur) }
        return out
    }
}

// MARK: хуки

public enum HookEvent: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case sessionStart = "SessionStart"
    case notification = "Notification"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case sessionEnd = "SessionEnd"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preToolUse: "Перед инструментом"
        case .postToolUse: "После инструмента"
        case .userPromptSubmit: "Когда ты отправил сообщение"
        case .stop: "Когда ответ готов"
        case .sessionStart: "В начале разговора"
        case .notification: "Когда нужно твоё внимание"
        case .subagentStop: "Когда помощник закончил"
        case .preCompact: "Перед сжатием разговора"
        case .sessionEnd: "Когда разговор закрыт"
        }
    }

    public var note: String {
        switch self {
        case .preToolUse: "Можно запретить: команда выходит с кодом 2 — инструмент не запускается, текст ошибки уходит модели."
        case .postToolUse: "Например, отформатировать файл после правки."
        case .userPromptSubmit: "Код 2 — сообщение не уходит; вывод команды добавляется к сообщению как контекст."
        case .stop: "Звук, уведомление, запись в журнал."
        case .sessionStart: "Вывод команды попадает в контекст: свежий статус, заметки."
        case .notification: "Claude ждёт разрешения или ответа."
        case .subagentStop: "Помощник (Task) закончил свою часть."
        case .preCompact: "Сохранить что-то до сжатия."
        case .sessionEnd: "Уборка после разговора."
        }
    }

    /// У событий инструментов есть фильтр: имя инструмента (`Bash`, `Edit|Write`, `mcp__github__.*`)
    public var hasMatcher: Bool { self == .preToolUse || self == .postToolUse }
}

/// Один хук для окна: событие, фильтр, команда
public struct HookRule: Sendable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    public var event: HookEvent
    public var matcher: String
    public var command: String
    /// Секунды; 0 — по умолчанию Claude Code (60)
    public var timeout: Int
    public var enabled: Bool
    /// Как назвал человек (в файле — поле `name`, Claude Code его не читает)
    public var name: String

    public init(event: HookEvent, matcher: String = "", command: String, timeout: Int = 0, enabled: Bool = true, name: String = "") {
        self.event = event
        self.matcher = matcher
        self.command = command
        self.timeout = timeout
        self.enabled = enabled
        self.name = name
    }
}

public enum HooksFile {
    /// `{"hooks": {Событие: [{matcher, hooks: [{type, command, timeout}]}]}}` → плоский список
    public static func load(_ url: URL) -> [HookRule] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return parse(obj)
    }

    public static func parse(_ obj: [String: Any]) -> [HookRule] {
        let hooks = obj["hooks"] as? [String: Any] ?? obj
        var out: [HookRule] = []
        for e in HookEvent.allCases {
            for group in hooks[e.rawValue] as? [[String: Any]] ?? [] {
                let matcher = group["matcher"] as? String ?? ""
                for h in group["hooks"] as? [[String: Any]] ?? [] where (h["type"] as? String ?? "command") == "command" {
                    guard let cmd = h["command"] as? String else { continue }
                    out.append(HookRule(event: e, matcher: matcher, command: cmd, timeout: h["timeout"] as? Int ?? 0,
                                        enabled: !(h["disabled"] as? Bool ?? false), name: h["name"] as? String ?? ""))
                }
            }
        }
        return out
    }

    /// В формат Claude Code. `forClaude` — без выключенных и без полей Lumen.
    public static func json(_ rules: [HookRule], forClaude: Bool) -> [String: Any] {
        var hooks: [String: Any] = [:]
        for e in HookEvent.allCases {
            let mine = rules.filter { $0.event == e && (!forClaude || $0.enabled) }
            if mine.isEmpty { continue }
            var groups: [(String, [[String: Any]])] = []
            for r in mine {
                var h: [String: Any] = ["type": "command", "command": r.command]
                if r.timeout > 0 { h["timeout"] = r.timeout }
                if !forClaude {
                    if !r.enabled { h["disabled"] = true }
                    if !r.name.isEmpty { h["name"] = r.name }
                }
                let m = e.hasMatcher ? r.matcher : ""
                if let i = groups.firstIndex(where: { $0.0 == m }) { groups[i].1.append(h) } else { groups.append((m, [h])) }
            }
            hooks[e.rawValue] = groups.map { ["matcher": $0.0, "hooks": $0.1] as [String: Any] }
        }
        return ["hooks": hooks]
    }

    public static func save(_ rules: [HookRule], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json(rules, forClaude: false),
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

/// Готовые хуки: одним нажатием
public struct HookTemplate: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let note: String
    public let rule: HookRule

    public static let all: [HookTemplate] = [
        HookTemplate(name: "Звук, когда ответ готов", note: "Короткий «дзинь» по окончании ответа",
                     rule: HookRule(event: .stop, command: "afplay /System/Library/Sounds/Glass.aiff", name: "Звук, когда ответ готов")),
        HookTemplate(name: "Уведомление, когда ждут тебя", note: "Уведомление macOS, если нужно разрешение или ответ",
                     rule: HookRule(event: .notification,
                                    command: "osascript -e 'display notification \"Lumen ждёт тебя\" with title \"Lumen\"'",
                                    name: "Уведомление, когда ждут тебя")),
        HookTemplate(name: "Не давать удалять всё подряд", note: "Запрещает `rm -rf` в командах",
                     rule: HookRule(event: .preToolUse, matcher: "Bash",
                                    command: "python3 -c 'import json,sys,re; c=json.load(sys.stdin).get(\"tool_input\",{}).get(\"command\",\"\"); sys.exit(2 if re.search(r\"rm\\s+-[a-z]*r[a-z]*f|rm\\s+-[a-z]*f[a-z]*r\", c) else 0)' || { echo 'rm -rf запрещён хуком Lumen' >&2; exit 2; }",
                                    name: "Не давать удалять всё подряд")),
        HookTemplate(name: "Журнал команд", note: "Пишет каждую команду агента в ~/Library/Logs/lumen-commands.log",
                     rule: HookRule(event: .postToolUse, matcher: "Bash",
                                    command: "python3 -c 'import json,sys,datetime; c=json.load(sys.stdin).get(\"tool_input\",{}).get(\"command\",\"\"); open(__import__(\"os\").path.expanduser(\"~/Library/Logs/lumen-commands.log\"),\"a\").write(datetime.datetime.now().isoformat(timespec=\"seconds\")+\"  \"+c+\"\\n\")'",
                                    name: "Журнал команд")),
    ]
}

// MARK: готовые коннекторы

public struct ConnectorPreset: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let title: String
    public let note: String
    public let icon: String
    public let server: MCPServer
    /// Что спросить у человека: `${ИМЯ}` → подсказка
    public let asks: [(key: String, hint: String)]
    /// Нужна папка (подставится вместо `{folder}` в аргументах)
    public let needsFolder: Bool

    public init(name: String, title: String, note: String, icon: String, server: MCPServer,
                asks: [(key: String, hint: String)] = [], needsFolder: Bool = false) {
        self.name = name
        self.title = title
        self.note = note
        self.icon = icon
        self.server = server
        self.asks = asks
        self.needsFolder = needsFolder
    }

    /// Проверенные коннекторы: открытые серверы, без входа через браузер
    public static let popular: [ConnectorPreset] = [
        ConnectorPreset(name: "playwright", title: "Браузер (Playwright)", note: "Открывает сайты, нажимает, заполняет формы, делает снимки страниц",
                        icon: "globe", server: MCPServer(command: "npx", args: ["-y", "@playwright/mcp@latest"])),
        ConnectorPreset(name: "fetch", title: "Чтение сайтов", note: "Скачивает страницу по адресу и отдаёт текст в Markdown",
                        icon: "download", server: MCPServer(command: "npx", args: ["-y", "mcp-fetch-server"])),
        ConnectorPreset(name: "context7", title: "Документация (Context7)", note: "Свежая документация библиотек и фреймворков",
                        icon: "book-open", server: MCPServer(type: .http, url: "https://mcp.context7.com/mcp")),
        ConnectorPreset(name: "filesystem", title: "Папка с файлами", note: "Читать и править файлы в выбранной папке",
                        icon: "folder", server: MCPServer(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "{folder}"]),
                        needsFolder: true),
        ConnectorPreset(name: "github", title: "GitHub", note: "Репозитории, задачи, pull request’ы. Нужен личный токен GitHub",
                        icon: "git-branch", server: MCPServer(type: .http, url: "https://api.githubcopilot.com/mcp/",
                                                              headers: ["Authorization": "Bearer ${GITHUB_TOKEN}"]),
                        asks: [("GITHUB_TOKEN", "Токен: github.com → Settings → Developer settings → Personal access tokens")]),
        ConnectorPreset(name: "memory-graph", title: "Граф знаний", note: "Отдельная память-граф: сущности и связи между ними",
                        icon: "waypoints", server: MCPServer(command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"])),
        ConnectorPreset(name: "sequential-thinking", title: "Пошаговое мышление", note: "Помогает модели раскладывать сложные задачи по шагам",
                        icon: "list-checks", server: MCPServer(command: "npx", args: ["-y", "@modelcontextprotocol/server-sequential-thinking"])),
    ]
}

// MARK: предложения Lumen из разговора

/// Хук в виде, который можно сохранить и передать (HookRule — для окна)
public struct HookSpec: Codable, Sendable, Equatable, Hashable {
    public var event: HookEvent
    public var matcher: String
    public var command: String
    public var name: String

    public init(event: HookEvent, matcher: String = "", command: String, name: String = "") {
        self.event = event
        self.matcher = matcher
        self.command = command
        self.name = name
    }

    public var rule: HookRule { HookRule(event: event, matcher: event.hasMatcher ? matcher : "", command: command, name: name) }
}

/// Lumen предлагает коннектор или хук — карточкой под ответом; ставит человек одним нажатием.
/// Сам Lumen ничего не подключает: коннектор запускает программы на Маке, хук — команды.
public struct CustomizeProposal: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case connector, hook }
    public enum State: String, Codable, Sendable { case pending, accepted, declined }

    public var id: String
    public var kind: Kind
    public var name: String
    public var why: String
    public var server: MCPServer?
    /// Свой сервер, который написал Lumen: код ляжет в customize/servers/<имя>/
    public var script: String?
    public var scriptFile: String?
    public var hook: HookSpec?
    public var state: State

    public init(kind: Kind, name: String, why: String, server: MCPServer? = nil, script: String? = nil, scriptFile: String? = nil,
                hook: HookSpec? = nil) {
        id = UUID().uuidString.lowercased()
        self.kind = kind
        self.name = name
        self.why = why
        self.server = server
        self.script = script
        self.scriptFile = scriptFile
        self.hook = hook
        state = .pending
    }
}

/// Предложения ждут конца хода в run/proposals/<разговор>/ (их пишет и lumen-mcp, и чат по ключу)
public enum ProposalBox {
    public static func dir(_ paths: AppPaths, _ conversationID: String) -> URL {
        paths.run.appendingPathComponent("proposals/\(conversationID)", isDirectory: true)
    }

    public static func put(_ p: CustomizeProposal, paths: AppPaths, conversationID: String) throws {
        let d = dir(paths, conversationID)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try JSONEncoder().encode(p).write(to: d.appendingPathComponent("\(Date().timeIntervalSince1970)-\(p.id).json"))
    }

    /// Забрать всё, что накопилось за ход (по порядку), и очистить
    public static func take(paths: AppPaths, conversationID: String) -> [CustomizeProposal] {
        let d = dir(paths, conversationID)
        let files = ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let out = files.compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(CustomizeProposal.self, from: $0) } }
        try? FileManager.default.removeItem(at: d)
        return out
    }
}
