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

/// Свои цвета — у своей темы и только для своего света; готовые темы не меняются; контраст меняет линии
@MainActor @Test func overridesApplyPerLight() {
    var p = Preferences()
    p.userThemes = [UserTheme(id: "user-a", name: "Своя", base: "lumen", darkColors: ThemeOverrides(background: "#102030"))]
    p.themeID = "user-a"
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
    #expect(Conversation(title: "чат", backend: .api, model: .sonnet, effort: .medium).usesCLI == false)
    #expect(Conversation(title: "агент", kind: .agent, folder: "/tmp", backend: .api, model: .sonnet, effort: .high).usesCLI == true)
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

@Test func markdownBlocksAreParsed() {
    let b = MarkdownBlocks.parse("# Заголовок\n\nАбзац\nвторая строка\n\n---\n\n- один\n  - вложенный\n- два\n1. раз\n2) два\n> цитата\n\n**не пункт**")
    #expect(b == [
        .heading(1, "Заголовок"), .paragraph("Абзац\nвторая строка"), .rule,
        .bullet(0, "один"), .bullet(1, "вложенный"), .bullet(0, "два"),
        .ordered(0, "1", "раз"), .ordered(0, "2", "два"), .quote("цитата"), .paragraph("**не пункт**"),
    ])
    #expect(MarkdownBlocks.isRule("- - -") && MarkdownBlocks.isRule("***") && !MarkdownBlocks.isRule("--"))
}

@Test func githubRepoIsParsedFromWhatPersonPasted() {
    #expect(GitHubRepo.parse("romankandeevy/lumen") == GitHubRepo(owner: "romankandeevy", name: "lumen"))
    #expect(GitHubRepo.parse("https://github.com/romankandeevy/lumen.git")?.slug == "romankandeevy/lumen")
    #expect(GitHubRepo.parse("https://github.com/anthropics/claude-code/tree/main/docs")?.slug == "anthropics/claude-code")
    #expect(GitHubRepo.parse("git@github.com:a/b.git")?.slug == "a/b")
    #expect(GitHubRepo.parse("github.com/a/b")?.cloneURL == "https://github.com/a/b.git")
    #expect(GitHubRepo.parse("https://example.com/a/b") == nil)
    #expect(GitHubRepo.parse("просто слова") == nil && GitHubRepo.parse("a") == nil && GitHubRepo.parse("") == nil)
}

@Test func webSearchAndMemoryAreOnByDefault() throws {
    let p = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(p.webSearch && p.useMemory)
    var q = p
    q.webSearch = false
    q.useMemory = false
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(q))
    #expect(!back.webSearch && !back.useMemory)
}

