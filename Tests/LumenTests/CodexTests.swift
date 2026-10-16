import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// ChatGPT через codex. Настоящий codex требует входа в ChatGPT, поэтому здесь вместо него —
// скрипт, который печатает те же события JSONL (формат `codex exec --json`, codex 0.163)
// и записывает, с какими аргументами и текстом его позвали.

private func line(_ s: String) -> Data { Data(s.utf8) }

@Test func codexEventsBecomeTextStepsPlanAndResult() {
    let p = CodexParser()
    var all: [ClaudeEvent] = []
    for s in [
        #"{"type":"thread.started","thread_id":"t-1"}"#,
        #"{"type":"turn.started"}"#,
        #"{"type":"item.completed","item":{"id":"i0","type":"reasoning","text":"думаю"}}"#,
        #"{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"/bin/zsh -lc 'ls -la'","status":"in_progress"}}"#,
        #"{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"/bin/zsh -lc 'ls -la'","exit_code":0}}"#,
        #"{"type":"item.started","item":{"id":"i2","type":"todo_list","items":[{"text":"Найти","completed":true},{"text":"Починить","completed":false}]}}"#,
        #"{"type":"item.completed","item":{"id":"i3","type":"file_change","changes":[{"path":"/x/App.swift","kind":"update"},{"path":"/x/New.swift","kind":"add"}]}}"#,
        #"{"type":"item.completed","item":{"id":"i4","type":"agent_message","text":"Готово."}}"#,
        #"{"type":"item.completed","item":{"id":"i5","type":"agent_message","text":"Ещё абзац."}}"#,
        #"{"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":40}}"#,
    ] { all += p.parse(line(s)) }

    #expect(all.first == .started(sessionID: "t-1", model: "", tools: []))
    let steps = all.compactMap { if case .step(let s) = $0 { s } else { nil } }
    #expect(steps == [AgentStep(kind: .run, text: "Запускает: ls -la"),
                      AgentStep(kind: .edit, text: "Правит App.swift"),
                      AgentStep(kind: .edit, text: "Пишет New.swift")])
    let text = all.compactMap { if case .textDelta(let t) = $0 { t } else { nil } }.joined()
    #expect(text == "Готово.\n\nЕщё абзац.")
    #expect(all.contains(.plan(.replace([PlanItem(text: "Найти", state: .done), PlanItem(text: "Починить", state: .doing)]))))
    guard case .finished(let r)? = all.last else { Issue.record("нет итога"); return }
    #expect(r.ok && r.sessionID == "t-1" && r.inputTokens == 1200 && r.cacheReadTokens == 800 && r.outputTokens == 40)
}

