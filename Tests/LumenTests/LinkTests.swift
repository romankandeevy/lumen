import AppKit
import Foundation
import Testing
@testable import LumenCore
@testable import LumenUI

@MainActor @Test func bareAddressesBecomeLinksButFileNamesDoNot() {
    let a = RichText.markdown("Сайт https://kandeev.com/about, зеркало www.example.org и файл README.md, код `https://x.dev` и [доки](https://docs.dev)")
    let links = a.runs.compactMap { run in run.link.map { (String(a[run.range].characters), $0.absoluteString) } }
    #expect(links.contains { $0.0 == "https://kandeev.com/about" && $0.1 == "https://kandeev.com/about" })
    #expect(links.contains { $0.0 == "www.example.org" })
    #expect(links.contains { $0.0 == "доки" && $0.1 == "https://docs.dev" })
    #expect(!links.contains { $0.0.contains("README") })
    #expect(!links.contains { $0.0.contains("x.dev") }) // в коде не трогаем
}

@MainActor @Test func linkTextKeepsLinksAndStylesAndFindsLinkUnderCursor() throws {
    let a = RichText.markdown("Открой **сайт** https://kandeev.com сейчас")
    let base = NSFont(name: "Geist-Regular", size: 15) ?? .systemFont(ofSize: 15)
    let s = LinkText.styled(a, base: base, size: 15, extra: 4, color: .white)
    let ns = s.string as NSString
    let at = ns.range(of: "https://kandeev.com")
    #expect((s.attribute(.link, at: at.location, effectiveRange: nil) as? URL)?.absoluteString == "https://kandeev.com")
    let bold = s.attribute(.font, at: ns.range(of: "сайт").location, effectiveRange: nil) as? NSFont
    #expect(bold?.fontName != base.fontName)

    let v = LinkTextView()
    v.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
    v.setText(s)
    let h = v.height(for: 600)
    #expect(h > 10 && h < 60)
    let l = try #require(v.layoutManager), c = try #require(v.textContainer)
    let glyphs = l.glyphRange(forCharacterRange: NSRange(location: at.location + 3, length: 1), actualCharacterRange: nil)
    let r = l.boundingRect(forGlyphRange: glyphs, in: c)
    let inside = NSPoint(x: r.midX + v.textContainerOrigin.x, y: r.midY + v.textContainerOrigin.y)
    #expect(v.link(at: inside) == at)
    #expect(v.link(at: NSPoint(x: 2, y: r.midY + v.textContainerOrigin.y)) == nil)
}

@Test func linkTargetDefaultsToSideBrowser() throws {
    let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(old.linkTarget == .side)
    var p = old
    p.linkTarget = .system
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
    #expect(back.linkTarget == .system)
}

/// Курсор над ссылкой — она подчёркивается целиком; ушёл — подчёркивание пропадает
@MainActor @Test func hoveredLinkIsUnderlined() throws {
    let a = RichText.markdown("Смотри https://kandeev.com/about и дальше")
    let s = LinkText.styled(a, base: .systemFont(ofSize: 15), size: 15, extra: 4, color: .white)
    let at = (s.string as NSString).range(of: "https://kandeev.com/about")
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    let v = LinkTextView()
    v.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
    w.contentView = v
    v.setText(s)
    _ = v.height(for: 600)
    let l = try #require(v.layoutManager), c = try #require(v.textContainer)
    let r = l.boundingRect(forGlyphRange: l.glyphRange(forCharacterRange: NSRange(location: at.location + 5, length: 1), actualCharacterRange: nil), in: c)
    func move(to p: NSPoint) throws {
        let e = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: v.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                                 windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        v.mouseMoved(with: e)
    }
    try move(to: NSPoint(x: r.midX + v.textContainerOrigin.x, y: r.midY + v.textContainerOrigin.y))
    var eff = NSRange()
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: at.location + 1, effectiveRange: &eff) != nil)
    #expect(eff == at)
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: 1, effectiveRange: nil) == nil)
    try move(to: NSPoint(x: 1, y: r.midY + v.textContainerOrigin.y))
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: at.location + 1, effectiveRange: nil) == nil)
}

@Test func checkboxesAndNestedQuotesAreParsed() {
    #expect(MarkdownBlocks.parse("- [x] готово\n- [ ] ждёт\n  - [X] вложенное\n- [x]не чекбокс\n- обычный") == [
        .task(0, true, "готово"), .task(0, false, "ждёт"), .task(1, true, "вложенное"), .bullet(0, "[x]не чекбокс"), .bullet(0, "обычный"),
    ])
    #expect(MarkdownBlocks.parse("> раз\n> > два\n> > ещё\n\n> снова") == [.quote(1, "раз"), .quote(2, "два\nещё"), .quote(1, "снова")])
}

@MainActor @Test func linksAreItalicAndTasksGetBoxes() {
    let base = NSFont.systemFont(ofSize: 15)
    let s = LinkText.styledBlocks("- [x] сделано\n- [ ] ждёт\n\nСмотри [доки](https://docs.dev)", base: base, size: 15, extra: 4, color: .white, muted: .gray)
    let ns = s.string as NSString
    #expect(ns.contains("☑\tсделано") && ns.contains("☐\tждёт"))
    let at = ns.range(of: "доки").location
    let font = s.attribute(.font, at: at, effectiveRange: nil) as? NSFont
    let slanted = (s.attribute(.obliqueness, at: at, effectiveRange: nil) as? Double ?? 0) > 0
    #expect(slanted || font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    #expect(s.attribute(.strikethroughStyle, at: ns.range(of: "сделано").location, effectiveRange: nil) != nil)
    #expect(s.attribute(.strikethroughStyle, at: ns.range(of: "ждёт").location, effectiveRange: nil) == nil)
}

