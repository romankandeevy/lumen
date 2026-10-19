import Foundation

/// Модели Claude, которые Lumen предлагает в чате (как в макете, `lib/mock-data.ts`)
public enum ChatModel: String, Codable, Sendable, CaseIterable, Identifiable {
    case fable = "claude-fable-5-1"
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    // ChatGPT через codex по подписке ChatGPT (каталог `codex debug models`, октябрь 2026)
    case gptAstra = "gpt-6-astra"
    case gptSol = "gpt-6.1-sol"
    case gptLuna = "gpt-6-luna"

    public static let claude: [ChatModel] = [.fable, .opus, .sonnet, .haiku]
    public static let gpt: [ChatModel] = [.gptAstra, .gptSol, .gptLuna]

    /// Отвечает ChatGPT (через codex), а не Claude
    public var isGPT: Bool { Self.gpt.contains(self) }

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .fable: "Fable 5.1"
        case .opus: "Opus 5.5"
        case .sonnet: "Sonnet 5.5"
        case .haiku: "Haiku 5.5"
        case .gptAstra: "GPT-6 Astra"
        case .gptSol: "GPT-6.1 Sol"
        case .gptLuna: "GPT-6 Luna"
        }
    }

    public var note: String {
        switch self {
        case .fable: "самый сильный, для сложного"
        case .opus: "умный, для кода и разбора"
        case .sonnet: "быстрый, на каждый день"
        case .haiku: "мгновенный и дешёвый"
        case .gptAstra: "ChatGPT: самый сильный"
        case .gptSol: "ChatGPT: код и каждый день"
        case .gptLuna: "ChatGPT: быстрый, для простого"
        }
    }

    /// Если модель откажется отвечать по правилам безопасности, API сам доотвечает другой моделью.
    /// У Haiku такого нет.
    public var hasServerFallback: Bool { self != .haiku && !isGPT }

    /// Цены API за миллион токенов: вход, выход, чтение кэша (платформа Anthropic, октябрь 2026)
    public var price: (input: Double, output: Double, cacheRead: Double) {
        switch self {
        case .fable: (10, 50, 0.25)
        case .opus: (4, 20, 0.20)
        case .sonnet: (2, 10, 0.20)
        case .haiku: (0.10, 0.50, 0.01)
        // ChatGPT — по подписке, за токены не платим
        case .gptAstra, .gptSol, .gptLuna: (0, 0, 0)
        }
    }

    /// Стоимость хода по API в долларах; запись в кэш — 1,25 цены входа
    public func cost(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let p = price
        return (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * p.cacheRead
                + Double(cacheWrite) * p.input * 1.25) / 1_000_000
    }
}

/// «Сколько думать» — effort, одинаковый у CLI и API
public enum Effort: String, Codable, Sendable, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .low: "Низкий"
        case .medium: "Средний"
        case .high: "Высокий"
        case .xhigh: "Сверхвысокий"
        case .max: "Максимальный"
        }
    }

    public var note: String {
        switch self {
        case .low: "быстрые ответы на простое"
        case .medium: "обычные вопросы и правки"
        case .high: "код и разбор"
        case .xhigh: "сложные баги, большие правки"
        case .max: "самое трудное, думает долго"
        }
    }

    public var level: Int { Effort.allCases.firstIndex(of: self) ?? 0 }
}

/// Работа позванного бота прямо сейчас: кто, что уже написал и какие шаги сделал (файл run/live-<разговор>.json)
public struct LiveWork: Codable, Sendable, Equatable {
    public var bot: String
    public var text: String
    public var steps: [AgentStep]
    public var started: Date
    public init(bot: String, text: String = "", steps: [AgentStep] = [], started: Date = Date()) {
        self.bot = bot
        self.text = text
        self.steps = steps
        self.started = started
    }
}

/// Прежний вариант ответа: что было написано и сделано
public struct AnswerVariant: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var steps: [AgentStep]
    public var attachments: [Attachment]
    public var error: String?
    public var model: ChatModel?
    public var createdAt: Date
    public init(text: String, steps: [AgentStep], attachments: [Attachment], error: String?, model: ChatModel?, createdAt: Date) {
        self.text = text
        self.steps = steps
        self.attachments = attachments
        self.error = error
        self.model = model
        self.createdAt = createdAt
    }

    public init(_ m: ChatMessage) {
        self.init(text: m.text, steps: m.steps, attachments: m.attachments, error: m.error, model: m.model, createdAt: m.createdAt)
    }
}

