import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

/// Своя тема до 1.4 становится темой в списке, а светлая/тёмная основа — светом
@Test func oldCustomThemeBecomesUserThemeAndLight() throws {
    let old = #"{"onboarded":true,"theme":"custom","customTheme":{"hue":0,"dark":false,"tint":0}}"#
    let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
    #expect(p.appearance == .light)
    #expect(p.userThemes.count == 1 && p.userThemes[0].hue == 0)
    #expect(p.themeID == p.userThemes[0].id)
    let light = try JSONDecoder().decode(Preferences.self, from: Data(#"{"theme":"light"}"#.utf8))
    #expect(light.themeID == "lumen" && light.appearance == .light)
    // уже новые настройки читаются как есть
    var n = Preferences()
    n.themeID = "aurora"; n.appearance = .system
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(n))
    #expect(back.themeID == "aurora" && back.appearance == .system)
}

/// Блок кода помнит язык — он подписью над кодом и расширением при скачивании
@MainActor @Test func codeBlockKeepsLanguage() {
    let parts = RichText.parts("Вот:\n\n```python\nprint(1)\n```\n\nи всё")
    #expect(parts.contains(.code("print(1)", lang: "python")))
    #expect(CodeBlock.fileName("python") == "код.py")
    #expect(CodeBlock.fileName(nil) == "код.txt")
    let plain = String(Highlighter.highlight("x = 1 # hi", lang: "python", palette: .lumen).characters)
    #expect(plain == "x = 1 # hi")
}

/// Плагины Claude Code (с их навыками) выключены в каждой сессии Lumen, хуки «Кастомизации» не теряются
@Test func claudePluginsAreSwitchedOff() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let hooks = dir.appendingPathComponent("hooks.json")
    try Data(#"{"hooks":{"Stop":[]}}"#.utf8).write(to: hooks)
    let s = try #require(ClaudeSession.Config.settings(file: hooks.path, pluginsOff: ["vercel@x", "design@synced"]))
    let o = try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    #expect((o["enabledPlugins"] as? [String: Bool]) == ["vercel@x": false, "design@synced": false])
    #expect(o["hooks"] != nil)
    var c = ClaudeSession.Config(model: "m")
    c.pluginsOff = ["a@b"]
    #expect(c.arguments.contains(#"{"enabledPlugins":{"a@b":false}}"#))
    #expect(c.arguments.contains("Skill"))
}

/// Режим разговора в приложении Claude → режим Lumen
@Test func desktopPermissionModeMaps() {
    #expect(ClaudeHistory.Desktop.Settings.mode("default") == .manual)
    #expect(ClaudeHistory.Desktop.Settings.mode("auto") == .auto)
    #expect(ClaudeHistory.Desktop.Settings.mode("plan") == .plan)
    #expect(ClaudeHistory.Desktop.Settings.mode(nil) == nil)
}

/// Таблица markdown — таблицей, и текст до и после неё не теряется
@MainActor @Test func markdownTableIsParsed() {
    let parts = RichText.parts("Блок:\n| Урок | Сценарий |\n|---|---|\n| 1.1 | Знакомство |\n| 1.2 | **Диалог** |\nИ дальше.")
    #expect(parts == [.prose("Блок:"), .table([["Урок", "Сценарий"], ["1.1", "Знакомство"], ["1.2", "**Диалог**"]]), .prose("И дальше.")])
    #expect(RichText.table("| a | b |\nне таблица") == nil)
}

/// Факт памяти Claude Code: описание из фронтматтера, тип → вид факта
@Test func claudeMemoryFileBecomesFact() {
    let md = "---\nname: x\ndescription: Рома любит короткие ответы\nmetadata:\n  type: feedback\ntype: feedback\n---\n\nТело"
    let f = AppModel.claudeMemoryFact(md, key: "claude-memory:x")
    #expect(f?.text == "Рома любит короткие ответы")
    #expect(f?.kind == .pref)
    #expect(f?.source == "Claude Code")
}

/// Свои цвета ложатся поверх темы только для своего света; контраст меняет линии
@MainActor @Test func overridesApplyPerLight() {
    var p = Preferences()
    p.themeID = "lumen"
    p.themeOverrides[Palette.overridesKey("lumen", dark: true)] = ThemeOverrides(background: "#102030")
    let dark = Palette.resolve(p, systemDark: false)
    p.appearance = .light
    let light = Palette.resolve(p, systemDark: false)
    #expect(dark.background.hexString == "#102030")
    #expect(light.background.hexString != "#102030")
    p.contrast = 100
    #expect(Palette.resolve(p, systemDark: false).borderScale > 1.5)
}

/// Картинка из разговора Claude ложится файлом один раз, сколько ни синхронизируй
@Test func claudeImageIsSavedOnce() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let data = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    let a = try #require(ClaudeHistory.saveImage("image/png", data, to: dir))
    let b = try #require(ClaudeHistory.saveImage("image/png", data, to: dir))
    #expect(a.path == b.path && a.kind == .image)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
}

