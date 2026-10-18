import Foundation
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenUI

@Test func projectPromptCarriesFolderAndContextFile() {
    let p = Project(name: "Lumen", instructions: "Пиши коротко", folder: "/Users/x/prog/lumen")
    let s = p.promptBlock(files: [], context: "## Статус\nВ работе", contextPath: "/Users/x/prog/lumen/PROJECT.md")
    #expect(s.contains("Папка проекта: /Users/x/prog/lumen."))
    #expect(s.contains("Контекст проекта (/Users/x/prog/lumen/PROJECT.md):\n## Статус"))
    #expect(s.contains("не переспрашивай"))
    #expect(s.contains("add_to_project"))
    #expect(s.contains("Инструкции проекта:\nПиши коротко"))
}

@Test func projectPromptWithoutFolderHasNoFolderLine() {
    let s = Project(name: "Сайт").promptBlock(files: [])
    #expect(s.hasPrefix("Это разговор в проекте «Сайт»."))
    #expect(!s.contains("Папка проекта"))
    #expect(!s.contains("Контекст проекта ("))
}

@Test func contextLivesInProjectFolderOrInLumen() {
    let root = URL(fileURLWithPath: "/tmp/lumen-projects")
    let own = Project(name: "Lumen", folder: "/Users/x/prog/lumen")
    #expect(own.contextURL(fallback: root).path == "/Users/x/prog/lumen/PROJECT.md")
    let none = Project(name: "Без папки")
    #expect(none.contextURL(fallback: root).path == "/tmp/lumen-projects/\(none.id)/PROJECT.md")
    // домашняя папка — не папка проекта: PROJECT.md туда не кладём
    let home = Project(name: "Всё", folder: FileManager.default.homeDirectoryForCurrentUser.path)
    #expect(home.ownFolder == nil)
    #expect(home.contextURL(fallback: root).path.hasPrefix("/tmp/lumen-projects/"))
}

@Test func contextSectionsAreEditedInPlace() {
    var doc = ProjectContext.template(name: "Lumen", folder: "/p/lumen")
    for s in ProjectContext.sections { #expect(doc.contains("## \(s)")) }
    #expect(ProjectContext.section("Где", in: doc) == "Папка: `/p/lumen`")

    doc = ProjectContext.replacing("Статус", with: "1.4 собрана", in: doc)
    #expect(ProjectContext.section("Статус", in: doc) == "1.4 собрана")
    doc = ProjectContext.appending("Ждёт выпуска", to: "Статус", in: doc)
    #expect(ProjectContext.section("Статус", in: doc) == "1.4 собрана\n\nЖдёт выпуска")
    // соседние разделы целы
    #expect(ProjectContext.section("Где", in: doc) == "Папка: `/p/lumen`")
    #expect(ProjectContext.section("Решения", in: doc) == "")

    // компакт чата: второй раз заменяется, другой чат — рядом
    doc = ProjectContext.settingChat(id: "a", title: "Иконка", summary: "Сделали иконку.", in: doc)
    doc = ProjectContext.settingChat(id: "b", title: "Выпуск", summary: "Готовим 1.4.", in: doc)
    doc = ProjectContext.settingChat(id: "a", title: "Иконка", summary: "Иконка готова и в сборке.", in: doc)
    #expect(ProjectContext.chatSummary(id: "a", in: doc) == "Иконка готова и в сборке.")
    #expect(ProjectContext.chatSummary(id: "b", in: doc) == "Готовим 1.4.")
    #expect(doc.components(separatedBy: "<!-- chat:a -->").count == 2)

    // нет раздела — встаёт перед «Чатами»
    doc = ProjectContext.replacing("Люди", with: "Папа — заказчик", in: doc)
    let people = doc.range(of: "## Люди")!.lowerBound, chats = doc.range(of: "## Чаты")!.lowerBound
    #expect(people < chats)
    #expect(!doc.contains("\n\n\n"))
}

@Test func addToProjectWritesTextFilesAndLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ctx-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("site", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let paths = AppPaths(root: root.appendingPathComponent("lumen", isDirectory: true))
    try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
    let store = try Store(path: paths.database)
    let p = Project(name: "Сайт папы", folder: folder.path)
    try store.save(p)
    var c = Conversation(title: "Дизайн", backend: .subscription, model: .sonnet, effort: .low)
    c.projectID = p.id
    try store.save(c)
    let shot = root.appendingPathComponent("макет.png")
    try Data([0x89, 0x50]).write(to: shot)

    var tools = MemoryTools(store: store, conversationID: c.id, conversationTitle: c.title)
    #expect(tools.project == nil) // без папок Lumen инструмента нет
    tools.paths = paths
    #expect(tools.project?.id == p.id)
    let out = try tools.call("add_to_project", ["text": "Цвета: синий и белый", "section": "Заметки",
                                                "files": [shot.path, "нет-такого.pdf"], "links": ["https://kandeev.com"]])
    #expect(out.contains("Добавил"))
    #expect(out.contains("нет-такого.pdf"))
    let doc = try String(contentsOf: folder.appendingPathComponent("PROJECT.md"), encoding: .utf8)
    let notes = ProjectContext.section("Заметки", in: doc) ?? ""
    #expect(notes.contains("из чата «Дизайн»"))
    #expect(notes.contains("Цвета: синий и белый"))
    #expect(notes.contains("![макет.png](context/"))
    #expect(notes.contains("- https://kandeev.com"))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("context/макет.png").path))

    // разговор не в проекте — инструмента нет, вызов вежливо отказывает
    let loose = Conversation(title: "Просто", backend: .subscription, model: .sonnet, effort: .low)
    try store.save(loose)
    var other = MemoryTools(store: store, conversationID: loose.id, conversationTitle: loose.title)
    other.paths = paths
    #expect(other.project == nil)
    #expect(try other.call("add_to_project", ["text": "x", "section": "Заметки", "files": [], "links": []]).contains("не в проекте"))
}

@MainActor @Test func projectChatGetsContextFileAndModelAnswerIsApplied() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ctxapp-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let pr = app.createProject()
    app.newChat(in: pr)
    // проект без папки — PROJECT.md в папке Lumen, и он уже в промпте чата
    let url = app.contextURL(pr)
    #expect(url.path.hasPrefix(app.paths.projects.path))
    #expect(FileManager.default.fileExists(atPath: url.path))
    var c = Conversation(title: "Первый", backend: .subscription, model: .sonnet, effort: .medium)
    c.projectID = pr.id
    #expect(app.systemPrompt(for: c).contains("Контекст проекта (\(url.path))"))

    // ответ модели: меняются только названные разделы, компакт чата — в «Чатах»
    let doc = try String(contentsOf: url, encoding: .utf8)
    let next = AppModel.applyContext(["sections": ["Статус": "Начали", "Что это": NSNull()], "chat": "Обсудили начало."], to: doc, chat: c)
    #expect(ProjectContext.section("Статус", in: next) == "Начали")
    #expect(ProjectContext.section("Что это", in: next) == "")
    #expect(ProjectContext.chatSummary(id: c.id, in: next) == "Обсудили начало.")
}

