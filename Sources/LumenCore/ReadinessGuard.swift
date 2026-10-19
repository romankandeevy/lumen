import Foundation

/// «Страж готовности» (Рома, 19.10): когда агент собрался закончить ход, смотрим в запись сессии claude и,
/// если работа не доведена, возвращаем его с объяснением. Это хук Stop у claude (`lumen-mcp guard`).
/// Не пускает дальше, если в этом ходе: правили код, а после последней правки ничего не собрали и не запустили;
/// последняя проверка упала; в плане остались несделанные пункты этого хода.
/// Один заход на остановку: claude сам ставит `stop_hook_active`, когда уже вернулся из-за хука, — тогда отпускаем,
/// чтобы не зациклиться.
public enum ReadinessGuard {
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    /// Правки только в таких файлах проверять нечем
    static let docExtensions: Set<String> = ["md", "markdown", "txt", "rst"]

    /// Команды, которые считаются проверкой: сборка, тесты, линтеры, типы, запуск сайта
    static let verifyPattern: NSRegularExpression = {
        let words = [
            #"swift\s+(build|test|run)"#, #"xcodebuild"#, #"(\./)?build\.sh"#, #"make(\s|$)"#,
            #"(npm|pnpm|yarn|bun)\s+(run\s+)?(test|build|lint|typecheck|check|dev|start)"#, #"npx\s+\S*(tsc|eslint|vitest|jest|playwright)"#,
            #"tsc(\s|$)"#, #"eslint"#, #"vitest"#, #"jest"#, #"node\s+--test"#, #"deno\s+(test|check)"#,
            #"pytest"#, #"python3?\s+-m\s+(pytest|unittest|mypy|ruff)"#, #"ruff"#, #"mypy"#, #"flake8"#, #"rspec"#,
            #"cargo\s+(build|test|check|clippy|run)"#, #"go\s+(build|test|vet|run)"#, #"gradle"#, #"mvn"#, #"dotnet\s+(build|test)"#,
            #"curl\s.*(localhost|127\.0\.0\.1)"#,
        ]
        return try! NSRegularExpression(pattern: "(^|[\\s;&|(])(" + words.joined(separator: "|") + ")", options: [.caseInsensitive])
    }()

