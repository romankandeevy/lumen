import Foundation
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenUI

/// Знакомство находит, что о человеке знают Claude Code и Codex на этом Маке
@MainActor @Test func knownSourcesFindClaudeAndCodexMemory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-known-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appendingPathComponent("home", isDirectory: true)
    let mem = home.appendingPathComponent(".claude/projects/-Users-x-prog/memory", isDirectory: true)
    try FileManager.default.createDirectory(at: mem, withIntermediateDirectories: true)
    try "---\nname: mac\ndescription: Делает приложения для Mac на SwiftUI\nmetadata:\n  type: user\n---\n\nТекст".write(to: mem.appendingPathComponent("mac.md"), atomically: true, encoding: .utf8)
    try "- [Mac](mac.md)".write(to: mem.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
    try "Пиши коротко.".write(to: home.appendingPathComponent(".claude/CLAUDE.md"), atomically: true, encoding: .utf8)
    let codex = home.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
    try "Отвечай по-русски.".write(to: codex.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
    let db = codex.appendingPathComponent("memories_1.sqlite")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = [db.path, "create table stage1_outputs (thread_id text, source_updated_at integer, raw_memory text); insert into stage1_outputs values ('a', 1, 'Учится в 11 классе');"]
    try p.run()
    p.waitUntilExit()

    let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("lumen", isDirectory: true)))
    let found = app.knownSources(home: home)
    #expect(found.map(\.kind) == [.claudeMemory, .claudeMD, .codexMemory, .codexMD])
    #expect(found[0].facts.map(\.text) == ["Делает приложения для Mac на SwiftUI"])
    #expect(found[0].detail == "1 факт")
    #expect(found[2].text.contains("11 классе"))

    // перенесённое второй раз не предлагается, повтор не сохраняется
    #expect(app.saveFacts(found[0].facts) == 1)
    #expect(app.saveFacts([MemoryFact(kind: .you, text: "делает приложения для Mac на SwiftUI!", source: "x")]) == 0)
    #expect(!app.knownSources(home: home).contains { $0.kind == .claudeMemory })
}

@Test func pastedAnswerSplitsIntoFactsWithoutModel() {
    let text = "```\n- Зовут Рома\n* Делает Lumen\nпросто строка\n- ок\n```"
    let facts = AppModel.lineFacts(text, source: "ChatGPT")
    #expect(facts.map(\.text) == ["Зовут Рома", "Делает Lumen"])
    #expect(facts.allSatisfy { $0.source == "ChatGPT" })
    #expect(AppModel.exportPrompt.contains("блоком кода"))
    #expect(AppModel.count(1, "факт", "факта", "фактов") == "1 факт")
    #expect(AppModel.count(3, "факт", "факта", "фактов") == "3 факта")
    #expect(AppModel.count(11, "факт", "факта", "фактов") == "11 фактов")
    #expect(AppModel.count(22, "факт", "факта", "фактов") == "22 факта")
}

/// «О тебе» в знакомстве — закреплёнными фактами; пустое поле при повторном знакомстве убирает старый ответ
@MainActor @Test func onboardingAboutYouGoesToMemory() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-about-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: app.prefs.theme,
                         about: ["work": "делаю приложения для Mac", "now": "Lumen 1.4.1", "style": ""])
    let work = app.memories.first { $0.key == "onboarding.work" }
    #expect(work?.text == "Чем занимается: делаю приложения для Mac")
    #expect(work?.pinned == true)
    #expect(app.memories.first { $0.key == "onboarding.now" }?.kind == .project)
    #expect(app.memories.first { $0.key == "onboarding.style" } == nil)
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: app.prefs.theme,
                         about: ["work": "", "now": "Lumen 1.5", "style": "коротко"])
    #expect(app.memories.first { $0.key == "onboarding.work" } == nil)
    #expect(app.memories.first { $0.key == "onboarding.now" }?.text == "Сейчас работает над: Lumen 1.5")
    #expect(app.memories.filter { $0.key == "onboarding.now" }.count == 1)
}

@Test func newSettingsHaveSafeDefaults() throws {
    let p = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(!p.notifyWhenDone && p.doneSound.isEmpty && !p.sendWithCommand && p.projectContextAuto)
}