/// Приписка агенту с путями вложений не показывается человеку, а вложения берутся по путям
@Test func savedAttachmentsNoteIsHidden() throws {
    let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try Data([1, 2, 3]).write(to: f)
    let (t, a) = Attachment.splitSavedNote("можно перевод чуть выделить\n\n(Вложения сохранены: Картинка.jpg — \(f.path); Нет.jpg — /нет/такого.jpg)")
    #expect(t == "можно перевод чуть выделить")
    #expect(a.count == 1 && a[0].kind == .image && a[0].path == f.path)
    #expect(Attachment.splitSavedNote("просто текст (в скобках)").text == "просто текст (в скобках)")
}

/// Что Lumen повторяет сам: сбои сети и API — да; лимит, вход, ошибки в самом запросе — нет
@MainActor @Test func transientFailuresAreRecognized() {
    #expect(ChatController.transient("API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"))
    #expect(ChatController.transient("API Error: 529 Overloaded"))
    #expect(ChatController.transient(""))
    #expect(!ChatController.transient("Claude AI usage limit reached"))
    #expect(!ChatController.transient("Invalid API key · Please run /login"))
    #expect(AnthropicAPI.retryable(status: 529) && AnthropicAPI.retryable(status: 503) && !AnthropicAPI.retryable(status: 400))
    #expect(AnthropicAPI.delay(1, retryAfter: nil) == 2 && AnthropicAPI.delay(3, retryAfter: nil) == 15)
    #expect(AnthropicAPI.delay(1, retryAfter: "120") == 60)
}

@MainActor @Test func longPromptIsNotRetried() {
    #expect(!ChatController.transient("prompt is too long: 250000 tokens > 200000 maximum"))
    #expect(ChatController.transient("API Error: 503 Service Unavailable"))
}

/// Варианты ответа и доп. папки агента переживают сохранение в базу; доп. папки уходят в --add-dir
@Test func variantsAndExtraPathsAreStored() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try Store(path: dir.appendingPathComponent("db.sqlite"))
    var c = Conversation(title: "т", kind: .agent, folder: "/tmp", backend: .subscription, model: .sonnet, effort: .high)
    c.extraPaths = ["/tmp/a"]
    try store.save(c)
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "новый")
    m.alternates = [AnswerVariant(text: "старый", steps: [], attachments: [], error: nil, model: .sonnet, createdAt: Date())]
    _ = try store.save(m)
    #expect(try store.conversations().first?.extraPaths == ["/tmp/a"])
    #expect(try store.messages(in: c.id).first?.alternates?.first?.text == "старый")
    var cfg = ClaudeSession.Config(model: "m")
    cfg.addDirs = ["/tmp/a"]
    #expect(cfg.arguments.contains("--add-dir"))
}