/// Откуда пришло сообщение в разговор бота: чат, где его позвали через @, или другой бот
public struct Via: Codable, Sendable, Equatable, Hashable {
    public var conversationID: String?
    public var title: String
    /// Позвал другой бот («@id»), а не человек из чата: у чата есть id, у бота — нет,
    /// и название чата тоже может начинаться с «@» («@designer привет»)
    public var fromBot: Bool { conversationID == nil && title.hasPrefix("@") && !title.contains(" ") }
    /// Сообщение подтянуто из Claude Code (перенесённый разговор догоняет то, что написано там)
    public static let claudeCode = Via(conversationID: nil, title: "Claude Code")
    public var isClaudeCode: Bool { self == Self.claudeCode }
    /// Сообщение отправил сам Lumen за человека: утро, «меня нет — реши сам», «лимит сбросился» (19.10)
    public static func auto(_ why: String) -> Via { Via(conversationID: nil, title: autoPrefix + why) }
    static let autoPrefix = "lumen-auto:"
    public var autoReason: String? { title.hasPrefix(Self.autoPrefix) ? String(title.dropFirst(Self.autoPrefix.count)) : nil }

    public init(conversationID: String? = nil, title: String) {
        self.conversationID = conversationID
        self.title = title
    }

    /// Скрытая пометка для модели: откуда задача и что было там перед ней. В переписке её не видно.
    public static func modelText(task: String, from title: String, context: String) -> String {
        var s = "<lumen-from chat=\"\(title.replacingOccurrences(of: "\"", with: "'"))\">"
        if !context.isEmpty { s += "\n" + context }
        return s + "\n</lumen-from>\n\n" + task
    }
}

/// Режим работы агента — те же пять, что в Claude Code (`--permission-mode`)
public enum AgentMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case plan
    case manual
    case acceptEdits
    case auto
    case bypassPermissions

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .plan: "План"
        case .manual: "Спрашивать"
        case .acceptEdits: "Принимать правки"
        case .auto: "Авто"
        case .bypassPermissions: "Обход"
        }
    }

    public var note: String {
        switch self {
        case .plan: "только читает и предлагает план, ничего не меняет"
        case .manual: "каждую правку и команду спрашивает у тебя"
        case .acceptEdits: "правит файлы сам, команды спрашивает"
        case .auto: "сам решает, что безопасно, рискованное спрашивает"
        case .bypassPermissions: "всё без вопросов, кроме push"
        }
    }

    public var icon: String {
        switch self {
        case .plan: "list-checks"
        case .manual: "hand"
        case .acceptEdits: "pencil"
        case .auto: "sparkles"
        case .bypassPermissions: "zap"
        }
    }
}

/// Чат — просто разговор; агент — работа в папке проекта
public enum ConversationKind: String, Codable, Sendable { case chat, agent, bot, group }

