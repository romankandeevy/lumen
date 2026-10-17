import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
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
