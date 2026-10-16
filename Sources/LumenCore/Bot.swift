import Foundation

/// Бот — агент под одну роль (техплан §4). Роль задают не словами, а набором возможностей:
/// чего нет в наборе, того нет в процессе бота вообще — модель даже не видит такого инструмента.
/// У бота один постоянный разговор; позвать его можно из любого чата через @id.
public struct Bot: Codable, Sendable, Equatable, Identifiable, Hashable {
    /// То, что пишут после @: латиница, цифры, дефис
    public var id: String
    public var name: String
    /// Иконка из Resources/Icons (lucide)
    public var icon: String
    /// Свой цвет, чтобы бот не путался с Lumen: оттенок 0…360
    public var hue: Double
    /// Роль одной строкой
    public var role: String
    public var instructions: String
    public var capabilities: Set<BotCapability>
    /// Какие команды можно запускать, если «Править файлы» не разрешено (`swift test`, `./build.sh` …)
    public var commands: [String]
    /// Рабочая папка (без неё бот работает в своей пустой папке)
    public var folder: String?
    public var model: ChatModel
    public var effort: Effort
    /// Готовые просьбы на пустом экране бота
    public var starters: [String]
    /// Кому передавать то, что не по роли (@id)
    public var handoff: String?
    /// Навыки бота (имена из библиотеки навыков)
    public var skills: [String] = []
    /// Чему бот научился на прошлых задачах — попадает в его правила (§4.4)
    public var learned: [String] = []
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, name: String, icon: String = "bot", hue: Double = 200, role: String = "", instructions: String = "",
                capabilities: Set<BotCapability> = [.read], commands: [String] = [], folder: String? = nil,
                model: ChatModel = .sonnet, effort: Effort = .medium, starters: [String] = [], handoff: String? = nil,
                skills: [String] = [], learned: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.skills = skills
        self.learned = learned
        self.id = id
        self.name = name
        self.icon = icon
        self.hue = hue
        self.role = role
        self.instructions = instructions
        self.capabilities = capabilities
        self.commands = commands
        self.folder = folder
        self.model = model
        self.effort = effort
        self.starters = starters
        self.handoff = handoff
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// @id: 2–32 знака, латиница в нижнем регистре, цифры, дефис; не «lumen»
    public static func isValidID(_ s: String) -> Bool {
        s.range(of: #"^[a-z0-9][a-z0-9-]{1,31}$"#, options: .regularExpression) != nil && s != "lumen"
    }

    /// Иконки, из которых выбирают знак бота
    public static let icons = ["bot", "flask-conical", "palette", "code-xml", "pen-line", "sunrise", "bug", "book-open",
                               "shield-check", "rocket", "chart-column", "languages", "graduation-cap", "lightbulb",
                               "list-checks", "globe", "terminal", "wrench", "sparkles", "brain"]

    /// Команды для бота «запускать без правки»: сборка, тесты и только чтение git
    public static let defaultCommands = ["swift build", "swift test", "./build.sh", "xcodebuild", "npm test", "npm run build",
                                         "git status", "git diff", "git log", "ls", "cat"]
}

extension Bot {
    /// Правила бота: роль, что ему доступно и что отрезано, чему научился, кому передавать чужое
    public func rules(handoff: Bot?, userName: String, ty: Bool, skills: String?, bots: [Bot] = []) -> String {
        var lines = ["Ты — бот «\(name)» (@\(id)) в Lumen, приложении на Маке. Твоя роль: \(role)."]
        if !instructions.isEmpty { lines.append(instructions) }
        let granted = BotCapability.allCases.filter { capabilities.contains($0) }.map(\.name)
        lines.append("Тебе доступно: \(granted.isEmpty ? "только разговор" : granted.joined(separator: ", ")). "
            + "Отрезано в коде: \(BotPermissions.blocked(self).joined(separator: ", ")). Этих инструментов у тебя нет — не пытайся обойти.")
        if capabilities.contains(.run) && !capabilities.contains(.write) && !commands.isEmpty {
            lines.append("Команды можно запускать только такие: \(commands.joined(separator: ", ")).")
        }
        if capabilities.contains(.bots) {
            let others = bots.filter { $0.id != id }
            if !others.isEmpty {
                lines.append("Если часть задачи не по твоей роли, передай её инструментом delegate одному из ботов и дождись ответа:\n"
                    + others.map { "- @\($0.id): \($0.role)" }.joined(separator: "\n"))
            }
        }
        if !learned.isEmpty {
            lines.append("Чему ты научился на прошлых задачах (учитывай):\n" + learned.map { "- \($0)" }.joined(separator: "\n"))
        }
        let to = handoff.map { "@\($0.id) (\($0.name))" } ?? "Lumen"
        lines.append("Если просят то, что не по роли, — коротко откажись и предложи передать это \(to). Не делай чужую работу наполовину.")
        lines.append("Push, публикацию и выкатку не делай: это только человек.")
        if !userName.isEmpty { lines.append("Собеседника зовут \(userName), обращайся на \(ty ? "«ты»" : "«вы»").") }
        if let skills { lines.append(skills) }
        lines.append("Отвечай по-русски, коротко и по делу: что сделал, что нашёл, что дальше.")
        return lines.joined(separator: "\n")
    }
}

/// Что боту разрешено. Push на GitHub не разрешается никому: его делает человек.
public enum BotCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case read, write, run, web, git, memory, bots

