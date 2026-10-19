import Foundation

/// Фоновые задачи агента (Рома, 19.10): субагенты, исследования, команды в терминале. claude сообщает о них
/// событиями task_started / task_progress / task_updated / task_notification — Lumen собирает их в список,
/// а шаги субагента идут в его задачу, а не в общий список шагов главного агента.
public enum TaskEvent: Sendable, Equatable {
    case started(id: String, toolUseID: String?, taskType: String, title: String, background: Bool, subagentType: String?)
    /// Что задача делает сейчас: по task_progress (с номером) или по шагу субагента (по вызову, который его запустил)
    case progress(id: String?, toolUseID: String?, activity: String?, toolUses: Int?, tokens: Int?)
    case finished(id: String, status: String, outputFile: String?, summary: String?, ended: Date?)
    /// Куда пишется вывод фоновой команды — claude говорит это сразу при запуске
    case output(id: String, file: String)
}

public struct BackgroundJob: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case agent, research, shell }
    public enum Status: String, Sendable { case running, completed, failed, stopped }

    public let id: String
    public var toolUseID: String?
    public var kind: Kind
    public var title: String
    /// Запущена в фоне (ход может закончиться раньше неё)
    public var background: Bool
    public var started: Date
    public var ended: Date?
    public var status: Status
    public var activity: String?
    public var toolUses = 0
    public var tokens = 0
    /// Файл с выводом команды или итогом субагента
    public var outputFile: String?
    public var summary: String?

    public init(id: String, toolUseID: String?, kind: Kind, title: String, background: Bool, started: Date) {
        self.id = id
        self.toolUseID = toolUseID
        self.kind = kind
        self.title = title
        self.background = background
        self.started = started
        self.status = .running
    }

    /// Команда — терминал; субагент-исследователь (Explore, research, deep-research) — исследование; остальные — субагент
    public static func kind(taskType: String, subagentType: String?, title: String) -> Kind {
        if taskType.contains("bash") || taskType.contains("shell") { return .shell }
        let words = ((subagentType ?? "") + " " + title + " " + taskType).lowercased()
        if ["research", "explore", "исслед", "поиск", "search", "workflow"].contains(where: words.contains) { return .research }
        return .agent
    }

    public static func apply(_ e: TaskEvent, to tasks: [BackgroundJob], now: Date = Date()) -> [BackgroundJob] {
        var tasks = tasks
        switch e {
        case .started(let id, let toolUseID, let type, let title, let background, let sub):
            guard !tasks.contains(where: { $0.id == id }) else { return tasks }
            tasks.append(BackgroundJob(id: id, toolUseID: toolUseID, kind: kind(taskType: type, subagentType: sub, title: title),
                                        title: title.isEmpty ? "Задача" : title, background: background, started: now))
        case .progress(let id, let toolUseID, let activity, let toolUses, let tokens):
            guard let i = tasks.lastIndex(where: { (id != nil && $0.id == id) || (toolUseID != nil && $0.toolUseID == toolUseID) }),
                  tasks[i].status == .running else { return tasks }
            if let activity, !activity.isEmpty { tasks[i].activity = activity }
            if let toolUses { tasks[i].toolUses = toolUses } else if id == nil { tasks[i].toolUses += 1 }
            if let tokens { tasks[i].tokens = tokens }
        case .finished(let id, let status, let output, let summary, let ended):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
            tasks[i].status = status == "completed" ? .completed : (status == "failed" || status == "error" ? .failed : .stopped)
            tasks[i].ended = tasks[i].ended ?? ended ?? now
            if let output { tasks[i].outputFile = output }
            if let summary, !summary.isEmpty { tasks[i].summary = summary }
            tasks[i].activity = nil
        case .output(let id, let file):
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
            tasks[i].outputFile = file
        }
        return tasks
    }
}

extension BackgroundJob {
    /// Последние строки вывода (команды в терминале): для живого просмотра под перепиской
    public func tail(_ lines: Int = 6) -> String? {
        guard let file = outputFile, let h = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 8192 ? size - 8192 : 0)
        let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let last = all.suffix(lines + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return last.isEmpty ? nil : last
    }
}