@Test func editedQuestionKeepsOldAnswerAsVariantWithItsPrompt() {
    var old = ChatMessage(conversationID: "c", role: .assistant, text: "ответ на старое")
    old.alternates = [AnswerVariant(text: "ещё раньше", steps: [], attachments: [], error: nil, model: .sonnet, createdAt: Date())]
    let all = (old.alternates ?? []) + [AnswerVariant(old, prompt: "старый вопрос")]
    #expect(all.count == 2 && all.last?.prompt == "старый вопрос" && all.last?.text == "ответ на старое" && all.first?.prompt == nil)
    // старые записи без «prompt» читаются
    let json = Data(#"{"text":"т","steps":[],"attachments":[],"createdAt":0}"#.utf8)
    #expect((try? JSONDecoder().decode(AnswerVariant.self, from: json))?.prompt == nil)
}

@Test func fileKindPicksThePreview() {
    #expect(FileKind.of(extension: "MD") == .markdown && FileKind.of(extension: "swift") == .text)
    #expect(FileKind.of(extension: "pdf") == .pdf && FileKind.of(extension: "png") == .image)
    #expect(FileKind.of(extension: "mp4") == .video && FileKind.of(extension: "mp3") == .audio)
    #expect(FileKind.of(extension: "pptx") == .office && FileKind.of(extension: "key") == .office && FileKind.of(extension: "docx") == .office)
    #expect(FileKind.of(extension: "usdz") == .model3d && FileKind.of(extension: "stl") == .model3d)
    #expect(FileKind.of(extension: "html") == .web && FileKind.of(extension: "zip") == .other)
    #expect(FileKind.markdown.hasText && FileKind.pdf.hasText && !FileKind.image.hasText)
}

@Test func sourcesAreFoundInAnswerAndSteps() {
    let text = "Победители держатся на одном [Vibe Jam](https://vibej.am/2026?utm_source=x) и на отклике: https://www.gamedeveloper.com/design/loop. "
        + "Повтор: [тот же](https://vibej.am/2026/) и ```\nhttps://in-code.dev\n```"
    var step = AgentStep(kind: .web, text: "Открывает https://itch.io/games")
    step.detail = "https://itch.io/games"
    let links = SourceLinks.extract(text: text, steps: [step])
    #expect(links.map(\.host) == ["vibej.am", "gamedeveloper.com", "itch.io"])
    #expect(links[0].title == "Vibe Jam" && links[1].title == nil)
    // без сети и всего с двумя ссылками — это не ответ с источниками
    #expect(SourceLinks.extract(text: "см. https://a.dev и https://b.dev", steps: []).isEmpty)
    #expect(SourceLinks.extract(text: "https://a.dev https://b.dev https://c.dev", steps: []).count == 3)
    #expect(SourceLinks.key("https://WWW.Site.com/a/#x") == SourceLinks.key("https://site.com/a"))
}

@Test func fileCardsInTextBecomeCardAndNote() {
    let first = FileMarks.marker("a1"), second = FileMarks.marker("b2")
    let draft = "\(first)поправь заголовок\n\(second)а тут цвета"
    #expect(FileMarks.ids(in: draft) == ["a1", "b2"])
    let sent = FileMarks.readable(draft, names: ["a1": "план.md", "b2": "эскиз.png"])
    #expect(sent == "[Файл: план.md]\nпоправь заголовок\n[Файл: эскиз.png]\nа тут цвета")
    #expect(FileMarks.segments(sent) == [.file("план.md"), .text("поправь заголовок"), .file("эскиз.png"), .text("а тут цвета")])
    // метка без вложения не остаётся в тексте
    #expect(FileMarks.strip(draft, keeping: ["b2"]) == "поправь заголовок\n\(second)а тут цвета")
    #expect(!FileMarks.hasFiles("просто текст"))
}

@Test func answerEndsWithoutTheSourcesListWhenCardsShowIt() {
    let list = """
    Вывод: ставь Dots, Grok пока слабее.

    Источники:

    - [OpenAI launches Dots](https://a.dev/dots)
    - [Grok Bot vs ChatGPT](https://b.dev/grok)
    - [Pricing 2026](https://c.dev/price)
    """
    #expect(SourceLinks.withoutListing(list) == "Вывод: ставь Dots, Grok пока слабее.")
    // жирный и решётки в заголовке, нумерованный список
    #expect(SourceLinks.withoutListing("Текст.\n\n**Источники**\n1. https://a.dev/x\n2. https://b.dev/y\n") == "Текст.")
    #expect(SourceLinks.withoutListing("Текст.\n\n## Sources\n- [a](https://a.dev)") == "Текст.")
    // не трогаем: нет заголовка, список не про ссылки, список не в конце, обычные пункты со ссылкой в середине
    #expect(SourceLinks.withoutListing("Текст.\n\n- [a](https://a.dev)\n- [b](https://b.dev)") == "Текст.\n\n- [a](https://a.dev)\n- [b](https://b.dev)")
    #expect(SourceLinks.withoutListing("Источники:\n- первый пункт\n- второй") == "Источники:\n- первый пункт\n- второй")
    let middle = "Источники:\n- [a](https://a.dev)\n\nА теперь вывод."
    #expect(SourceLinks.withoutListing(middle) == middle)
    // ссылка в тексте ответа остаётся
    #expect(SourceLinks.withoutListing("См. [доки](https://a.dev).\n\nИсточники:\n- [доки](https://a.dev)") == "См. [доки](https://a.dev).")
}

@Test func githubRepoGoesToTheModelAsOneRepository() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let summary = dir.appendingPathComponent("flowlocal.md")
    try "— README.md —\n# FlowLocal\n\n— Файлы (2) —\nREADME.md\nPackage.swift".write(to: summary, atomically: true, encoding: .utf8)
    var chat = Attachment(name: "flowlocal", kind: .text, mime: "text/plain", path: summary.path, size: 60)
    chat.repo = "romankandeevy/flowlocal"
    let text = chat.contentBlock()?["text"] as? String ?? ""
    #expect(text.contains("Репозиторий GitHub «romankandeevy/flowlocal»") && text.contains("Package.swift"))
    #expect(chat.repoOwner == "romankandeevy")
    #expect(chat.repoWebURL?.absoluteString == "https://github.com/romankandeevy/flowlocal")

    // агенту — папка; путь в блоке репозитория, без служебной приписки «Вложения сохранены»
    var agent = Attachment(name: "flowlocal", kind: .file, mime: "inode/directory", path: dir.path, size: 0)
    agent.repo = "romankandeevy/flowlocal"
    let blocks = Attachment.userContent(text: "Сделай промо", attachments: [agent], agent: true)
    let all = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    #expect(all.contains("склонирован в папку \(dir.path)"))
    #expect(!all.contains("Вложения сохранены"))
    #expect(all.hasSuffix("Сделай промо"))
}
