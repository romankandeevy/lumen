import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// Самостоятельная работа агента (19.10): ночь, «рядом ли человек», лимиты и автовыбор модели, своё сжатие

private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Moscow")!; return c }()
private func at(_ h: Int, _ m: Int, day: Int = 19) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }

@Test func nightWakesAtTheNextMorning() {
    #expect(Night.nextWake("06:00", after: at(23, 30), calendar: cal) == at(6, 0, day: 20))
    #expect(Night.nextWake("06:00", after: at(2, 10), calendar: cal) == at(6, 0))
    #expect(Night.nextWake("07:30", after: at(7, 30), calendar: cal) == at(7, 30, day: 20))
    #expect(Night.nextWake("ерунда", after: at(23, 0), calendar: cal) == at(6, 0, day: 20))
    #expect(Night.clock(at(6, 5), calendar: cal) == "06:05")
    var n = NightPrefs()
    #expect(!n.active())
    n.until = Date().addingTimeInterval(60)
    #expect(n.active())
    n.until = Date().addingTimeInterval(-60)
    #expect(!n.active())
}

@Test func oldSettingsWithoutNightStillDecode() throws {
    let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"onboarded":true}"#.utf8))
    #expect(p.presence && p.autoModel && p.autoCompact && p.compactAt == 70)
    #expect(p.night.wake == "06:00" && p.night.until == nil && p.night.keepAwake)
    let n = try JSONDecoder().decode(NightPrefs.self, from: Data(#"{"wake":"07:00"}"#.utf8))
    #expect(n.wake == "07:00" && n.waitForLimits)
}

@Test func awayMeansIdleOrLocked() {
    #expect(!Presence.isAway(idle: 30, screenLocked: false))
    #expect(Presence.isAway(idle: 6 * 60, screenLocked: false))
    #expect(Presence.isAway(idle: 1, screenLocked: true))
}

@Test func usageLimitIsRecognized() {
    #expect(UsageLimit.isLimit("Claude AI usage limit reached|1760000000"))
    #expect(UsageLimit.isLimit("You've hit your limit · resets 3am (Europe/Moscow)"))
    #expect(UsageLimit.isLimit("5-hour limit reached ∙ resets 9pm"))
    #expect(!UsageLimit.isLimit("API Error: 500 Internal server error"))
    #expect(!UsageLimit.isLimit("Can't reach the API server"))
}

@Test func handoffIsDueByPercentOrCap() {
    // окно 200 тыс.: 70% — 140 тыс.
    #expect(!Handoff.due(used: 139_000, window: 200_000, percent: 70))
    #expect(Handoff.due(used: 140_000, window: 200_000, percent: 70))
    // окно в 1 млн: 70% — это 700 тыс., но не позже 400 тыс.
    #expect(!Handoff.due(used: 399_000, window: 1_000_000, percent: 70))
    #expect(Handoff.due(used: 400_000, window: 1_000_000, percent: 70))
    #expect(!Handoff.due(used: 0, window: 0, percent: 70))
    let first = Handoff.prefix("## Задача\nПочинить вход")
    #expect(first.contains("<lumen-handoff>") && first.contains("Починить вход") && first.contains("recall"))
    #expect(Handoff.request.contains("## Как проверено") && Handoff.request.contains("Последние сообщения человека"))
}

@Test func modelIsSwitchedOnlyForItsOwnWeeklyLimit() {
    let opusOut = [UsageWindow(kind: .session, percent: 40, resetsAt: nil), UsageWindow(kind: .week, percent: 60, resetsAt: nil),
                   UsageWindow(kind: .weekModel("Opus"), percent: 100, resetsAt: nil)]
    let p = ModelChoice.pick(.opus, usage: opusOut)
    #expect(p.model == .sonnet && p.why?.contains("Opus 5.5") == true)
    // у Sonnet своего лимита нет — Sonnet и остаётся
    #expect(ModelChoice.pick(.sonnet, usage: opusOut).model == .sonnet)
    // общий лимит на 5 часов кончился — другая модель не поможет
    let sessionOut = [UsageWindow(kind: .session, percent: 100, resetsAt: nil), UsageWindow(kind: .weekModel("Opus"), percent: 100, resetsAt: nil)]
    #expect(ModelChoice.pick(.opus, usage: sessionOut).model == .opus)
    // и у Sonnet кончился — Haiku
    let both = opusOut + [UsageWindow(kind: .weekModel("Sonnet"), percent: 99, resetsAt: nil)]
    #expect(ModelChoice.pick(.opus, usage: both).model == .haiku)
    #expect(ModelChoice.chain(after: .fable) == [.opus, .sonnet, .haiku])
    #expect(ModelChoice.chain(after: .haiku).isEmpty)
    #expect(ModelChoice.pick(.gptSol, usage: opusOut).model == .gptSol)
}

@Test func agentGetsFallbackModelsAndNoQuestionWindow() {
    var c = ClaudeSession.Config.agent(model: "claude-opus-5-5", effort: "high", persona: "", folder: URL(fileURLWithPath: "/tmp"),
                                       sessionID: "s", resume: false)
    c.fallbackModels = ["claude-sonnet-5-5", "claude-haiku-5-5"]
    let a = c.arguments
    let i = a.firstIndex(of: "--fallback-model")
    #expect(i.map { a[$0 + 1] } == "claude-sonnet-5-5,claude-haiku-5-5")
    let off = a.firstIndex(of: "--disallowedTools").map { Array(a[($0 + 1)...]) } ?? []
    #expect(off.contains("AskUserQuestion") && off.contains("Bash(sudo:*)") && off.contains("Bash(git push:*)"))
}

@Test func autoMessagesAreMarkedAsFromLumen() {
    let v = Via.auto("утро")
    #expect(v.autoReason == "утро")
    #expect(Via(conversationID: "x", title: "Чат").autoReason == nil)
}

@Test func agentRulesExplainNightAndAbsence() {
    let core = AgentRules.core(userName: "Рома", ty: true, russianOnly: true)
    #expect(core.contains("<lumen-presence away=\"true\">"))
    #expect(core.contains("<lumen-night until=\"ЧЧ:ММ\">"))
    #expect(core.contains(Night.doneMark))
    #expect(Night.note(until: at(6, 0)).contains("Человек спит"))
}

// MARK: ночной страж

private func human(_ t: String) -> String { #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"\#(t)"}]}}"# }
private func say(_ t: String) -> String { #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(t)"}]}}"# }
private func bash(_ id: String, _ cmd: String) -> [String] {
    [#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(id)","name":"Bash","input":{"command":"\#(cmd)"}}]}}"#,
     #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok","is_error":false}]}}"#]
}
private let feedback = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Stop hook feedback: Рано заканчивать. Ночь"}]}}"#

@Test func nightGuardKeepsAgentWorkingUntilMorningOrDone() {
    let now = at(2, 0)
    let morning = at(6, 0)
    let worked = [human("сделай")] + bash("1", "swift test") + [say("Готово, тесты прошли.")]
    let r = ReadinessGuard.verdict(transcript: worked.joined(separator: "\n"), stopHookActive: false, nightUntil: morning, now: now)
    #expect(r?.contains("Ночь: человек спит до 06:00, осталось 4 ч 0 мин") == true)
    // даже на повторном заходе ночью — если между заходами он работал
    let again = worked + [feedback] + bash("2", "swift build") + [say("Проверил ещё раз.")]
    #expect(ReadinessGuard.verdict(transcript: again.joined(separator: "\n"), stopHookActive: true, nightUntil: morning, now: now) != nil)
    // сказал, что всё сделано, — отпускаем
    let done = worked + [say("Всё сделано и проверено. \(Night.doneMark)")]
    #expect(ReadinessGuard.verdict(transcript: done.joined(separator: "\n"), stopHookActive: true, nightUntil: morning, now: now) == nil)
    // вернули, а он ничего не сделал — делать правда нечего, отпускаем
    let idle = worked + [feedback, say("Больше делать нечего.")]
    #expect(ReadinessGuard.verdict(transcript: idle.joined(separator: "\n"), stopHookActive: true, nightUntil: morning, now: now) == nil)
    // утро уже наступило — обычный день
    #expect(ReadinessGuard.verdict(transcript: worked.joined(separator: "\n"), stopHookActive: false, nightUntil: morning, now: at(6, 1)) == nil)
    // ответ стража — не сообщение человека: ход не обрывается на нём
    #expect(!ReadinessGuard.isHumanMessage((try! JSONSerialization.jsonObject(with: Data(feedback.utf8))) as! [String: Any]))
}

@MainActor @Test func guardCommandPassesTheNightFile() throws {
    pointToMCP()
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-night-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let cmd = try #require(app.guardCommand)
    #expect(cmd.contains(" guard ") && cmd.hasSuffix("/night'"))
    // ночь: файл со временем утра; выключили — файла нет
    app.startNight()
    let text = try String(contentsOf: app.nightFile, encoding: .utf8)
    let until = try #require(ISO8601DateFormatter().date(from: text))
    #expect(until > Date() && until.timeIntervalSinceNow < 25 * 3600)
    #expect(app.chat.effectiveMode(Conversation(title: "т", kind: .agent, backend: .subscription, model: .opus, effort: .high)) == .bypassPermissions)
    app.endNight(morning: false)
    #expect(!FileManager.default.fileExists(atPath: app.nightFile.path))
    #expect(app.chat.effectiveMode(Conversation(title: "т", kind: .agent, backend: .subscription, model: .opus, effort: .high)) == nil)
}