@Test func tildeFencesAndFormulasBecomeBlocks() {
    let parts = RichText.parts("Вот код:\n\n~~~python\nprint(1)\n~~~\n\n$$\nE = mc^2\n$$\n\n\\[ a^2 + b^2 = c^2 \\]\n\n```math\n\\int_0^1 x\\,dx\n```")
    #expect(parts.contains(.code("print(1)", lang: "python")))
    let visuals = parts.compactMap { part -> String? in if case .visual(let h, true) = part { h } else { nil } }
    #expect(visuals.count == 3)
    #expect(visuals[0].contains("E = mc^2") && visuals[1].contains("a^2 + b^2 = c^2") && visuals[2].contains("int_0^1"))
    #expect(MathBlock.display("цена $$ и $$ ещё") == nil)
}

@MainActor @Test func lineBreakTagsBecomeNewlines() {
    #expect(String(RichText.markdown("раз<br>два<BR/>три").characters) == "раз\nдва\nтри")
}

@Test func sidebarAndMainHaveTheirOwnGlass() throws {
    let none = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(none.glassSidebar == 0 && none.glassMain == 0)
    let clamped = try JSONDecoder().decode(Preferences.self, from: Data(#"{"glassSidebar":5,"glassMain":-1}"#.utf8))
    #expect(clamped.glassSidebar == 1 && clamped.glassMain == 0)
    // прежние настройки (булевы переключатели) не ломают разбор
    let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"glass":0.5,"glassSidebar":true,"glassMain":false}"#.utf8))
    #expect(old.glassSidebar == 0 && old.glassMain == 0)
    var p = Preferences()
    p.glassSidebar = 0.4
    p.glassMain = 0.15
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
    #expect(back.glassSidebar == 0.4 && back.glassMain == 0.15)
}

@Test func eclipseMarkIsOnByDefaultAndCanBeSwitchedOff() throws {
    #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).showMark)
    var p = Preferences()
    p.showMark = false
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)).showMark == false)
}

@Test func agentSuggestionsHaveFallbackAndPromptKnowsTheFolder() {
    #expect(Suggestions.agentFallback(home: false).count == 3 && Suggestions.agentFallback(home: true).count == 3)
    let p = Suggestions.agentPrompt(name: "Рома", folder: "lumen", home: false, branch: "main", changed: 3, files: ["Sources", "README.md"], recent: ["Починить таблицы"])
    #expect(p.contains("lumen") && p.contains("main") && p.contains("README.md") && p.contains("Починить таблицы") && p.contains("Рома"))
    // у домашней папки список файлов не уходит
    let home = Suggestions.agentPrompt(name: "", folder: "roman", home: true, branch: nil, changed: 0, files: [], recent: [])
    #expect(home.contains("домашняя папка") && !home.contains("Что лежит"))
    #expect(Suggestions.parse(#"["Почини тесты", "Разбери README", "Убери дубли"]"#) == ["Почини тесты", "Разбери README", "Убери дубли"])
}

@Test func dictationAppendsToWhatIsAlreadyInTheField() throws {
    #expect(VoiceInput.merged(base: "", transcript: " привет ") == "привет")
    #expect(VoiceInput.merged(base: "Напиши", transcript: "письмо") == "Напиши письмо")
    #expect(VoiceInput.merged(base: "Напиши ", transcript: "письмо") == "Напиши письмо")
    #expect(VoiceInput.merged(base: "Строка\n", transcript: "вторая") == "Строка\nвторая")
    #expect(VoiceInput.merged(base: "Уже было", transcript: "  ") == "Уже было")
    #expect(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).voiceLanguage == "ru-RU")
    #expect(VoiceInput.modelLanguage("ru-RU") == "ru" && VoiceInput.modelLanguage("en-US") == "en")
}

/// Без этих описаний macOS закрывает приложение в тот момент, когда оно просит микрофон
@Test func infoPlistExplainsMicrophoneAndSpeechAccess() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Info.plist")
    let plist = try #require(NSDictionary(contentsOf: url))
    #expect((plist["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false)
    // распознаёт FlowLocal, а не система: разрешение на речь не нужно
    #expect(plist["NSSpeechRecognitionUsageDescription"] == nil)
}

/// Настоящий круг: речь (голос системы) → запись 16 кГц → процесс FlowLocal → текст. Без FlowLocal на Маке — пропускается
@Test func flowLocalRecognizesSpokenRussian() async throws {
    guard VoiceBackend.python.path.isEmpty == false, FileManager.default.isExecutableFile(atPath: VoiceBackend.python.path),
          FileManager.default.fileExists(atPath: VoiceBackend.modelDir("ru").path),
          FileManager.default.isExecutableFile(atPath: "/usr/bin/say"), FileManager.default.isExecutableFile(atPath: "/usr/bin/afconvert") else { return }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Voice/server.py")
    setenv("LUMEN_VOICE_SCRIPT", script.path, 1)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func run(_ exe: String, _ args: [String]) throws -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }
    let aiff = dir.appendingPathComponent("a.aiff").path, wav = dir.appendingPathComponent("a.wav").path
    // нет русского голоса — нечего проверять
    guard try run("/usr/bin/say", ["-v", "Milena", "Привет, как дела? Проверка голосового ввода.", "-o", aiff]),
          try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav]) else { return }
    let raw = try Data(contentsOf: URL(fileURLWithPath: wav)).dropFirst(44)
    let samples = raw.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Float($0) / 32768 }
    let text = try #require(await VoiceBackend.shared.transcribe(samples, lang: "ru"))
    VoiceBackend.shared.shutdown()
    #expect(text.lowercased().contains("как дела") && text.lowercased().contains("проверка"))
}
