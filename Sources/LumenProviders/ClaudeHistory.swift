import Foundation
import LumenCore

/// Разговоры Claude Code на этом Маке (`~/.claude/projects/<папка>/<сессия>.jsonl`) — для импорта в Lumen.
/// Человек сам выбирает, какие забрать. Импортированный разговор — задача агента в той же папке и с той же
/// сессией `claude`: Lumen продолжает его через `--resume`, как будто он начинался здесь.
public enum ClaudeHistory {
    /// Разговор в списке импорта
    public struct Session: Sendable, Identifiable, Equatable, Hashable {
        public var id: String
        public var file: URL
        /// Папка, в которой шёл разговор
        public var cwd: String
        public var title: String
        public var firstPrompt: String
        public var updatedAt: Date
        public var bytes: Int

        public var folderName: String { URL(fileURLWithPath: cwd).lastPathComponent }
    }

    /// Разобранный разговор: сообщения в формате Lumen и последний план агента
    public struct Transcript: Sendable {
        public var session: Session
        public var messages: [ChatMessage]
        public var plan: [PlanItem]
        public var model: ChatModel?
        public var createdAt: Date
    }

    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Все разговоры, свежие сверху. Пропускает служебные: временные папки, разговоры самого Lumen
    /// (его папка `run`), пустые и уже импортированные (`skip` — id сессий, что уже есть в Lumen).
    public static func sessions(root: URL = root, skip: Set<String> = [], lumenRoot: URL? = nil) -> [Session] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Session] = []
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                let id = f.deletingPathExtension().lastPathComponent
                guard !skip.contains(id), let s = summary(f) else { continue }
                if isService(s.cwd, lumenRoot: lumenRoot) { continue }
                out.append(s)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Временные и служебные папки — там разговоры тестов, проверок и самого Lumen
    static func isService(_ cwd: String, lumenRoot: URL?) -> Bool {
        let tmp = ["/private/tmp", "/tmp/", "/private/var/folders", "/var/folders"]
        // «/» — служебные вызовы самого Lumen (подсказки, названия, настройка ботов), не разговоры человека
        if tmp.contains(where: { cwd.hasPrefix($0) }) || cwd == "/tmp" || cwd == "/" { return true }
        if let lumenRoot, cwd.hasPrefix(lumenRoot.path) { return true }
        return cwd.contains("/Library/Application Support/Lumen")
    }

    /// Краткое описание разговора по началу и концу файла — без разбора целиком (файлы бывают по 50 МБ)
    static func summary(_ file: URL) -> Session? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        let size = Int((try? h.seekToEnd()) ?? 0)
        try? h.seek(toOffset: 0)
        let head = (try? h.read(upToCount: 400_000)) ?? Data()
        var cwd: String?
        var first: String?
        var title: String?
        var date: Date?
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if cwd == nil, let c = o["cwd"] as? String { cwd = c }
            if o["type"] as? String == "custom-title", let t = o["customTitle"] as? String { title = t }
            if first == nil, let p = userPrompt(o), !p.isSummary { first = p.text }
            if cwd != nil && first != nil { break }
        }
        // название и время — с конца файла: название переименовывают, время — последнее сообщение
        let tailSize = min(size, 300_000)
        try? h.seek(toOffset: UInt64(size - tailSize))
        let tail = (try? h.readToEnd()) ?? Data()
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if title == nil, o["type"] as? String == "custom-title", let t = o["customTitle"] as? String { title = t }
            if date == nil, let ts = o["timestamp"] as? String { date = parseDate(ts) }
            if title != nil && date != nil { break }
        }
        guard let cwd, let first else { return nil }
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let name = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? shortTitle(first)
        return Session(id: file.deletingPathExtension().lastPathComponent, file: file, cwd: cwd, title: name,
                       firstPrompt: String(first.prefix(300)), updatedAt: date ?? mtime ?? Date(), bytes: size)
    }

    // MARK: разбор

    struct Prompt {
        var text: String
        var isSummary: Bool
    }

    /// Реплика человека из строки: строка-текст или блоки text (не результаты инструментов, не служебное)
    static func userPrompt(_ o: [String: Any]) -> Prompt? {
        guard o["type"] as? String == "user", o["isMeta"] as? Bool != true, o["isSidechain"] as? Bool != true,
              let m = o["message"] as? [String: Any] else { return nil }
        var text: String
        if let s = m["content"] as? String {
            text = s
        } else if let blocks = m["content"] as? [[String: Any]] {
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n\n")
            if blocks.contains(where: { $0["type"] as? String == "image" }) { text += text.isEmpty ? "[картинка]" : "\n\n[картинка]" }
        } else { return nil }
        if text.hasPrefix("This session is being continued from a previous conversation") { return Prompt(text: text, isSummary: true) }
        text = clean(text)
        let service = ["<command-name>", "<command-message>", "<local-command-stdout>", "<local-command-stderr>",
                       "[Request interrupted", "<bash-input>", "<bash-stdout>", "<task-notification>"]
        if text.isEmpty || service.contains(where: { text.hasPrefix($0) }) { return nil }
        return Prompt(text: text, isSummary: false)
    }

    /// Без служебных вставок Claude Code: напоминаний системы и т. п.
    static func clean(_ s: String) -> String {
        var t = s
        for tag in ["system-reminder", "local-command-caveat", "ide_opened_file", "ide_selection"] {
            while let a = t.range(of: "<\(tag)>"), let b = t.range(of: "</\(tag)>", range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Прочитать разговор целиком в сообщения Lumen. `conversationID` — id разговора, куда он ляжет.
    public static func transcript(_ s: Session, conversationID: String) throws -> Transcript {
        let data = try Data(contentsOf: s.file)
        var messages: [ChatMessage] = []
        var plan: [PlanItem] = []
        var model: ChatModel?
        var created: Date?
        // текущий ответ агента: копится, пока не придёт новая реплика человека
        var answer: ChatMessage?
        var needBreak = false

        func closeAnswer() {
            if var a = answer, !(a.text.isEmpty && a.steps.isEmpty) {
                a.text = a.text.trimmingCharacters(in: .whitespacesAndNewlines)
                messages.append(a)
            }
            answer = nil
            needBreak = false
        }

        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if o["isSidechain"] as? Bool == true { continue }
            let date = (o["timestamp"] as? String).flatMap(parseDate)
            if created == nil, let date { created = date }

            if let p = userPrompt(o) {
                closeAnswer()
                if p.isSummary {
                    messages.append(ChatMessage(conversationID: conversationID, role: .assistant, text: "",
                                                note: "Разговор сжат", createdAt: date ?? Date()))
                } else {
                    messages.append(ChatMessage(conversationID: conversationID, role: .user, text: p.text, createdAt: date ?? Date()))
                }
                continue
            }
            guard o["type"] as? String == "assistant", let m = o["message"] as? [String: Any],
                  let blocks = m["content"] as? [[String: Any]] else { continue }
            if let id = m["model"] as? String, let cm = ChatModel(rawValue: id) { model = cm }
            if answer == nil {
                answer = ChatMessage(conversationID: conversationID, role: .assistant, text: "", model: model, createdAt: date ?? Date())
            }
            if let uuid = o["uuid"] as? String { answer?.cliAnchor = uuid }
            for b in blocks {
                switch b["type"] as? String {
                case "text":
                    let t = (b["text"] as? String ?? "")
                    guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    if let cur = answer?.text, !cur.isEmpty {
                        answer?.text += needBreak || !cur.hasSuffix("\n") ? "\n\n" : ""
                    }
                    answer?.text += t
                    needBreak = false
                case "tool_use":
                    let name = b["name"] as? String ?? ""
                    let input = b["input"] as? [String: Any] ?? [:]
                    var step = AgentStep.from(tool: name, input: input)
                    step.at = answer?.text.count ?? 0
                    answer?.steps.append(step)
                    needBreak = true
                    switch name {
                    case "TodoWrite":
                        if let todos = input["todos"] as? [[String: Any]] { plan = PlanItem.apply(.replace(PlanItem.from(todos: todos)), to: plan) }
                    case "TaskCreate":
                        if let subject = input["subject"] as? String { plan = PlanItem.apply(.add(subject), to: plan) }
                    case "TaskUpdate":
                        if let id = input["taskId"] as? String ?? (input["taskId"] as? Int).map(String.init) {
                            plan = PlanItem.apply(.update(id: id, status: input["status"] as? String, text: input["subject"] as? String), to: plan)
                        }
                    default: break
                    }
                default: break
                }
            }
        }
        closeAnswer()
        return Transcript(session: s, messages: messages, plan: plan, model: model, createdAt: created ?? s.updatedAt)
    }

    /// Заголовок из первой фразы: до 60 знаков, по границе слова
    static func shortTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        guard line.count > 60 else { return line }
        let cut = line.prefix(60)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
