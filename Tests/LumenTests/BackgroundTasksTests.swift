import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// Фоновые задачи агента (19.10): строки — из настоящего потока claude 2.1.301 (команда в фоне и субагент)

private let lines = [
    #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_bash","name":"Bash","input":{"command":"sleep 6; echo ГОТОВО","description":"Sleep 6 seconds then print ГОТОВО","run_in_background":true}}]}}"#,
    #"{"type":"system","subtype":"task_started","task_id":"bfvfqyn0m","tool_use_id":"toolu_bash","description":"Sleep 6 seconds then print ГОТОВО","is_backgrounded":true,"task_type":"local_bash"}"#,
    #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_bash","content":"Command running in background with ID: bfvfqyn0m. Output is being written to: /tmp/lumen-bg-test/tasks/bfvfqyn0m.output"}]},"tool_use_result":{"stdout":"","backgroundTaskId":"bfvfqyn0m"}}"#,
    #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_agent","name":"Agent","input":{"description":"List files in working folder","subagent_type":"general-purpose","prompt":"Перечисли файлы"}}]}}"#,
    #"{"type":"system","subtype":"task_started","task_id":"abac48c5","tool_use_id":"toolu_agent","description":"List files in working folder","subagent_type":"general-purpose","is_backgrounded":false,"task_type":"local_agent"}"#,
    #"{"type":"assistant","parent_tool_use_id":"toolu_agent","message":{"content":[{"type":"tool_use","id":"toolu_ls","name":"Bash","input":{"command":"ls -1Ap","description":"List top-level entries"}}]}}"#,
    #"{"type":"user","parent_tool_use_id":"toolu_agent","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_ls","content":"a.txt"}]}}"#,
    #"{"type":"system","subtype":"task_progress","task_id":"abac48c5","tool_use_id":"toolu_agent","description":"Running List top-level entries","usage":{"total_tokens":35755,"tool_uses":1,"duration_ms":2721},"last_tool_name":"Bash"}"#,
    #"{"type":"system","subtype":"task_updated","task_id":"abac48c5","patch":{"status":"completed","end_time":1792434303170}}"#,
    #"{"type":"system","subtype":"task_notification","task_id":"abac48c5","tool_use_id":"toolu_agent","status":"completed","output_file":"/tmp/x/abac48c5.output","summary":"Нашёл 3 файла"}"#,
    #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_agent","content":"a.txt"}]}}"#,
    #"{"type":"system","subtype":"task_notification","task_id":"bfvfqyn0m","tool_use_id":"toolu_bash","status":"completed","output_file":"/tmp/lumen-bg-test/tasks/bfvfqyn0m.output","summary":"Background command completed"}"#,
]

@Test func backgroundTasksAreCollectedFromClaudeEvents() {
    var tasks: [BackgroundJob] = []
    var mainSteps: [AgentStep] = []
    var toolDone = 0
    for l in lines {
        for ev in ClaudeEvent.decodeAll(Data(l.utf8)) {
            switch ev {
            case .task(let t): tasks = BackgroundJob.apply(t, to: tasks)
            case .step(let s): mainSteps.append(s)
            case .toolDone: toolDone += 1
            default: break
            }
        }
    }
    #expect(tasks.count == 2)
    let shell = tasks[0], agent = tasks[1]
    #expect(shell.kind == .shell && shell.background && shell.status == .completed)
    #expect(shell.outputFile == "/tmp/lumen-bg-test/tasks/bfvfqyn0m.output")
    #expect(agent.kind == .agent && agent.status == .completed && agent.summary == "Нашёл 3 файла" && agent.toolUses == 1)
    // шаги субагента не попадают в шаги главного агента, а его ответы инструментов — в счёт идущих команд
    #expect(mainSteps.map(\.text) == ["В фоне: Sleep 6 seconds then print ГОТОВО", "Запускает субагента «List files in working folder»"])
    #expect(toolDone == 2)
}

@MainActor @Test func backgroundTaskKindsAndTail() throws {
    #expect(BackgroundJob.kind(taskType: "local_agent", subagentType: "Explore", title: "Find usages") == .research)
    #expect(BackgroundJob.kind(taskType: "local_agent", subagentType: "general-purpose", title: "Исследовать API") == .research)
    #expect(BackgroundJob.kind(taskType: "local_agent", subagentType: "general-purpose", title: "Fix tests") == .agent)
    #expect(BackgroundJob.kind(taskType: "local_bash", subagentType: nil, title: "build") == .shell)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-tail-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("out.output")
    try (1...20).map { "строка \($0)" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    var t = BackgroundJob(id: "x", toolUseID: nil, kind: .shell, title: "t", background: true, started: Date())
    t.outputFile = file.path
    #expect(t.tail(3) == "строка 17\nстрока 18\nстрока 19\nстрока 20".split(separator: "\n").suffix(4).joined(separator: "\n"))
    #expect(BackgroundTasksBar.summary([t]) == "Фоновые задачи · работают 1")
}