    static func isVerification(tool: String, input: [String: Any]) -> Bool {
        if tool == "Bash", let cmd = input["command"] as? String {
            return verifyPattern.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)) != nil
        }
        // посмотрел результат глазами: снимок или действие в браузере сбоку
        return tool.hasPrefix("mcp__lumen__browser") || tool.hasPrefix("mcp__playwright")
    }

    /// Файл можно изменить и командой в терминале: `>>`, `sed -i`, `tee`, `git apply`… Это тоже правка кода.
    /// Сборка и тесты с выводом в журнал (`> /tmp/x.log`) правкой не считаются.
    static func isBashEdit(_ command: String) -> Bool {
        if isVerification(tool: "Bash", input: ["command": command]) { return false }
        var cmd = command
        for noise in [#"\d?>&\d"#, #"&>\s*/dev/null"#, #"\d?>\s*/dev/null"#] {
            cmd = cmd.replacingOccurrences(of: noise, with: " ", options: .regularExpression)
        }
        // куда перенаправлен вывод: не в /tmp и не в журнал
        let redirect = try! NSRegularExpression(pattern: #"(?<![<>&\d])>>?\s*([^\s;&|>]+)"#)
        let range = NSRange(cmd.startIndex..., in: cmd)
        for m in redirect.matches(in: cmd, range: range) {
            guard let r = Range(m.range(at: 1), in: cmd) else { continue }
            let target = String(cmd[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if target.hasPrefix("/tmp") || target.hasPrefix("/private/tmp") || target.hasPrefix("/dev/") || target.contains("TMPDIR")
                || target.hasSuffix(".log") || target.hasSuffix(".out") { continue }
            if !isDoc(target) { return true }
        }
        let writers = #"(^|[\s;&|(])(sed\s+(-[a-zA-Z]*i|--in-place)|perl\s+-[a-zA-Z]*i|tee(\s|$)|patch(\s|$)|git\s+(apply|restore|checkout\s+--))"#
        if cmd.range(of: writers, options: .regularExpression) != nil {
            // правка одних только документов — проверять нечем
            let exts = try! NSRegularExpression(pattern: #"[\w./~-]+\.([A-Za-z0-9]{1,6})\b"#)
            let found = exts.matches(in: cmd, range: range).compactMap { Range($0.range(at: 1), in: cmd).map { String(cmd[$0]).lowercased() } }
            return found.isEmpty || found.contains { !docExtensions.contains($0) }
        }
        return false
    }

    /// Причина вернуть агента к работе или nil — можно заканчивать
    public static func verdict(transcript: String, stopHookActive: Bool) -> String? {
        if stopHookActive { return nil }
        let turn = lastTurn(transcript)

        struct Use { let id: String; let name: String; let input: [String: Any]; let seq: Int }
        var uses: [Use] = []
        var failed: [String: Bool] = [:]
        var pendingCreate: [String: String] = [:]
        var tasks: [String: (subject: String, status: String)] = [:]
        var todos: [[String: Any]]?
        var seq = 0

        for obj in turn {
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content {
                switch block["type"] as? String {
                case "tool_use":
                    let id = block["id"] as? String ?? "", name = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    seq += 1
                    uses.append(Use(id: id, name: name, input: input, seq: seq))
                    switch name {
                    case "TodoWrite": todos = input["todos"] as? [[String: Any]]
                    case "TaskCreate": pendingCreate[id] = input["subject"] as? String ?? ""
                    case "TaskUpdate":
                        let tid = input["taskId"] as? String ?? (input["taskId"] as? Int).map(String.init) ?? ""
                        let status = input["status"] as? String
                        if status == "deleted" { tasks[tid] = nil } else if let status, tasks[tid] != nil { tasks[tid]?.status = status }
                    default: break
                    }
                case "tool_result":
                    let id = block["tool_use_id"] as? String ?? ""
                    failed[id] = block["is_error"] as? Bool ?? false
                    if let subject = pendingCreate[id], let n = taskNumber(block) { tasks[n] = (subject, "pending") }
                default: break
                }
            }
        }
        guard !uses.isEmpty else { return nil }

        var reasons: [String] = []
        let toolEdits = uses.filter { editTools.contains($0.name) && !isDoc(path($0.input)) }
        let shellEdits = uses.filter { $0.name == "Bash" && isBashEdit($0.input["command"] as? String ?? "") }
        let codeEdits = toolEdits + shellEdits
        if let lastEdit = codeEdits.map(\.seq).max() {
            let checks = uses.filter { $0.seq > lastEdit && isVerification(tool: $0.name, input: $0.input) }
            if checks.isEmpty {
                var files = Array(Set(toolEdits.map { (path($0.input) as NSString).lastPathComponent })).sorted().prefix(4).map { $0 }
                if !shellEdits.isEmpty { files.append("правки командой в терминале") }
                reasons.append("Ты менял файлы (\(files.joined(separator: ", "))), но после последней правки ничего не собрал и не запустил. Проверь работу: собери проект и запусти тесты — или запусти результат и посмотри на него. Упало — исправь и проверь снова. Проверить нечем — скажи об этом в отчёте прямо.")
            } else if let last = checks.last, failed[last.id] == true {
                reasons.append("Последняя проверка после правок упала. Разберись в причине, исправь и проверь снова. Если упала не из-за твоих правок — скажи об этом в отчёте прямо.")
            }
        }

        var open = tasks.values.filter { $0.status != "completed" }.map(\.subject)
        for t in todos ?? [] where (t["status"] as? String) != "completed" { open.append(t["content"] as? String ?? "") }
        open = open.filter { !$0.isEmpty }
        if !open.isEmpty {
            reasons.append("В плане остались несделанные пункты: " + open.prefix(5).map { "«\($0)»" }.joined(separator: ", ")
                           + ". Доделай их. Если пункт больше не нужен — убери его из плана и объясни почему в отчёте.")
        }
        return reasons.isEmpty ? nil : "Рано заканчивать. " + reasons.joined(separator: " ")
    }

    /// Ответ хука для claude: JSON с решением или nil — пусть заканчивает. `stdin` — то, что claude передал хуку.
    public static func hookOutput(for stdin: Data) -> String? {
        guard let input = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
              let file = input["transcript_path"] as? String,
              let text = try? String(contentsOfFile: file, encoding: .utf8),
              let reason = verdict(transcript: text, stopHookActive: input["stop_hook_active"] as? Bool ?? false),
              let data = try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": reason]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: разбор записи сессии

    /// Записи последнего хода: от последнего сообщения человека до конца. Записи подагентов не считаем.
    static func lastTurn(_ transcript: String) -> [[String: Any]] {
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: true)
        var turn: [[String: Any]] = []
        for line in lines.reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if obj["isSidechain"] as? Bool == true { continue }
            if isHumanMessage(obj) { break }
            turn.append(obj)
        }
        return turn.reversed()
    }

    static func isHumanMessage(_ obj: [String: Any]) -> Bool {
        guard obj["type"] as? String == "user", obj["isMeta"] as? Bool != true else { return false }
        let content = (obj["message"] as? [String: Any])?["content"]
        if content is String { return true }
        guard let blocks = content as? [[String: Any]] else { return false }
        return !blocks.contains { $0["type"] as? String == "tool_result" }
            && blocks.contains { ["text", "image", "document"].contains($0["type"] as? String ?? "") }
    }

    static func path(_ input: [String: Any]) -> String {
        (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String ?? ""
    }

    static func isDoc(_ path: String) -> Bool {
        docExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// «Task #7 created successfully: …» → "7"
    static func taskNumber(_ block: [String: Any]) -> String? {
        var text = ""
        if let s = block["content"] as? String { text = s }
        else if let parts = block["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        guard let m = text.firstMatch(of: /Task #(\d+) created/) else { return nil }
        return String(m.1)
    }
}