    public var name: String {
        switch self {
        case .read: "Читать файлы"
        case .write: "Править файлы"
        case .run: "Запускать команды"
        case .web: "Интернет"
        case .git: "Git: коммит"
        case .memory: "Писать в память"
        case .bots: "Звать других ботов"
        }
    }

    public var icon: String {
        switch self {
        case .read: "file-text"
        case .write: "pencil"
        case .run: "terminal"
        case .web: "globe"
        case .git: "git-commit-horizontal"
        case .memory: "brain"
        case .bots: "at-sign"
        }
    }
}

/// Как набор возможностей становится флагами `claude`: список инструментов, что можно без вопросов, что нельзя никогда.
/// Режим `dontAsk`: всё, чего нет в разрешённом, отклоняется без вопроса.
public struct BotPermissions: Sendable, Equatable {
    /// `--tools`: какие инструменты вообще существуют для бота
    public var tools: [String]
    /// `--allowedTools`
    public var allowed: [String]
    /// `--disallowedTools`: запрещено даже при обходе разрешений
    public var disallowed: [String]
    /// lumen-mcp не даёт `remember`
    public var memoryReadOnly: Bool

    public init(_ bot: Bot) {
        let can = bot.capabilities
        var tools: [String] = []
        var allowed: [String] = []
        if can.contains(.read) || can.contains(.write) {
            tools += ["Read", "Glob", "Grep"]
            allowed += ["Read", "Glob", "Grep"]
        }
        if can.contains(.write) {
            tools += ["Edit", "Write", "MultiEdit", "NotebookEdit"]
            allowed += ["Edit", "Write", "MultiEdit", "NotebookEdit"]
        }
        if can.contains(.run) || can.contains(.git) {
            tools.append("Bash")
            if can.contains(.run) && can.contains(.write) {
                // правит файлы и так — команды без белого списка
                allowed.append("Bash")
            } else {
                // команды без права правки: только из белого списка, иначе `echo > file` обошёл бы запрет
                if can.contains(.run) { allowed += bot.commands.map { "Bash(\($0):*)" } }
                if can.contains(.git) {
                    allowed += ["Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git add:*)", "Bash(git commit:*)"]
                }
            }
        }
        if can.contains(.web) {
            tools += ["WebSearch", "WebFetch"]
            allowed += ["WebSearch", "WebFetch"]
        }
        // план работы — безвредно и помогает в длинных задачах
        if !tools.isEmpty {
            tools += ["TodoWrite"]
            allowed += ["TodoWrite"]
        }
        self.tools = tools
        self.allowed = allowed + ["mcp__lumen__recall", "mcp__lumen__load_skill", "mcp__lumen__read_skill_file"]
            + (can.contains(.memory) ? ["mcp__lumen__remember"] : []) + (can.contains(.bots) ? ["mcp__lumen__delegate"] : [])
        self.memoryReadOnly = !can.contains(.memory)
        var never = ["Bash(git push:*)", "Bash(git push)"]
        if !can.contains(.git) { never += ["Bash(git commit:*)", "Bash(git reset:*)", "Bash(git checkout:*)"] }
        self.disallowed = never
    }

    /// «Отрезано в коде» — для паспорта бота
    public static func blocked(_ bot: Bot) -> [String] {
        BotCapability.allCases.filter { !bot.capabilities.contains($0) }.map(\.name) + ["Push на GitHub"]
    }
}