/// Шаг агента: что он делал (читал, правил, запускал) — из вызовов инструментов
public struct AgentStep: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable { case read, edit, run, search, web, think, other }
    public var kind: Kind
    public var text: String
    /// Где в тексте ответа агент сделал этот шаг (число символов до него) — чтобы шаги стояли между абзацами,
    /// как в Claude Code. nil — старые ответы: все шаги над текстом.
    public var at: Int?
    /// Подробности, которые раскрываются в чате: полный путь, команда, что поменяли. nil — раскрывать нечего
    public var detail: String? = nil

    public init(kind: Kind, text: String, at: Int? = nil) {
        self.kind = kind
        self.text = text
        self.at = at
    }

    /// В чате видны только шаги в браузере; память и навыки там показаны плашками
    public var shownInChat: Bool { kind != .think && kind != .other && !text.hasPrefix("Читает навык") }

    /// Шаг: строка для ленты и подробности для раскрытия
    public static func from(tool: String, input: [String: Any]) -> AgentStep {
        var step = label(tool: tool, input: input)
        step.detail = detail(tool: tool, input: input)
        return step
    }

    /// Подробности: что агент реально сделал. Правки — строки «было» (−) и «стало» (+), не больше 12 на замену
    static func detail(tool: String, input: [String: Any]) -> String? {
        func str(_ k: String) -> String { input[k] as? String ?? "" }
        func opt(_ s: String) -> String? { s.isEmpty ? nil : s }
        func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
        func diff(_ old: String, _ new: String) -> String {
            let minus = old.components(separatedBy: "\n").prefix(12).map { "- " + $0 }
            let plus = new.components(separatedBy: "\n").prefix(12).map { "+ " + $0 }
            return (minus + plus).joined(separator: "\n")
        }
        switch tool {
        case "Read", "Write": return opt(str("file_path"))
        case "NotebookEdit": return opt(str("notebook_path"))
        case "Edit": return clip(str("file_path") + "\n" + diff(str("old_string"), str("new_string")), 1500)
        case "MultiEdit":
            let edits = (input["edits"] as? [[String: Any]] ?? []).map { diff($0["old_string"] as? String ?? "", $0["new_string"] as? String ?? "") }
            return clip(([str("file_path")] + edits).joined(separator: "\n…\n"), 1500)
        case "Bash": return opt(clip(str("command"), 1200))
        case "Grep": return "«\(str("pattern"))»" + (str("path").isEmpty ? "" : " в " + str("path"))
        case "Glob": return opt(str("pattern"))
        case "WebSearch": return opt(str("query"))
        case "WebFetch": return opt(str("url"))
        case "mcp__lumen__browser_navigate": return opt(str("url"))
        case "mcp__lumen__browser_type": return opt(clip(str("text"), 400))
        default: return nil
        }
    }

    /// Человеческая строка из имени инструмента и его входа
    private static func label(tool: String, input: [String: Any]) -> AgentStep {
        func file(_ k: String) -> String { ((input[k] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "" }
        switch tool {
        case "Read": return .init(kind: .read, text: "Читает \(file("file_path"))")
        case "Edit", "MultiEdit": return .init(kind: .edit, text: "Правит \(file("file_path"))")
        case "Write": return .init(kind: .edit, text: "Пишет \(file("file_path"))")
        case "NotebookEdit": return .init(kind: .edit, text: "Правит \(file("notebook_path"))")
        case "Bash":
            // своё описание команды — им и пишем; иначе сама команда. Без двоеточий: «Запускает swift test»
            let bg = input["run_in_background"] as? Bool == true ? "В фоне: " : ""
            if let d = (input["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                return .init(kind: .run, text: bg.isEmpty ? d.prefix(1).uppercased() + String(d.dropFirst().prefix(79)) : bg + String(d.prefix(79)))
            }
            return .init(kind: .run, text: "Запускает " + String(((input["command"] as? String) ?? "").prefix(80)))
        case "Grep": return .init(kind: .search, text: "Ищет «\((input["pattern"] as? String ?? "").prefix(40))»")
        case "Glob": return .init(kind: .search, text: "Ищет файлы \((input["pattern"] as? String ?? "").prefix(40))")
        case "WebSearch": return .init(kind: .web, text: "Ищет в интернете «\((input["query"] as? String ?? "").prefix(40))»")
        case "WebFetch": return .init(kind: .web, text: "Открывает \((input["url"] as? String ?? "").prefix(60))")
        case "TodoWrite", "TaskUpdate": return .init(kind: .think, text: "Обновляет план")
        case "TaskCreate": return .init(kind: .think, text: "Добавляет в план «\((input["subject"] as? String ?? "").prefix(60))»")
        case "ToolSearch", "TaskList", "TaskGet": return .init(kind: .think, text: "Готовит инструменты")
        case "Task", "Agent":
            let d = (input["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(kind: .other, text: d.isEmpty ? "Запускает субагента" : "Запускает субагента «\(d.prefix(60))»")
        case "remember", "mcp__lumen__remember": return .init(kind: .think, text: "Запоминает")
        case "add_to_project", "mcp__lumen__add_to_project": return .init(kind: .think, text: "Добавляет в контекст проекта")
        case "recall", "mcp__lumen__recall": return .init(kind: .think, text: "Вспоминает")
        case "load_skill", "mcp__lumen__load_skill": return .init(kind: .think, text: "Берёт навык \(input["name"] as? String ?? "")")
        case "read_skill_file", "mcp__lumen__read_skill_file": return .init(kind: .read, text: "Читает навык \(input["path"] as? String ?? "")")
        case "mcp__lumen__delegate": return .init(kind: .other, text: "Зовёт @\(input["bot"] as? String ?? "") — \((input["task"] as? String ?? "").prefix(60))")
        // встроенный браузер
        case "mcp__lumen__browser_navigate":
            let u = input["url"] as? String ?? ""
            return .init(kind: .web, text: ["back": "Возвращается на страницу назад", "forward": "Идёт на страницу вперёд", "reload": "Обновляет страницу"][u.lowercased()]
                         ?? "Открывает \(URL(string: u)?.host ?? String(u.prefix(60)))")
        case "mcp__lumen__browser_show": return .init(kind: .web, text: "Показывает \(file("path"))")
        case "mcp__lumen__browser_read_page", "mcp__lumen__browser_text": return .init(kind: .read, text: "Читает страницу")
        case "mcp__lumen__browser_find": return .init(kind: .search, text: "Ищет на странице «\((input["query"] as? String ?? "").prefix(40))»")
        case "mcp__lumen__browser_click": return .init(kind: .web, text: "Нажимает \(input["ref"] as? String ?? "")")
        case "mcp__lumen__browser_type": return .init(kind: .web, text: "Вводит «\((input["text"] as? String ?? "").prefix(40))»")
        case "mcp__lumen__browser_select": return .init(kind: .web, text: "Выбирает «\((input["value"] as? String ?? "").prefix(40))»")
        case "mcp__lumen__browser_key": return .init(kind: .web, text: "Клавиша \(input["key"] as? String ?? "")")
        case "mcp__lumen__browser_scroll": return .init(kind: .web, text: "Прокручивает страницу")
        case "mcp__lumen__browser_screenshot": return .init(kind: .read, text: "Смотрит на страницу")
        case "mcp__lumen__browser_js": return .init(kind: .run, text: "Скрипт на странице")
        case "mcp__lumen__browser_wait": return .init(kind: .think, text: "Ждёт страницу")
        case "mcp__lumen__browser_hover": return .init(kind: .web, text: "Наводит указатель")
        case "mcp__lumen__browser_drag": return .init(kind: .web, text: "Перетаскивает")
        case "mcp__lumen__browser_zoom": return .init(kind: .read, text: "Рассматривает кусок страницы")
        case "mcp__lumen__browser_upload": return .init(kind: .web, text: "Загружает файлы на страницу")
        case "mcp__lumen__browser_console": return .init(kind: .read, text: "Смотрит консоль страницы")
        case "mcp__lumen__browser_network": return .init(kind: .read, text: "Смотрит запросы страницы")
        case "mcp__lumen__browser_tabs": return .init(kind: .web, text: ["new": "Открывает вкладку", "close": "Закрывает вкладку", "select": "Переключает вкладку"][input["action"] as? String ?? ""] ?? "Смотрит вкладки")
        case "mcp__lumen__browser_resize": return .init(kind: .web, text: "Меняет размер страницы")
        case "mcp__lumen__browser_batch": return .init(kind: .web, text: "Несколько действий в браузере (\((input["actions"] as? [Any])?.count ?? 0))")
        case "mcp__lumen__browser_servers": return .init(kind: .read, text: "Смотрит запущенные localhost")
        case "mcp__lumen__show_in_chat": return .init(kind: .web, text: "Показывает в чате \(file("path"))")
        case "mcp__lumen__make_file": return .init(kind: .web, text: "Делает файл \(input["name"] as? String ?? "")")
        default:
            let name = tool.hasPrefix("mcp__") ? tool.components(separatedBy: "__").last ?? tool : tool
            // инструменты приложения Claude Code — в разговорах, перенесённых оттуда
            switch name {
            case "update_plan": return .init(kind: .think, text: "Обновляет план")
            case "wrap_up": return .init(kind: .think, text: "Подводит итог")
            case "mark_chapter": return .init(kind: .think, text: "Отмечает главу")
            case "start_session": return .init(kind: .other, text: "Предлагает отдельную задачу")
            default: return .init(kind: .other, text: name)
            }
        }
    }
}

/// Кусок ответа агента: абзацы текста и группы шагов между ними, в том порядке, как он работал
public enum AnswerPiece: Equatable, Sendable {
    case text(String)
    case steps([AgentStep])

    /// Разложить ответ: шаги встают туда, где агент их сделал. Место подтягивается к ближайшей границе абзаца —
    /// текст ответа после хода чуть обрезается (пробелы, блок «что дальше»), и шаг не должен рвать предложение.
    public static func layout(text: String, steps: [AgentStep]) -> [AnswerPiece] {
        let chars = Array(text)
        // границы абзацев: позиции сразу после пустой строки
        var breaks: [Int] = [0]
        var i = 0
        while i < chars.count - 1 {
            if chars[i] == "\n" && chars[i + 1] == "\n" {
                var j = i
                while j < chars.count && chars[j] == "\n" { j += 1 }
                breaks.append(j)
                i = j
            } else { i += 1 }
        }
        breaks.append(chars.count)
        func snap(_ at: Int?) -> Int {
            guard let at else { return 0 }
            if at >= chars.count { return chars.count }
            return breaks.min { abs($0 - at) < abs($1 - at) } ?? 0
        }
        var groups: [(Int, [AgentStep])] = []
        for s in steps {
            let pos = snap(s.at)
            if let last = groups.last, last.0 == pos { groups[groups.count - 1].1.append(s) } else { groups.append((pos, [s])) }
        }
        groups.sort { $0.0 < $1.0 }
        var out: [AnswerPiece] = []
        var from = 0
        func addText(_ a: Int, _ b: Int) {
            guard b > a else { return }
            let t = String(chars[a..<b]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
        }
        for (pos, ss) in groups {
            addText(from, pos)
            if case .steps(let prev) = out.last { out[out.count - 1] = .steps(prev + ss) } else { out.append(.steps(ss)) }
            from = max(from, pos)
        }
        addText(from, chars.count)
        return out
    }
}

/// Пункт плана агента (`PlanItem` в макете) — из его списка задач (TodoWrite)
public struct PlanItem: Codable, Sendable, Equatable, Hashable {
    public enum State: String, Codable, Sendable { case done, doing, todo }
    public var text: String
    public var state: State
    /// Номер задачи у claude (TaskCreate выдаёт 1, 2, 3…) — для TaskUpdate
    public var id: String?

    public init(text: String, state: State, id: String? = nil) {
        self.text = text
        self.state = state
        self.id = id
    }

    /// Изменение плана из вызова инструмента
    public enum Change: Sendable, Equatable {
        /// TodoWrite: весь список заново
        case replace([PlanItem])
        /// TaskCreate: новая задача в конец
        case add(String)
        /// TaskUpdate: статус (pending / in_progress / completed / deleted) и, может быть, новый текст
        case update(id: String, status: String?, text: String?)
        /// Ответ на TaskCreate («Task #7 created successfully: …»): настоящий номер задачи у claude
        case created(id: String, subject: String)
    }

    /// Номер, пока claude не ответил на TaskCreate: начинается с «~» и ни с чьим настоящим номером не совпадёт
    public static func pendingID() -> String { "~" + UUID().uuidString.prefix(6) }

    /// `freshTurn` — первое изменение плана в новом ходе: если агент начинает добавлять пункты, это новый план,
    /// старый не дописывается (иначе пункты дублируются из хода в ход). Номера продолжаются: у claude они сквозные.
    /// `live` — идущий ход: новый пункт ждёт настоящий номер из ответа claude (`.created`). Раньше Lumen нумеровал сам
    /// с 1 после каждого хода, а у claude нумерация сквозная на всю сессию, и «сделано» попадало не в тот пункт (19.10).
    public static func apply(_ change: Change, to plan: [PlanItem], freshTurn: Bool, live: Bool = false) -> [PlanItem] {
        if live, case .add(let text) = change {
            let item = PlanItem(text: text, state: .todo, id: pendingID())
            return freshTurn ? [item] : plan + [item]
        }
        if freshTurn, case .add(let text) = change {
            let base = plan.compactMap { $0.id.flatMap(Int.init) }.max() ?? 0
            return [PlanItem(text: text, state: .todo, id: String(base + 1))]
        }
        return apply(change, to: plan)
    }

    public static func apply(_ change: Change, to plan: [PlanItem]) -> [PlanItem] {
        switch change {
        case .replace(let items):
            return items
        case .add(let text):
            let next = (plan.compactMap { $0.id.flatMap(Int.init) }.max() ?? 0) + 1
            return plan + [PlanItem(text: text, state: .todo, id: String(next))]
        case .created(let id, let subject):
            if plan.contains(where: { $0.id == id }) { return plan }
            // по порядку создания: первый ещё не подтверждённый пункт с таким названием (иначе просто первый такой)
            let waiting = plan.indices.filter { plan[$0].id?.hasPrefix("~") == true }
            guard let i = waiting.first(where: { plan[$0].text == subject }) ?? waiting.first else { return plan }
            var p = plan
            p[i].id = id
            return p
        case .update(let id, let status, let text):
            if status == "deleted" { return plan.filter { $0.id != id } }
            return plan.map { item in
                guard item.id == id else { return item }
                var i = item
                if let text, !text.isEmpty { i.text = text }
                switch status {
                case "completed": i.state = .done
                case "in_progress": i.state = .doing
                case "pending": i.state = .todo
                default: break
                }
                return i
            }
        }
    }

    /// Из входа TodoWrite: [{content, status: pending|in_progress|completed, activeForm}]
    public static func from(todos: [[String: Any]]) -> [PlanItem] {
        todos.map { t in
            let status = t["status"] as? String
            return PlanItem(text: t["content"] as? String ?? "",
                            state: status == "completed" ? .done : (status == "in_progress" ? .doing : .todo))
        }
    }
}

/// Карточка «что дальше» в конце хода агента (`NextStep` в макете): итог, вопрос, одна-две кнопки
public struct NextStep: Codable, Sendable, Equatable {
    public struct Choice: Codable, Sendable, Equatable {
        public var label: String
        public var reply: String
        public init(label: String, reply: String) {
            self.label = label
            self.reply = reply
        }
    }
    public var recap: String
    public var ask: String?
    public var primary: Choice?
    public var secondary: Choice?

    public init(recap: String, ask: String? = nil, primary: Choice? = nil, secondary: Choice? = nil) {
        self.recap = recap
        self.ask = ask
        self.primary = primary
        self.secondary = secondary
    }

    static let open = "<lumen-next>", close = "</lumen-next>"

    /// Текст ответа без блока «что дальше» — и сам блок, если агент его написал
    public static func split(_ text: String) -> (text: String, next: NextStep?) {
        guard let a = text.range(of: open) else { return (text, nil) }
        let visible = String(text[..<a.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = text[a.upperBound...]
        let json = rest.range(of: close).map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        let next = try? JSONDecoder().decode(NextStep.self, from: Data(json.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return (visible, next?.recap.isEmpty == false ? next : nil)
    }
}

/// Изменённый агентом файл (карточка «Изменения»)
public struct FileChange: Codable, Sendable, Equatable, Hashable {
    public var path: String
    /// M — изменён, A — новый, D — удалён
    public var status: String
    public var added: Int
    public var removed: Int
    /// Файл был изменён ещё до хода агента — его не откатываем, чтобы не потерять чужую работу
    public var preexisting: Bool

    public init(path: String, status: String, added: Int, removed: Int, preexisting: Bool = false) {
        self.path = path
        self.status = status
        self.added = added
        self.removed = removed
        self.preexisting = preexisting
    }
}

/// Карточка «Изменения» после хода агента
public struct ChangeSet: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case applied, committed, reverted }
    public var files: [FileChange]
    public var state: State

    public init(files: [FileChange], state: State = .applied) {
        self.files = files
        self.state = state
    }
}

/// Разговор во вкладке «Чат» или «Агент». Через что он думает, выбирается при создании и не меняется:
/// у подписки история живёт в сессии `claude`, у API — в базе Lumen.
public struct Conversation: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kind: ConversationKind
    /// Папка проекта — только у агента
    public var folder: String?
    public var backend: Backend
    public var model: ChatModel
    public var effort: Effort
    /// Сессия `claude` для режима подписки — для `--resume`
    public var cliSessionID: String?
    /// План агента — последний его список задач
    public var plan: [PlanItem] = []
    /// Закреплён — всегда сверху списка
    public var pinned = false
    /// Проект, в котором разговор (nil — вне проектов)
    public var projectID: String?
    /// Постоянный разговор этого бота (kind = .bot)
    public var botID: String?
    /// Разговор группы ботов (kind = .group) — id группы
    public var groupID: String?
    /// Режим агента в этом разговоре
    public var mode: AgentMode?
    /// Ещё папки, к которым у агента есть доступ, кроме основной (`--add-dir`)
    public var extraPaths: [String]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), title: String = "", kind: ConversationKind = .chat, folder: String? = nil,
                backend: Backend, model: ChatModel, effort: Effort, cliSessionID: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.kind = kind
        self.folder = folder
        self.backend = backend
        self.model = model
        self.effort = effort
        self.cliSessionID = cliSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Сообщение разговора
public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: Int64?
    public var conversationID: String
    public var role: Role
    public var text: String
    /// Ответ API целиком (блоки content в JSON): при следующем ходе отправляется как есть,
    /// чтобы история только дописывалась (§3 техплана)
    public var apiContent: String?
    public var model: ChatModel?
    /// Остановлен кнопкой «Стоп»
    public var stopped: Bool
    /// Понятная ошибка вместо ответа
    public var error: String?
    /// Шаги агента за этот ход
    public var steps: [AgentStep]
    /// Что агент поменял в файлах
    public var changes: ChangeSet?
    /// Факты, которые Lumen запомнил за этот ход («Запомнил») и на которые опирался («Опирался на»)
    public var remembered: [Int64]
    public var recalled: [Int64]
    /// Сколько токенов занял разговор к этому ответу и сколько всего помещается
    public var contextTokens: Int?
    public var contextWindow: Int?
    /// Служебная строка в переписке («Разговор сжат») — не ответ модели
    public var note: String?
    /// «Что дальше» после хода агента; nil — карточку убрали или её не было
    public var next: NextStep?
    /// Ответил бот (позвали через @id или это его разговор)
    public var botID: String?
    /// Предложенный после этой задачи навык («сам научился»); nil — не предлагался или уже решили
    public var skillDraft: SkillDraft?
    /// Коннекторы и хуки, которые Lumen предложил в этом ответе (карточки «Подключить» / «Добавить»)
    public var proposals: [CustomizeProposal] = []
    /// Метка ответа в сессии claude — к ней откатывается разговор при «Изменить» и «Попробовать снова»
    public var cliAnchor: String?
    /// Сообщение — начало главы: видно в оглавлении разговора
    public var chapter: Bool = false
    /// Вложения сообщения человека: картинки и файлы
    public var attachments: [Attachment] = []
    /// Прежние варианты этого ответа («Попробовать снова» не стирает их, а листает ‹ 1/3 ›), новый — сам ответ
    public var alternates: [AnswerVariant]?
    /// Сообщение пришло боту из другого разговора (позвали через @): откуда — для пометки под ним
    public var via: Via?
    public var createdAt: Date

    public init(id: Int64? = nil, conversationID: String, role: Role, text: String, apiContent: String? = nil,
                model: ChatModel? = nil, stopped: Bool = false, error: String? = nil, steps: [AgentStep] = [],
                changes: ChangeSet? = nil, remembered: [Int64] = [], recalled: [Int64] = [], note: String? = nil,
                createdAt: Date = Date()) {
        self.note = note
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.apiContent = apiContent
        self.model = model
        self.stopped = stopped
        self.error = error
        self.steps = steps
        self.changes = changes
        self.remembered = remembered
        self.recalled = recalled
        self.createdAt = createdAt
    }
}