@Test func personaUsesOwnTextAndDescription() {
    var p = Persona()
    #expect(!p.usesCustom)
    #expect(p.soul(userName: "Рома", ty: true) == p.built(userName: "Рома", ty: true))
    p.custom = "# Мой Lumen\nГоворит как пират."
    #expect(p.usesCustom)
    #expect(p.soul(userName: "Рома", ty: true) == "# Мой Lumen\nГоворит как пират.")
    #expect(p.reminder.contains("характер"))

    let g = Persona().applying(["name": "Люми", "warmth": "dry", "length": "long", "emoji": true,
                                "never": ["Извиняться", " "], "humor": "непонятно"])
    #expect(g.name == "Люми")
    #expect(g.warmth == .dry && g.length == .long && g.emoji)
    #expect(g.never == ["Извиняться"])
    #expect(g.humor == Persona().humor) // непонятное значение не ломает настройку
}

private let liveContext = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

/// Живая проверка на настоящем claude (Haiku): проект с папкой сам заполняет PROJECT.md по README,
/// а после разговора дописывает статус и компакт чата
@MainActor @Test(.enabled(if: liveContext)) func liveProjectContextFillsItself() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ctxlive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let folder = home.appendingPathComponent("winrate", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "# Winrate\n\nСчётчик винрейта для Mac на SwiftUI. Сборка: `./build.sh`, запуск: `./build.sh run`.\n"
        .write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    let app = try AppModel(paths: AppPaths(root: home.appendingPathComponent("lumen", isDirectory: true)))
    await app.refreshClaude()
    let pr = app.createProject(folder: folder)
    let url = app.contextURL(pr)
    #expect(url.path == folder.appendingPathComponent("PROJECT.md").path)
    // первое заполнение идёт фоном — ждём, пока раздел «Что это» появится
    for _ in 0..<60 where (ProjectContext.section("Что это", in: (try? String(contentsOf: url, encoding: .utf8)) ?? "") ?? "").isEmpty {
        try await Task.sleep(for: .seconds(1))
    }
    let filled = try String(contentsOf: url, encoding: .utf8)
    #expect(!(ProjectContext.section("Что это", in: filled) ?? "").isEmpty)
    #expect((ProjectContext.section("Стек и запуск", in: filled) ?? "").contains("build.sh"))

    var c = Conversation(title: "Тёмная тема", backend: .subscription, model: .haiku, effort: .low)
    c.projectID = pr.id
    try app.store.save(c)
    _ = try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Решили: делаем тёмную тему по умолчанию, светлую убираем."))
    _ = try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Сделал тёмную тему по умолчанию и убрал светлую. Осталось обновить скриншоты в README."))
    app.reloadConversations()
    app.updateProjectContext(after: c)
    for _ in 0..<60 where ProjectContext.chatSummary(id: c.id, in: (try? String(contentsOf: url, encoding: .utf8)) ?? "") == nil {
        try await Task.sleep(for: .seconds(1))
    }
    let after = try String(contentsOf: url, encoding: .utf8)
    #expect(ProjectContext.chatSummary(id: c.id, in: after) != nil)
    #expect(after.lowercased().contains("тёмн") || after.lowercased().contains("темн"))
    print("PROJECT.md после живой проверки:\n\(after)")
}