@MainActor @Test func codexReconnectIsNotTheEndButFailureIs() {
    let p = CodexParser()
    let retry = p.parse(line(#"{"type":"error","message":"Reconnecting... 2/5 (unexpected status 401 Unauthorized)"}"#))
    #expect(retry.count == 1)
    if case .retry = retry[0] {} else { Issue.record("переподключение — не конец хода") }
    let fail = p.parse(line(#"{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized"}}"#))
    guard case .finished(let r)? = fail.first else { Issue.record("нет итога"); return }
    #expect(!r.ok)
    #expect(ChatController.codexError(r.text).contains("войти"))
}

@Test func codexArgumentsKeepAgentInItsFolderAndResume() {
    let folder = URL(fileURLWithPath: "/tmp/проект")
    let chat = CodexCLI.Turn(model: "gpt-6.1-sol", effort: "high", agent: false, folder: folder)
    #expect(chat.arguments.contains("read-only"))
    #expect(!chat.arguments.contains("resume"))
    #expect(chat.arguments.last == "-")

    let agent = CodexCLI.Turn(model: "gpt-6-astra", effort: "max", agent: true, folder: folder, threadID: "t-9",
                              memoryServer: ("/Applications/Lumen.app/Contents/MacOS/lumen-mcp", ["LUMEN_DB": "/a b/lumen.sqlite"]))
    let a = agent.arguments
    #expect(a.contains("workspace-write"))
    #expect(!a.contains("danger-full-access"))
    #expect(a.contains("model_reasoning_effort=\"max\""))
    #expect(a.contains(#"mcp_servers.lumen.env={LUMEN_DB="\/a b\/lumen.sqlite"}"#) || a.contains(#"mcp_servers.lumen.env={LUMEN_DB="/a b/lumen.sqlite"}"#))
    // resume — после всех флагов, перед текстом из stdin
    #expect(Array(a.suffix(3)) == ["resume", "t-9", "-"])
}

/// Скрипт-двойник codex: пишет аргументы и stdin в лог, отвечает событиями, на «долго» — ждёт
private func fakeCodex(in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("codex")
    let script = """
    #!/bin/bash
    LOG="\(dir.path)/calls.log"
    echo "ARGS $*" >> "$LOG"
    IN=$(cat)
    echo "STDIN $IN" >> "$LOG"
    if [ "$1" = login ] && [ "$2" = status ]; then echo "Logged in using ChatGPT"; exit 0; fi
    echo '{"type":"thread.started","thread_id":"th-42"}'
    echo '{"type":"turn.started"}'
    if [[ "$IN" == *долго* ]]; then sleep 30; fi
    echo '{"type":"item.completed","item":{"id":"m1","type":"agent_message","text":"Привет от ChatGPT."}}'
    echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}'
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@MainActor @Test func chatGPTTurnThroughCodexContinuesAndStops() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-codex-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let bin = home.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.codexCLI = CodexCLI(binary: try fakeCodex(in: bin))
    app.codex = .signedIn
    #expect(app.availableModels(for: .subscription).contains(.gptSol))

    app.chat.set(model: .gptSol)
    app.chat.send("Привет")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
    let first = try #require(app.chat.messages.last)
    #expect(first.error == nil, "\(first.error ?? "")")
    #expect(first.text == "Привет от ChatGPT.")
    #expect(app.chat.conversation?.cliSessionID == "th-42")
    #expect(app.chat.conversation?.backend == .subscription)

    // второй ход продолжает тот же разговор; правила Lumen — только в первом
    app.chat.send("И ещё")
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(20)) }
    let log = try String(contentsOf: bin.appendingPathComponent("calls.log"), encoding: .utf8)
    // служебный запрос названия (--ephemeral) — отдельно от ходов разговора
    let calls = log.components(separatedBy: "\n").filter { $0.hasPrefix("ARGS exec") && !$0.contains("--ephemeral") }
    #expect(calls.count == 2)
    #expect(calls[0].contains("-m gpt-6.1-sol") && calls[0].contains("read-only") && !calls[0].contains("resume"))
    #expect(calls[1].contains("resume th-42"))
    #expect(log.contains("STDIN <lumen-instructions>"))
    #expect(log.contains("STDIN И ещё"))
    // название придумал ChatGPT (быстрая модель, без сохранения сессии), а не первая фраза
    #expect(log.contains("--ephemeral") && log.contains("-m gpt-6-luna"))
    #expect(app.conversations.first?.title == "Привет от ChatGPT")

    // «Стоп» гасит процесс сразу
    app.chat.send("Подумай долго")
    try await Task.sleep(for: .milliseconds(400))
    let t0 = Date()
    app.chat.stop()
    while app.chat.running != nil { try await Task.sleep(for: .milliseconds(10)) }
    #expect(Date().timeIntervalSince(t0) < 0.5)
    #expect(app.chat.messages.last?.stopped == true)
}

@MainActor @Test func newAgentTaskRemembersItsOwnModelAndEffort() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-agentprefs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.tab = .agent
    app.chat.set(model: .sonnet, effort: .xhigh)
    #expect(app.defaultAgentModel == .sonnet)
    #expect(app.prefs.agentEffort == .xhigh)
    // у чата свои значения
    #expect(app.prefs.effort == .medium)
}
