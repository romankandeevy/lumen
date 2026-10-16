import AppKit
import SwiftUI
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenUI
@testable import LumenProviders

// Снимки экранов для сверки с макетом (ui/, mockups/). Рисуются в невидимом окне — экран не трогают.
//   LUMEN_SNAP=/путь/к/папке swift test --filter Snapshots

private let snapDir = ProcessInfo.processInfo.environment["LUMEN_SNAP"]

@MainActor
enum Snap {
    static func registerFonts() {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Fonts").standardized
        setenv("LUMEN_ICONS", dir.deletingLastPathComponent().appendingPathComponent("Icons").path, 1)
        for f in ["Regular", "Medium", "SemiBold", "Bold"] {
            CTFontManagerRegisterFontsForURL(dir.appendingPathComponent("Geist-\(f).ttf") as CFURL, .process, nil)
        }
    }

    static func save<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 1180, height: 760)) async throws {
        guard let dir = snapDir else { return }
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        // как настоящее окно Lumen (.hiddenTitleBar): заголовок прозрачный, содержимое на всю высоту
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600)) // анимации и прокрутка до конца
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        window.close()
    }

    /// Приложение с чистыми данными во временной папке
    static func app() throws -> AppModel {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-snap-\(UUID().uuidString)")
        return try AppModel(paths: AppPaths(root: home))
    }
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotsMatchMockup() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    try await Snap.save(RootView(app: app), "01-onboarding")

    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    try await Snap.save(RootView(app: app), "03-new-chat")

    // разговор как в макете (mockups/02-chat.jpg)
    let c = Conversation(title: "Lumen: замысел", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Напомни, на чём мы остановились с Люменом и что я просил про кнопки?"))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Остановились на макете первой версии: память между разговорами, люди, характер ответов и боты-агенты.\n\nПро кнопки ты просил одно: когда я внедряю мокап или новую функцию, существующие кнопки остаются на местах. Двигаю только по твоей просьбе."))
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Да. И запомни: светлую тему не делаем, только тёмные."))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Понял. Тёмных тем будет две — «Люмен» и «Монохром». Светлой не будет."))
    for t in ["Что поделаем сегодня?", "Тексты для блога"] {
        try app.store.save(Conversation(title: t, backend: .subscription, model: .sonnet, effort: .medium))
    }
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "02-chat")

    for s in SettingsView.Section.allCases {
        app.page = .settings(s)
        try await Snap.save(RootView(app: app), "12-settings-\(s)")
    }
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotOrb() async throws {
    try await Snap.save(HStack(spacing: 60) {
        Orb(state: .idle, size: 96, animated: false)
        Orb(state: .idle, size: 22, animated: false).scaleEffect(4)
    }.frame(width: 400, height: 240).background(Palette.lumen.card).environment(\.palette, .lumen), "orb", size: CGSize(width: 400, height: 240))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotAgent() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let folders = ["lumen", "shelf", "island", "prog-dashboard"].map { FileManager.default.temporaryDirectory.appendingPathComponent($0) }
    for f in folders.reversed() {
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        app.rememberFolder(f)
    }
    app.agentFolder = folders[0]
    app.newAgentTask()
    try await Snap.save(RootView(app: app), "04-agent-empty")

    let c = Conversation(title: "Почему падает Shelf?", kind: .agent, folder: folders[1].path, backend: .subscription, model: .sonnet, effort: .high)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Почему падает Shelf при двойном щелчке?"))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant,
        text: "Нашёл: `ShelfStorage.remove(at:)` вызывается дважды, второй раз — с индексом, которого уже нет. Добавил проверку индекса.",
        steps: [.init(kind: .read, text: "Читает ShelfStorage.swift"), .init(kind: .search, text: "Ищет «remove(at:»"),
                .init(kind: .edit, text: "Правит ShelfStorage.swift"), .init(kind: .run, text: "Запускает: ./build.sh")],
        changes: ChangeSet(files: [FileChange(path: "Sources/ShelfStorage.swift", status: "M", added: 2, removed: 1)])))
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "05-agent-session")
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotMemory() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let c = Conversation(title: "Lumen: замысел", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    let facts: [(MemoryKind, String, Bool)] = [
        (.decision, "Только тёмные темы: «Люмен» и «Монохром»; светлую не делаем", true),
        (.pref, "При внедрении мокапа существующие кнопки остаются на местах", true),
        (.project, "Lumen — Mac-приложение по логике Hermes Agent, открытый код", false),
        (.people, "Папа — владелец kandeev.com, сайт без цен и кейсов с цифрами", false),
    ]
    var ids: [Int64] = []
    for (k, t, pin) in facts {
        let f = try app.store.save(MemoryFact(kind: k, text: t, source: c.title, conversationID: c.id, pinned: pin))
        ids.append(f.id!)
    }
    app.reloadMemories()
    app.reloadConversations()
    app.page = .memory
    try await Snap.save(RootView(app: app), "08-memory")

    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Да. И запомни: светлую тему не делаем, только тёмные."))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Понял. Тёмных тем будет две — «Люмен» и «Монохром». Светлой не будет.",
                                   remembered: [ids[0]], recalled: [ids[1]]))
    app.openChat(c)
    try await Snap.save(RootView(app: app), "02b-chat-remembered")
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotContextPanel() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let c = Conversation(title: "Lumen: замысел", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    let f = try app.store.save(MemoryFact(kind: .decision, text: "Только тёмные темы: «Люмен» и «Монохром»", source: c.title, conversationID: c.id, pinned: true))
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Какие темы делаем?"))
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "Две тёмные: «Люмен» и «Монохром». Светлой не будет.", recalled: [f.id!])
    m.contextTokens = 47_400
    m.contextWindow = 200_000
    try app.store.save(m)
    app.usage = [UsageWindow(kind: .session, percent: 34, resetsAt: Date().addingTimeInterval(3600)),
                 UsageWindow(kind: .week, percent: 12, resetsAt: Date().addingTimeInterval(86_400 * 3))]
    app.reloadMemories()
    app.reloadConversations()
    app.openChat(c)
    app.update { $0.contextOpen = true }
    try await Snap.save(RootView(app: app), "06-context-panel")
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotAgentPlanNext() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shelf")
    var c = Conversation(title: "Почему падает Shelf?", kind: .agent, folder: folder.path, backend: .subscription, model: .sonnet, effort: .high)
    c.plan = [.init(text: "Понять задачу и прочитать проект", state: .done, id: "1"),
              .init(text: "Сделать правки", state: .doing, id: "2"),
              .init(text: "Собрать и проверить", state: .todo, id: "3")]
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Почему падает Shelf при двойном щелчке?"))
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "Нашёл причину: двойной вызов `remove(at:)`. Добавил проверку индекса.",
                        steps: [.init(kind: .read, text: "Читает ShelfStorage.swift"), .init(kind: .edit, text: "Правит ShelfStorage.swift")],
                        changes: ChangeSet(files: [FileChange(path: "Sources/ShelfStorage.swift", status: "M", added: 2, removed: 1)]))
    m.next = NextStep(recap: "Сделал первую часть: нашёл причину и добавил проверку индекса. Собрать и проверить в приложении ещё не успел.",
                      ask: "Продолжать?", primary: .init(label: "Продолжай", reply: "Продолжай"),
                      secondary: .init(label: "Покажи план", reply: "Покажи, что будешь делать"))
    m.contextTokens = 61_000
    m.contextWindow = 200_000
    try app.store.save(m)
    app.reloadConversations()
    app.openChat(c)
    app.update { $0.contextOpen = true }
    try await Snap.save(RootView(app: app), "17-next-step", size: CGSize(width: 1280, height: 800))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotMenuAndSearch() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    var pinned = Conversation(title: "Lumen: замысел", backend: .subscription, model: .sonnet, effort: .medium)
    pinned.pinned = true
    try app.store.save(pinned)
    for t in ["привет", "Что поделаем сегодня?"] { try app.store.save(Conversation(title: t, backend: .subscription, model: .sonnet, effort: .medium)) }
    app.reloadConversations()
    try await Snap.save(RootView(app: app), "20-sidebar")
    app.showChatMenu(app.conversations[1], at: CGPoint(x: 200, y: 160))
    try await Snap.save(RootView(app: app), "21-chat-menu")
    app.menu = nil
    app.searchOpen = true
    try await Snap.save(RootView(app: app), "22-search")
    app.searchOpen = false
    app.update { $0.sidebarHidden = true }
    try await Snap.save(RootView(app: app), "23-sidebar-hidden")
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotProjects() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    let pr = app.createProject()
    app.updateProject(pr) {
        $0.name = "Блог kandeev.com"
        $0.instructions = "Пиши как редактор блога: коротко, без канцелярита. Цены и кейсы с цифрами не упоминать."
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("стиль-блога.md")
    try "# Стиль\nКороткие абзацы.".write(to: file, atomically: true, encoding: .utf8)
    app.addFile(file, to: app.project(pr.id)!)
    for t in ["Пост про новый сайт", "Заголовки для рассылки"] {
        var c = Conversation(title: t, backend: .subscription, model: .sonnet, effort: .medium)
        c.projectID = pr.id
        try app.store.save(c)
    }
    try app.store.save(Conversation(title: "привет", backend: .subscription, model: .sonnet, effort: .medium))
    app.reloadConversations()
    app.reloadProjects()
    app.page = .project(pr.id)
    try await Snap.save(RootView(app: app), "24-project")
}
