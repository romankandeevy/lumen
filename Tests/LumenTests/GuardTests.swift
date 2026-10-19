import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders

/// «Страж готовности» (19.10): не пускает агента закончить, пока он не проверил свою работу

private func human(_ text: String) -> String {
    #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"\#(text)"}]}}"#
}

private func use(_ id: String, _ name: String, _ input: String) -> String {
    #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
}

private func result(_ id: String, _ text: String = "ok", error: Bool = false) -> String {
    #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"\#(text)","is_error":\#(error)}]}}"#
}

private func edit(_ id: String, _ path: String = "/p/App.swift") -> [String] {
    [use(id, "Edit", #"{"file_path":"\#(path)","old_string":"a","new_string":"b"}"#), result(id)]
}

private func bash(_ id: String, _ cmd: String, error: Bool = false) -> [String] {
    [use(id, "Bash", #"{"command":"\#(cmd)"}"#), result(id, error ? "упало" : "ok", error: error)]
}

private func verdict(_ lines: [String], active: Bool = false) -> String? {
    ReadinessGuard.verdict(transcript: lines.joined(separator: "\n"), stopHookActive: active)
}

@Test func guardBlocksEditsWithoutChecking() {
    let r = verdict([human("почини")] + edit("1"))
    #expect(r?.contains("ничего не собрал") == true)
    #expect(r?.contains("App.swift") == true)
}

@Test func guardLetsGoAfterBuildOrTests() {
    #expect(verdict([human("почини")] + edit("1") + bash("2", "swift test --filter Foo")) == nil)
    #expect(verdict([human("почини")] + edit("1") + bash("2", "cd app && npm run build")) == nil)
    // проверка до последней правки не считается
    #expect(verdict([human("почини")] + bash("1", "swift build") + edit("2")) != nil)
}

@Test func guardBlocksWhenLastCheckFailed() {
    let r = verdict([human("почини")] + edit("1") + bash("2", "swift test", error: true))
    #expect(r?.contains("проверка после правок упала") == true)
    // исправил и проверил снова — можно
    #expect(verdict([human("почини")] + edit("1") + bash("2", "swift test", error: true) + edit("3") + bash("4", "swift test")) == nil)
}

@Test func guardIgnoresDocsAndPlainAnswers() {
    #expect(verdict([human("допиши")] + edit("1", "/p/README.md")) == nil)
    // чтение без правок — проверять нечего
    #expect(verdict([human("что тут?"), use("1", "Read", #"{"file_path":"/p/a"}"#), result("1")]) == nil)
    // ход без инструментов
    #expect(verdict([human("привет")]) == nil)
}

@Test func guardCountsEditsMadeByShellCommands() {
    // 19.10, живой claude: правил файл не Edit, а `printf >> calc.py` — и страж этого не видел
    #expect(verdict([human("добавь")] + bash("1", "printf 'def mul(a,b):\\n    return a*b\\n' >> calc.py")) != nil)
    #expect(verdict([human("добавь")] + bash("1", "sed -i '' 's/a/b/' src/main.swift")) != nil)
    #expect(verdict([human("добавь")] + bash("1", "cat <<EOF > app.py\\nprint(1)\\nEOF")) != nil)
    // после правки запустил проверку — можно
    #expect(verdict([human("добавь")] + bash("1", "printf x >> calc.py") + bash("2", "python3 -m pytest")) == nil)
    // чтение, вывод в журнал и правки документов правкой кода не считаются
    #expect(verdict([human("добавь")] + bash("1", "ls && cat calc.py")) == nil)
    #expect(verdict([human("добавь")] + bash("1", "swift build > /tmp/build.log 2>&1")) == nil)
    #expect(verdict([human("добавь")] + bash("1", "echo hi >> NOTES.md")) == nil)
    #expect(verdict([human("добавь")] + bash("1", "ls 2>&1 | head")) == nil)
}

@Test func guardOnlyLooksAtTheLastTurn() {
    // правка без проверки была в прошлом ходе — этот ход чистый
    let lines = [human("раз")] + edit("1") + [human("два"), use("2", "Read", #"{"file_path":"/p/a"}"#), result("2")]
    #expect(verdict(lines) == nil)
}

@Test func guardGivesOneChanceOnly() {
    #expect(verdict([human("почини")] + edit("1"), active: true) == nil)
}

@Test func guardHoldsBackUnfinishedPlan() {
    let create = [use("c1", "TaskCreate", #"{"subject":"Прочитать код"}"#), result("c1", "Task #7 created successfully: Прочитать код"),
                  use("c2", "TaskCreate", #"{"subject":"Написать тест"}"#), result("c2", "Task #8 created successfully: Написать тест")]
    let done7 = [use("u1", "TaskUpdate", #"{"taskId":"7","status":"completed"}"#), result("u1")]
    let r = verdict([human("сделай")] + create + done7)
    #expect(r?.contains("Написать тест") == true)
    #expect(r?.contains("Прочитать код") == false)
    let done8 = [use("u2", "TaskUpdate", #"{"taskId":"8","status":"completed"}"#), result("u2")]
    #expect(verdict([human("сделай")] + create + done7 + done8) == nil)
    // пункт из прошлого хода, которого нет среди созданных в этом, не держит
    #expect(verdict([human("сделай")] + done7) == nil)
}

@Test func guardReadsTodoWriteToo() {
    let todos = [use("t", "TodoWrite", #"{"todos":[{"content":"Раз","status":"completed"},{"content":"Два","status":"in_progress"}]}"#), result("t")]
    #expect(verdict([human("сделай")] + todos)?.contains("Два") == true)
}

@Test func guardHookAnswersClaudeInJSON() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("guard-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("s.jsonl")
    try ([human("почини")] + edit("1")).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    let stdin = try JSONSerialization.data(withJSONObject: ["transcript_path": file.path, "stop_hook_active": false])
    let out = try #require(ReadinessGuard.hookOutput(for: stdin))
    let json = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    #expect(json["decision"] as? String == "block")
    #expect((json["reason"] as? String)?.contains("Рано заканчивать") == true)
    // повторный заход — отпускаем; битый вход — тоже
    let again = try JSONSerialization.data(withJSONObject: ["transcript_path": file.path, "stop_hook_active": true])
    #expect(ReadinessGuard.hookOutput(for: again) == nil)
    #expect(ReadinessGuard.hookOutput(for: Data("не json".utf8)) == nil)
}

@Test func guardHookIsAddedToClaudeSettingsAndKeepsOthers() throws {
    let hooks = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"x"}]}]}}"#
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-" + UUID().uuidString + ".json")
    try hooks.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let s = try #require(ClaudeSession.Config.settings(file: file.path, pluginsOff: [], guardCommand: "'/x/lumen-mcp' guard '/x/off'"))
    let json = try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    let h = try #require(json["hooks"] as? [String: Any])
    #expect((h["Stop"] as? [[String: Any]])?.count == 2)
    #expect(h["PreToolUse"] != nil)
    #expect(s.contains("guard"))
    // без стража (бот, чат) — хука нет
    #expect(ClaudeSession.Config.settings(file: nil, pluginsOff: [], guardCommand: nil) == nil)
}

@Test func agentHasRulesNotCharacter() {
    let core = AgentRules.core(userName: "Рома", ty: true, russianOnly: true)
    #expect(core.contains("Рома") && core.contains("«ты»") && core.contains("по-русски"))
    #expect(core.contains("Не заканчивай ход вопросом"))
    #expect(core.contains("Не пиши «готово», пока не проверил"))
    // тона, длины и шуток в правилах агента нет
    #expect(!core.contains("Тон:") && !core.contains("Юмор") && !core.contains("характер"))
    #expect(AgentRules.user("  ") == nil)
    #expect(AgentRules.user("Не двигай кнопки")?.contains("Не двигай кнопки") == true)
}
