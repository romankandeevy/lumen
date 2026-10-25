import AppKit
import SwiftUI
import WebKit
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
        CTFontManagerRegisterFontsForURL(dir.appendingPathComponent("Literata.ttf") as CFURL, .process, nil)
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
    // знак-затмение: покой, «горячий» (поле в фокусе), малый и малый «думает» — в тёмной и светлой темах
    func row(_ p: Palette) -> some View {
        HStack(spacing: 70) {
            LumenMark(state: .idle, size: 78, animated: false)
            LumenMark(state: .idle, size: 78, animated: false, hot: true)
            LumenMark(state: .idle, size: 24, animated: false).scaleEffect(3)
            LumenMark(state: .thinking, size: 24).scaleEffect(3)
        }
        .frame(width: 640, height: 200).background(p.background).environment(\.palette, p)
    }
    let fams = Palette.Family.builtIn
    try await Snap.save(VStack(spacing: 0) { row(.lumen); row(.light); row(fams[1].dark); row(fams[2].dark); row(fams[3].dark); row(fams[4].dark) },
                        "orb", size: CGSize(width: 640, height: 1200))
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
    // настоящая папка с git — сам репозиторий Lumen
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    app.rememberFolder(repo)
    for (t, ago) in [("Проекты как в Claude", 600.0), ("Верх панели и меню «…»", 7200.0)] {
        try app.store.save(Conversation(title: t, kind: .agent, folder: repo.path, backend: .subscription, model: .sonnet, effort: .high,
                                        createdAt: Date().addingTimeInterval(-ago), updatedAt: Date().addingTimeInterval(-ago)))
    }
    app.reloadConversations()
    app.agentFolder = repo
    app.newAgentTask()
    try await Snap.save(RootView(app: app), "04-agent-empty")

    let c = Conversation(title: "Почему падает Shelf?", kind: .agent, folder: folders[1].path, backend: .subscription, model: .sonnet, effort: .high)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Почему падает Shelf при двойном щелчке?"))
    // как в Claude Code: абзац — шаги — абзац
    let p1 = "Смотрю, где Shelf обрабатывает двойной щелчок."
    let p2 = "Нашёл: `ShelfStorage.remove(at:)` вызывается дважды, второй раз — с индексом, которого уже нет. Добавляю проверку индекса."
    let p3 = "Собрал и проверил: двойной щелчок больше не роняет Shelf."
    let e1 = p1.count, e2 = p1.count + 2 + p2.count
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant,
        text: [p1, p2, p3].joined(separator: "\n\n"),
        steps: [.init(kind: .read, text: "Читает ShelfStorage.swift", at: e1), .init(kind: .search, text: "Ищет «remove(at:»", at: e1),
                .init(kind: .read, text: "Читает ShelfView.swift", at: e1),
                .init(kind: .edit, text: "Правит ShelfStorage.swift", at: e2), .init(kind: .run, text: "Запускает: ./build.sh", at: e2),
                .init(kind: .run, text: "Запускает: swift test", at: e2)],
        changes: ChangeSet(files: [FileChange(path: "Sources/ShelfStorage.swift", status: "M", added: 2, removed: 1)])))
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "05-agent-session")

    let now = Date()
    let lumenGroup = ClaudeHistory.Desktop.Group(id: "g1", name: "LUMEN")
    let english = ClaudeHistory.Desktop.Group(id: "g2", name: "Изучение английского")
    let hermes = ClaudeHistory.Desktop.Group(id: "g3", name: "Hermes")
    let sessions = [("Агент с контекстом проектов", "~/Documents/prog", "Настрой Lumen, чтобы проекты работали", 600.0, lumenGroup),
                    ("Люмен: дизайн и логика", "~/Documents/prog", "Сделай дизайн как в Claude", 7200.0, lumenGroup),
                    ("Изучение", "~/Documents/prog", "ghbdtn", 3600.0, english),
                    ("Кнопка Shelf падает", "~/Documents/prog/shelf", "Почини двойной щелчок в Shelf", 1800.0, nil),
                    ("Чем займёмся?", "~/Documents/prog", "Что поделаем?", 90000.0, nil)].enumerated().map { i, s in
        ClaudeHistory.Session(id: "s\(i)", file: URL(fileURLWithPath: "/tmp/s\(i).jsonl"),
                              cwd: s.1.replacingOccurrences(of: "~", with: NSHomeDirectory()), title: s.0,
                              firstPrompt: s.2, updatedAt: now.addingTimeInterval(-s.3), bytes: 1000, group: s.4)
    }
    try await Snap.save(ImportClaudeSheet(app: app, close: {}, preset: .init(sessions: sessions, groups: [lumenGroup, english, hermes]),
                                          prepicked: ["s0", "s1", "s3"])
        .environment(\.palette, Palette.of(.lumen)), "40-import-claude", size: CGSize(width: 680, height: 640))

    // план под перепиской, как в Claude
    var pc = Conversation(title: "Паспорт как книжка", kind: .agent, folder: folders[0].path, backend: .subscription, model: .opus, effort: .high)
    pc.plan = [PlanItem(text: "Посмотреть, что поменялось в макетах", state: .done), PlanItem(text: "Паспорт как открытая книжка с закладкой", state: .doing),
               PlanItem(text: "Новая галерея index.html", state: .todo), PlanItem(text: "Обновить localhost и проверить", state: .todo)]
    try app.store.save(pc)
    try app.store.save(ChatMessage(conversationID: pc.id, role: .user, text: "Сделай паспорт как открытую книжку"))
    let t1 = "Смотрю, что поменялось в макетах."
    try app.store.save(ChatMessage(conversationID: pc.id, role: .assistant, text: t1 + "\n\nПаспорт делаю разворотом: слева фото и данные, справа штампы.",
        steps: [.init(kind: .run, text: "Запускает: ls macets", at: t1.count), .init(kind: .read, text: "Читает passport.html", at: t1.count),
                .init(kind: .run, text: "Запускает: git diff", at: t1.count)]))
    app.reloadConversations()
    app.openChat(pc)
    try await Snap.save(RootView(app: app), "42-plan-card")

    // картинки агента: маленькие превью и «+N», как в Claude Code
    var shots: [LumenCore.Attachment] = []
    for (i, color) in [NSColor.systemBlue, .systemOrange, .systemPink, .systemTeal, .systemPurple, .systemGreen, .systemYellow].enumerated() {
        let img = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { r in
            color.withAlphaComponent(0.6).setFill(); r.fill()
            NSColor.white.setFill(); NSRect(x: 40, y: 40, width: 560, height: 60).fill()
            return true
        }
        if let a = app.importImage(img, name: "Снимок \(i + 1).png") { shots.append(a) }
    }
    var withShots = ChatMessage(conversationID: pc.id, role: .assistant, text: "Снял все экраны галереи — смотри превью.",
                                steps: [.init(kind: .web, text: "Открывает localhost", at: 0)])
    withShots.attachments = shots
    try app.store.save(withShots)
    app.chat.reloadMessages()
    try await Snap.save(RootView(app: app), "43-agent-shots")

    // файл вложением (make_file) и вкладка «Артефакты»
    let md = FileManager.default.temporaryDirectory.appendingPathComponent("plan-\(UUID().uuidString.prefix(4)).md")
    try "# План паспорта\n\n- Разворот\n- Штампы\n- Закладка в цвете языка".write(to: md, atomically: true, encoding: .utf8)
    if var fileA = app.importAttachment(md) {
        fileA.name = "passport-plan.md"
        var fm = ChatMessage(conversationID: pc.id, role: .assistant, text: "Сделал план файлом — открой сбоку или скачай.")
        fm.attachments = [fileA]
        try app.store.save(fm)
        app.chat.reloadMessages()
    }
    try await Snap.save(RootView(app: app), "44-make-file")
    app.page = .artifacts
    // один снимок уже прикреплён к чату — внизу полоска «ждёт в поле ввода»
    app.attachInbox = Array(shots.prefix(1))
    try await Snap.save(RootView(app: app), "45-artifacts")
    app.attachInbox = []
    app.page = .chat

    // два разговора рядом (бросили разговор в правую половину окна)
    app.openChat(pc)
    app.openSplit(c)
    try await Snap.save(RootView(app: app), "46-split", size: CGSize(width: 1500, height: 820))
    app.closeSplit()

    // строка проекта под мышью: «+» и «…» в ряд, название обрезается до них
    let longP = Project(name: "Изучение английского языка для путешествий", folder: folders[0].path)
    try app.store.save(longP)
    app.reloadProjects()
    ProjectRow.snapHover = true
    try await Snap.save(VStack { ProjectRow(app: app, project: longP, open: false, count: 3) {} }.padding(12).frame(width: 260)
        .environment(\.palette, Palette.of(.lumen)).background(Palette.of(.lumen).sidebar), "47-project-hover", size: CGSize(width: 260, height: 56))
    ProjectRow.snapHover = false

    // «Характер»
    app.page = .persona
    try await Snap.save(RootView(app: app), "48-persona", size: CGSize(width: 1500, height: 900))
    app.page = .chat

    // браузер сбоку: пустой, с подсказкой про входы в аккаунты (страницу WebKit рисует сам, в снимок она не попадает)
    app.browserOpen = true
    try await Snap.save(RootView(app: app), "41-browser", size: CGSize(width: 1440, height: 820))
    app.browserOpen = false
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

/// Боты: каталог, конструктор, разговор бота с паспортом, ответ бота в обычном чате (@id)
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotBots() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.saveBot(Bot(id: "tester", name: "Тестировщик", icon: "flask-conical", hue: 160, role: "Проверяет приложения и правки — и только",
                    instructions: "Собирает проект, гоняет тесты. Сам ничего не чинит.", capabilities: [.read, .run, .memory],
                    commands: ["swift test", "./build.sh"], folder: NSHomeDirectory() + "/Documents/prog",
                    starters: ["Протестируй последний коммит в Shelf", "Что сломалось в прошлый раз?"], handoff: "coder"))
    app.saveBot(Bot(id: "coder", name: "Кодер prog", icon: "code-xml", hue: 235, role: "Пишет и чинит код Mac-приложений",
                    capabilities: [.read, .write, .run, .git, .memory], model: .opus))
    app.saveBot(Bot(id: "writer", name: "Тексты для сайта", icon: "pen-line", hue: 200, role: "Тексты для kandeev.com",
                    capabilities: [.read, .web]))
    app.page = .bots
    try await Snap.save(RootView(app: app), "30-bots")

    app.page = .botEditor("tester")
    try await Snap.save(RootView(app: app), "31-bot-editor")
    // весь конструктор целиком — высоким окном
    try await Snap.save(RootView(app: app), "31b-bot-editor-full", size: CGSize(width: 1180, height: 1900))
    app.page = .botEditor(nil)
    try await Snap.save(RootView(app: app), "31c-bot-new", size: CGSize(width: 1180, height: 1900))
    // «Работают»: бота позвали из чата
    app.botRuns["tester"] = "Почему падает Shelf?"
    app.page = .bots
    try await Snap.save(RootView(app: app), "30b-bots-working")
    app.botRuns = [:]
    // подсказка ботов при наборе «@»
    app.newChat()
    try await Snap.save(VStack { Spacer(); Composer(app: app, draft: .constant("@"), attachments: .constant([]), backend: .subscription) }
        .environment(\.palette, Palette.of(.lumen)).background(Palette.of(.lumen).background), "35-mention-popup",
        size: CGSize(width: 900, height: 360))

    app.openBot("tester")
    try await Snap.save(RootView(app: app), "32-bot-empty")

    let b = try #require(app.bot("tester"))
    let bc = app.botConversation(for: b)
    try app.store.save(ChatMessage(conversationID: bc.id, role: .user, text: "Прогони тесты Lumen"))
    var r = ChatMessage(conversationID: bc.id, role: .assistant, text: "Собрал и прогнал: 51 тест, все зелёные. Падений нет.",
                        steps: [AgentStep(kind: .run, text: "Запускает: swift test")])
    r.botID = "tester"
    try app.store.save(r)
    app.chat.reloadMessages()
    app.update { $0.contextOpen = true }
    try await Snap.save(RootView(app: app), "33-bot-chat")

    app.update { $0.contextOpen = false }
    let c = Conversation(title: "Почему падает Shelf?", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "@tester проверь фикс двойного щелчка в Shelf"))
    var d = ChatMessage(conversationID: c.id, role: .assistant, text: "Проверил: двойной щелчок по полке больше не роняет Shelf. Прогнал сценарий 10 раз.",
                        steps: [AgentStep(kind: .run, text: "Запускает: ./build.sh"), AgentStep(kind: .read, text: "Читает ShelfView.swift")])
    d.botID = "tester"
    try app.store.save(d)
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "34-mention")
}

/// Граф памяти (как mockups: memory-graph): «Меньше движения» — раскладка сразу до покоя
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotGraph() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.reducedMotion = true }
    for name in ["Lumen", "Shelf", "Пульт", "Island", "kandeev.com", "FlowLocal"] { try app.store.save(Project(name: name)) }
    app.reloadProjects()
    let facts: [(MemoryKind, String, Bool)] = [
        (.you, "Рома делает Mac-приложения на Swift и сайты; работает в ~/Documents/prog", true),
        (.pref, "Не двигать существующие кнопки, когда внедряю мокап или фичу, — только по просьбе", true),
        (.pref, "Отвечать коротко, по-русски, простыми словами", false),
        (.decision, "Интерфейс Mac-приложений — только SwiftUI: Пульт, Island, Shelf, Lumen", false),
        (.project, "Shelf: вкладку «Полка» убрали, файлы идут в Буфер — это видно в Island", false),
        (.project, "kandeev.com — папин сайт; превью в ветке preview, прод — только по OK", false),
        (.decision, "HandPilot пробовали и бросили — не предлагать снова", false),
        (.you, "Говорит голосом через FlowLocal — в тексте бывают оговорки", false),
        (.project, "Lumen: v1 — память, люди, характер и боты-агенты", false),
        (.decision, "Lumen: только тёмные темы — «Люмен» и «Монохром»", false),
        (.project, "Island: тень должна следовать за островом", false),
        (.project, "FlowLocal v3.0: нейтральные цвета, яркий зелёный", false),
        (.people, "Папа — хозяин kandeev.com; на сайте без цен и кейсов с цифрами", false),
        (.people, "Лёша помогает с дизайном Пульта", false),
        (.project, "Пульт v1.0 выпущен, тёмный монохром", false),
    ]
    for (k, t, pin) in facts {
        var f = MemoryFact(kind: k, text: t, source: "Lumen: замысел")
        f.pinned = pin
        _ = try app.store.save(f)
    }
    app.reloadMemories()
    app.page = .memory
    app.memoryMode = .graph
    try await Snap.save(RootView(app: app), "40-graph")
}

/// Навыки: список, редактор, предложенный навык под ответом агента; бот с навыками и выводами
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotSkills() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let lib = app.skillLibrary
    try lib.save(name: "release-notes", description: "Готовит заметки к релизу из git log: разделы «Новое» и «Исправлено». Используй, когда просят changelog, «что нового» или заметки к версии.",
                 body: "## Шаги\n1. Возьми git log с прошлого тега.\n2. Раздели на «Новое» и «Исправлено».\n\n## Формат\n…", origin: .created)
    try lib.save(name: "shelf-build", description: "Сборка Shelf после смены ветки: сначала swift package resolve, потом ./build.sh.", body: "1. swift package resolve\n2. ./build.sh", origin: .learned)
    try lib.save(name: "pdf", description: "Работа с PDF: прочитать, заполнить формы, собрать. Используй, когда в задаче есть PDF.", body: "…", origin: .catalog)
    for _ in 0..<7 { try app.store.logSkillUse("release-notes", conversationID: nil) }
    try app.store.logSkillUse("shelf-build", conversationID: nil)
    app.reloadSkills()
    app.page = .skills
    try await Snap.save(RootView(app: app), "50-skills")

    app.page = .skillEditor("release-notes")
    try await Snap.save(RootView(app: app), "51-skill-editor", size: CGSize(width: 1180, height: 1100))

    // «Сам научился» под ответом агента
    let c = Conversation(title: "Собрать Shelf", kind: .agent, folder: NSHomeDirectory() + "/Documents/prog/Мак-приложения/shelf",
                         backend: .subscription, model: .opus, effort: .high)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Собери Shelf и прогони тесты"))
    var m = ChatMessage(conversationID: c.id, role: .assistant, text: "Собрал: сначала упало, после `swift package resolve` всё прошло, 24 теста зелёные.",
                        steps: ["Запускает: ./build.sh", "Запускает: swift package resolve", "Запускает: ./build.sh", "Запускает: swift test"].map { AgentStep(kind: .run, text: $0) })
    m.skillDraft = SkillDraft(name: "swift-build-after-branch", description: "Сборка Swift-проекта после смены ветки: если ./build.sh падает на зависимостях, сначала swift package resolve. Используй, когда сборка падает после git checkout.",
                              body: "1. …")
    try app.store.save(m)
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "52-skill-proposal")

    var b = Bot(id: "tester", name: "Тестировщик", icon: "flask-conical", hue: 160, role: "Проверяет приложения и правки — и только",
                capabilities: [.read, .run, .bots], commands: ["./build.sh", "swift test"])
    b.skills = ["shelf-build"]
    b.learned = ["Shelf после смены ветки собирать только после swift package resolve", "У Island проверять тень при раскрытии первым делом"]
    app.saveBot(b)
    app.saveBot(Bot(id: "coder", name: "Кодер prog", icon: "code-xml", hue: 235, role: "Пишет и чинит код", capabilities: [.read, .write, .run, .git]))
    app.openBot("tester")
    app.update { $0.contextOpen = true }
    try await Snap.save(RootView(app: app), "53-bot-passport-learned")
    app.update { $0.contextOpen = false }
    app.page = .botEditor("tester")
    try await Snap.save(RootView(app: app), "54-bot-editor-skills", size: CGSize(width: 1180, height: 2300))
    app.page = .botEditor(nil)
    try await Snap.save(RootView(app: app), "55-bot-new-describe")
}

/// Режимы: выбор в поле агента, «Можно?», план готов; широкая левая панель
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotModes() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.agentMode = .manual }
    app.tab = .agent
    app.newAgentTask()
    try await Snap.save(RootView(app: app), "60-agent-mode")

    var c = Conversation(title: "Почистить логи", kind: .agent, folder: NSHomeDirectory(), backend: .subscription, model: .sonnet, effort: .high)
    c.mode = .manual
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Удали старые логи сборки"))
    app.reloadConversations()
    app.openChat(c)
    app.chat.pendingPermission = .init(conversationID: c.id, request: .init(id: "r1", tool: "Bash",
        inputJSON: #"{"command":"rm -rf build/logs/2026-09-*","description":"Удаляет логи за сентябрь"}"#, description: ""))
    try await Snap.save(RootView(app: app), "61-permission")

    let plan = "## План\n1. Найти логи старше 30 дней в build/logs.\n2. Показать список и размер.\n3. Удалить их одной командой.\n4. Проверить, что сборка не сломалась."
    let planJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["plan": plan]), as: UTF8.self)
    app.chat.pendingPermission = .init(conversationID: c.id, request: .init(id: "r2", tool: "ExitPlanMode", inputJSON: planJSON, description: ""))
    try await Snap.save(RootView(app: app), "62-plan-ready")

    app.chat.pendingPermission = nil
    app.sidebarWidth = 900 // шире половины — упрётся в половину окна
    try await Snap.save(RootView(app: app), "63-wide-sidebar")
}

/// Вложения: в поле ввода и в переписке; настройки режимов
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotAttachments() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let src = app.paths.root.appendingPathComponent("src")
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try makeImage(1200, 800, color: .systemOrange, to: src.appendingPathComponent("макет.png"))
    try makeImage(800, 800, color: .systemTeal, to: src.appendingPathComponent("иконка.png"))
    try "# Заметки\nПервый релиз Lumen".write(to: src.appendingPathComponent("заметки.md"), atomically: true, encoding: .utf8)
    try Data(repeating: 1, count: 240_000).write(to: src.appendingPathComponent("отчёт.pdf"))
    let img = try #require(app.importAttachment(src.appendingPathComponent("макет.png")))
    let img2 = try #require(app.importAttachment(src.appendingPathComponent("иконка.png")))
    let md = try #require(app.importAttachment(src.appendingPathComponent("заметки.md")))
    let pdf = try #require(app.importAttachment(src.appendingPathComponent("отчёт.pdf")))

    let c = Conversation(title: "Разбор макета", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    var u = ChatMessage(conversationID: c.id, role: .user, text: "Посмотри макет и заметки — что поправить перед релизом?")
    u.attachments = [img, md, pdf]
    _ = try app.store.save(u)
    _ = try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Макет аккуратный. Поправил бы три вещи: отступ у шапки, контраст подписи и порядок кнопок."))
    var u2 = ChatMessage(conversationID: c.id, role: .user, text: "А так?")
    u2.attachments = [img, img2]
    _ = try app.store.save(u2)
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "70-message-attachments")

    try await Snap.save(VStack { Spacer(); Composer(app: app, draft: .constant("Что не так с этим экраном?"), attachments: .constant([img, md, pdf]), backend: .subscription) }
        .environment(\.palette, Palette.of(.lumen)).background(Palette.of(.lumen).background), "71-composer-attachments",
        size: CGSize(width: 900, height: 320))

    app.update { $0.hiddenModes = [.bypassPermissions] }
    app.page = .settings(.general)
    try await Snap.save(RootView(app: app), "72-settings-modes", size: CGSize(width: 1180, height: 1300))
}

/// 1.4: настройки группами, тема со светом, о программе, удаление, проект как в Claude, код, «/»
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotLook14() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    for s in [SettingsView.Section.theme, .general, .fonts, .about, .uninstall, .data, .persona] {
        app.page = .settings(s)
        try await Snap.save(RootView(app: app), "80-settings-\(s)")
    }
    // 25.10: настройки — панелью поверх окна, как в Claude
    app.page = .chat
    app.settingsOpen = true
    for s in [SettingsView.Section.theme, .fonts, .window] {
        app.settingsSection = s
        try await Snap.save(RootView(app: app), "84-settings-sheet-\(s)")
    }
    app.settingsOpen = false
    // кнопка «панель» не ездит: открыта панель или спрятана — она на том же месте
    app.update { $0.sidebarHidden = true }
    try await Snap.save(RootView(app: app), "85-sidebar-hidden")
    app.update { $0.sidebarHidden = false }
    try await Snap.save(RootView(app: app), "85-sidebar-shown")
    app.update { $0.appearance = .light }
    app.page = .settings(.theme)
    try await Snap.save(RootView(app: app), "81-settings-theme-light")
    app.update { $0.appearance = .dark }
    let pr = app.createProject(folder: nil)
    app.updateProject(pr) { $0.name = "Swift"; $0.instructions = "Я хочу устроиться летом на стажировку разработчиком." }
    _ = try app.store.save(ProjectFile(projectID: pr.id, name: "about.md", text: String(repeating: "текст ", count: 400)))
    _ = try app.store.save(ProjectFile(projectID: pr.id, name: "Как проходит интервью.txt", text: String(repeating: "x", count: 6900)))
    app.page = .project(pr.id)
    try await Snap.save(RootView(app: app), "82-project")
    let code = ChatMessage(conversationID: "x", role: .assistant, text: "Вот скрипт:\n\n```python\nimport random\n\nsecret = random.randint(1, 100)\n# угадай\nwhile True:\n    guess = int(input(\"Число: \"))\n    if guess == secret:\n        print(f\"Угадал за {secret}!\")\n        break\n```\n\nЗапусти его.")
    try await Snap.save(RichText(text: code.text).padding(20).environment(\.palette, Palette.lumen).background(Palette.lumen.background), "83-code", size: CGSize(width: 700, height: 420))
}

/// Таблица из ответа (19.10): длинные ячейки переносятся, строки не наезжают друг на друга
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotTable() async throws {
    Snap.registerFonts()
    let text = """
    Сценарии, обновлённые под «Конструктор»:

    | Сценарий | Было | Шаги | Зачем |
    |---|---|---|---|
    | **1. Новый способ** | A + B | Инструкция за 10 с → примеры → вставь → переделай → собери из плиток → напиши сам → скажи сам | Открыть грамматику и сразу собрать из неё своё |
    | **2. Слова сферы** | Д | Новые слова → пары → по звуку → напиши слово → вставь в предложение известным способом → скажи | Ось «Слова» |
    | **3. Слушаем** | Б | Сцена из сферы на слух → верно или нет → числа или похожие слова → диктант → ответь | Понимать живую речь |
    | **4. Диалог по шагам** | Г | Реплика собеседника → выбери ответ → собери ответ → допиши → ответь голосом | Подготовка к «Разговору», только своя роль |
    | **5. Ошибки** | новое | Русская ловушка → найди ошибку → выбери верное → исправь → скажи верно | Типичные ошибки русскоязычных |

    Блок из восьми уроков строится так.
    """
    for (name, pal, width) in [("dark", Palette.lumen, 1100.0), ("light", Palette.light, 1100.0), ("narrow", Palette.lumen, 560.0)] {
        let v = RichText(text: text).padding(24).frame(width: width, alignment: .leading)
            .environment(\.palette, pal).background(pal.background)
        try await Snap.save(v, "85-table-\(name)", size: CGSize(width: width, height: 620))
    }
}

/// Время хода на виду (19.10): с начала хода, не с начала шага; есть и пока пишется текст
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotTurnClock() async throws {
    Snap.registerFonts()
    let start = Date().addingTimeInterval(-(2 * 3600 + 14 * 60 + 5))
    let steps = [AgentStep(kind: .run, text: "Запускает swift test")]
    let v = VStack(alignment: .leading, spacing: 22) {
        LiveStepLine(text: "Запускает swift test", since: start)
        StepsView(steps: steps, live: (start, nil))
        TurnClockLine(text: "Пишет ответ", since: Date().addingTimeInterval(-134))
    }
    .padding(24).frame(width: 640, alignment: .leading)
    try await Snap.save(v.environment(\.palette, Palette.light).background(Palette.light.background), "86-turn-clock", size: CGSize(width: 640, height: 220))
}

/// Фоновые задачи агента (19.10): субагент работает, исследование готово, команда в фоне с выводом
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotBackgroundTasks() async throws {
    Snap.registerFonts()
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-bg-snap.output")
    try "Compiling LumenUI ChatView.swift\nCompiling LumenUI AgentViews.swift\nBuild complete! (12,4 с)\nTest run with 233 tests passed".write(to: out, atomically: true, encoding: .utf8)
    var shell = BackgroundJob(id: "b1", toolUseID: nil, kind: .shell, title: "swift test", background: true, started: Date().addingTimeInterval(-74))
    shell.outputFile = out.path
    var agent = BackgroundJob(id: "a1", toolUseID: nil, kind: .agent, title: "Переписать экран настроек", background: true, started: Date().addingTimeInterval(-212))
    agent.activity = "Правит SettingsView.swift"
    var research = BackgroundJob(id: "r1", toolUseID: nil, kind: .research, title: "Как устроен автокомпакт в Codex", background: false, started: Date().addingTimeInterval(-300))
    research.status = .completed
    research.ended = Date().addingTimeInterval(-180)
    research.summary = "В Codex сжатие — отдельный запрос модели с просьбой пересказать разговор; пересказ заменяет историю."
    let v = BackgroundTasksBar(tasks: [research, agent, shell], initiallyOpen: true).padding(24).frame(width: 720, alignment: .leading)
    for (name, pal) in [("dark", Palette.lumen), ("light", Palette.light)] {
        try await Snap.save(v.environment(\.palette, pal).background(pal.background), "87-background-\(name)", size: CGSize(width: 720, height: 460))
    }
}

/// История шагов: идущий шаг в заголовке, раскрытая лента
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotStepsHistory() async throws {
    Snap.registerFonts()
    let steps = [AgentStep(kind: .search, text: "Ищет файлы **/*скриншот*/**"), AgentStep(kind: .read, text: "Читает 01 Начало истории — открыт.png"),
                 AgentStep(kind: .read, text: "Читает 02 Новые слова — открыт.png"), AgentStep(kind: .run, text: "Запускает swift test"),
                 AgentStep(kind: .edit, text: "Правит ChatView.swift"), AgentStep(kind: .read, text: "Читает 07 Проверь себя — открыт.png")]
    let v = VStack(alignment: .leading, spacing: 24) {
        StepsView(steps: steps, live: (Date().addingTimeInterval(-12), nil), initiallyOpen: true)
        StepsView(steps: steps, initiallyOpen: true)
    }
    .padding(24).frame(width: 640, alignment: .leading)
    for (name, pal) in [("dark", Palette.lumen), ("light", Palette.light)] {
        try await Snap.save(v.environment(\.palette, pal).background(pal.background), "84-steps-\(name)", size: CGSize(width: 640, height: 640))
    }
}

/// Живая картинка из блока ```visual: настоящий WebKit, график Chart.js с CDN и SVG — снимок как в переписке
@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotVisualBlock() async throws {
    let code = """
        <div class="grid">
          <div class="card"><div class="muted">Выручка</div><div style="font-size:26px;font-weight:600">1,2 млн</div></div>
          <div class="card"><div class="muted">Рост</div><div style="font-size:26px;font-weight:600;color:var(--accent)">+18%</div></div>
        </div>
        <div class="card" style="margin-top:12px"><canvas id="c" height="160"></canvas></div>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
        <script>
        const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
        new Chart(document.getElementById('c'), {type:'bar', data:{labels:['Янв','Фев','Мар','Апр','Май'],
          datasets:[{label:'Продажи', data:[12,19,9,22,28], backgroundColor: css('--accent')}]},
          options:{plugins:{legend:{labels:{color:css('--fg')}}}, scales:{x:{ticks:{color:css('--muted')},grid:{color:css('--border')}},
          y:{ticks:{color:css('--muted')},grid:{color:css('--border')}}}}});
        </script>
        """
    for (name, pal) in [("dark", Palette.lumen), ("light", Palette.light)] {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 620, height: 380))
        web.setValue(false, forKey: "drawsBackground")
        // в окне, как в Lumen: без окна WebKit не крутит анимации, и график остаётся пустым
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.orderFrontRegardless()
        defer { window.close() }
        web.loadHTMLString(VisualBlock.page(code, palette: pal, standalone: true), baseURL: URL(string: "https://lumen.visual/"))
        try await Task.sleep(for: .seconds(4))
        let img = try await web.takeSnapshot(configuration: nil)
        let rep = try #require(img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: snapDir!).appendingPathComponent("85-visual-\(name).png"))
    }
}

/// Ответ настоящей модели с блоком ```visual (файл из LUMEN_VISUAL_FROM) — как он нарисуется
@MainActor @Test(.enabled(if: snapDir != nil && ProcessInfo.processInfo.environment["LUMEN_VISUAL_FROM"] != nil)) func snapshotModelVisual() async throws {
    let text = try String(contentsOfFile: ProcessInfo.processInfo.environment["LUMEN_VISUAL_FROM"]!, encoding: .utf8)
    guard case .visual(let code, _)? = RichText.parts(text).first(where: { if case .visual = $0 { true } else { false } }) else { return }
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 660, height: 520))
    let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderFrontRegardless()
    defer { window.close() }
    web.loadHTMLString(VisualBlock.page(code, palette: .light, standalone: true), baseURL: URL(string: "https://lumen.visual/"))
    try await Task.sleep(for: .seconds(4))
    let img = try await web.takeSnapshot(configuration: nil)
    let rep = try #require(img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: snapDir!).appendingPathComponent("86-model-visual.png"))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotThemes() async throws {
    // стартовый экран во всех встроенных темах, тёмных и светлых — как они выглядят рядом
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    app.newChat()
    for f in Palette.Family.builtIn {
        for dark in [true, false] {
            app.update { $0.themeID = f.id; $0.appearance = dark ? .dark : .light; $0.separateModes = false }
            try await Snap.save(RootView(app: app), "theme-\(f.id)-\(dark ? "dark" : "light")", size: CGSize(width: 1000, height: 640))
        }
    }
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotPetInChat() async throws {
    // питомец «всегда в переписке»: сидит слева от последнего ответа вместо знака-затмения
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.pet.enabled = true; $0.pet.floating = false; $0.pet.alwaysInChat = true; $0.pet.inChat = true }
    let c = Conversation(title: "Питомец", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Привет"))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Привет, Роман! Что делаем сегодня?"))
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "pet-in-chat", size: CGSize(width: 1000, height: 560))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotMarkdown() async throws {
    Snap.registerFonts()
    let text = """
    # Большой заголовок

    Обычный абзац с **жирным**, *курсивом*, `кодом` и ссылкой https://kandeev.com — всё в одном выделяемом тексте.

    ---

    ## Что сделано
    - Первый пункт списка
    - Второй пункт, длинный: он переносится на вторую строку и держится под текстом, а не под маркером, чтобы читалось ровно
      - Вложенный пункт
      - Ещё один вложенный
    - Третий

    ### По порядку
    1. Собрать приложение
    2. Прогнать тесты
    3. Перезапустить

    > Цитата: одна строка с чертой слева, цвет приглушённый.

    ```swift
    let x = 1
    ```

    Последний абзац после кода и конец.
    """
    try await Snap.save(RichText(text: text).padding(24).frame(width: 640, alignment: .leading).environment(\.palette, Palette.lumen).background(Palette.lumen.background),
                        "markdown", size: CGSize(width: 700, height: 820))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotRememberedGroup() async throws {
    // загрузили о себе много — тридцать фактов: одна плашка вместо ленты карточек, свёрнутая и раскрытая
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    var ids: [Int64] = []
    for i in 1...30 {
        let f = try app.store.save(MemoryFact(kind: .you, text: "Факт номер \(i): Роман делает приложения на Swift и любит, когда всё работает ровно", source: "Знакомство"))
        if let id = f.id { ids.append(id) }
    }
    app.reloadMemories()
    try await Snap.save(VStack(alignment: .leading, spacing: 16) {
        RememberedGroup(app: app, ids: ids)
        RememberedGroup(app: app, ids: ids, initiallyOpen: true)
    }.padding(24).frame(width: 640, alignment: .leading).environment(\.palette, Palette.lumen).background(Palette.lumen.background),
                        "remembered-group", size: CGSize(width: 700, height: 560))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotGraphClusters() async throws {
    // граф памяти: ты в центре (маленькое затмение), узлы-темы, люди и проекты со своими созвездиями фактов
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    var facts: [MemoryFact] = []
    var id: Int64 = 1
    func add(_ kind: MemoryKind, _ text: String) { facts.append(MemoryFact(id: id, kind: kind, text: text, source: "Знакомство")); id += 1 }
    for i in 1...18 { add(.you, "Роман: факт о себе номер \(i)") }
    for i in 1...10 { add(.pref, "Привычка или предпочтение \(i)") }
    for i in 1...9 { add(.decision, "Решение \(i), принятое по ходу работы") }
    for i in 1...8 { add(.project, "Заметка \(i) про lumen и shelf") }
    for name in ["Вика", "Отец", "Младшая", "Кот Бакс", "Помогал"] { add(.people, "\(name) — близкий человек"); add(.people, "\(name) любит разговоры по вечерам") }
    for i in 1...6 { add(.project, "Идея \(i) про prog") }
    let g = MemoryGraph(facts: facts, me: "Роман", projects: ["lumen", "shelf", "prog", "Изучение английского"])
    let model = GraphModel(graph: g)
    model.lessMotion = true
    model.run()
    model.selected = nil
    try await Snap.save(GraphView(app: app, model: model).environment(\.palette, Palette.lumen), "graph", size: CGSize(width: 1100, height: 760))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotComposerPills() async throws {
    // таблетки у «+»: поиск в сети и память включены по умолчанию, ресерч — нет; у агента — тот же ряд
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    app.newChat()
    try await Snap.save(RootView(app: app), "composer-pills-chat", size: CGSize(width: 1100, height: 640))
    app.switchTab(.agent)
    app.newAgentTask()
    try await Snap.save(RootView(app: app), "composer-pills-agent", size: CGSize(width: 1100, height: 700))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotFilePane() async throws {
    // панель сбоку с файлами: Markdown, картинка и PDF — своё превью, без адресной строки; сверху «В чат», копировать, скачать
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-file-pane-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let md = dir.appendingPathComponent("план-игры.md")
    try "# План игры\n\nКоротко: **одна механика**, мгновенный отклик.\n\n- Идея\n- Прототип\n- Звук и «сок»\n\n> Играть должно быть приятно с первой секунды.\n".write(to: md, atomically: true, encoding: .utf8)
    let png = dir.appendingPathComponent("эскиз.png")
    let img = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { r in
        NSGradient(colors: [NSColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1), NSColor(red: 0.6, green: 0.2, blue: 0.7, alpha: 1)])?.draw(in: r, angle: 35)
        return true
    }
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) { try data.write(to: png) }
    app.openFile(md)
    app.openFile(png)
    app.browser.select(app.browser.tabs.first { $0.file?.url == md }!.id)
    try await Snap.save(BrowserPane(app: app, browser: app.browser).environment(\.palette, Palette.lumen).background(Palette.lumen.background),
                        "file-pane-md", size: CGSize(width: 520, height: 640))
    app.browser.select(app.browser.tabs.first { $0.file?.url == png }!.id)
    try await Snap.save(BrowserPane(app: app, browser: app.browser).environment(\.palette, Palette.lumen).background(Palette.lumen.background),
                        "file-pane-image", size: CGSize(width: 520, height: 640))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotSourceChips() async throws {
    // источники ответа (вариант A): чипы под текстом, номера у ссылок
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    let c = Conversation(title: "Игры", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "посмотри в интернете, как делают топовые браузерные игры"))
    var a = ChatMessage(conversationID: c.id, role: .assistant, text: """
        Победители джемов держатся на трёх вещах: понятно за десять секунд, мгновенный отклик, короткая сессия ([Vibe Jam](https://vibej.am/2026), \
        [Game Developer](https://www.gamedeveloper.com/design/loop)).

        ## Что повторяется у лучших
        - Одна механика, доведённая до блеска — разбор на [itch.io](https://itch.io/games)
        - Звук и «сок» делают половину впечатления: https://www.youtube.com/watch?v=juice
        - Запуск без регистрации, меньше 5 МБ ([MDN](https://developer.mozilla.org/docs/Games))
        """)
    var s = AgentStep(kind: .web, text: "Ищет в интернете «Vibe Jam 2026 winners»")
    s.detail = "Vibe Jam 2026 winners"
    a.steps = [s]
    try app.store.save(a)
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "source-chips", size: CGSize(width: 1100, height: 700))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotFileCardsInComposer() async throws {
    // файл из панели сбоку — карточкой в тексте поля; после неё правка, потом следующий файл и его правка; и как это уходит в переписку
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-cards-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let md = dir.appendingPathComponent("план-игры.md")
    try "# План\n".write(to: md, atomically: true, encoding: .utf8)
    let txt = dir.appendingPathComponent("заметки.txt")
    try "Заметки\n".write(to: txt, atomically: true, encoding: .utf8)
    let a = try #require(app.importAttachment(md)), b = try #require(app.importAttachment(txt))
    let draft = FileMarks.marker(a.id) + "Сделай заголовок короче\n" + FileMarks.marker(b.id) + "А здесь убери повторы"
    let sent = FileMarks.readable(draft, names: [a.id: a.name, b.id: b.name])
    var message = ChatMessage(conversationID: "snap", role: .user, text: sent)
    message.attachments = [a, b]
    try await Snap.save(MessageRow(message: message, chat: nil).environment(\.palette, Palette.lumen).padding(24).frame(width: 640).background(Palette.lumen.background),
                        "file-cards-sent", size: CGSize(width: 640, height: 360))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotBrowserActivityPill() async throws {
    // «Lumen · Смотрит» — таблеткой внизу панели, а не полосой под вкладками
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    app.browser.activity = "Lumen · Смотрит"
    try await Snap.save(BrowserPane(app: app, browser: app.browser).environment(\.palette, Palette.lumen).background(Palette.lumen.background),
                        "browser-activity-pill", size: CGSize(width: 640, height: 520))
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotStepShots() async throws {
    // как в Claude Code: снимки шагов — превью справа на строке («+N» после трёх), а то, что агент показал сам, — одним крупным кадром под ответом
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    func shot(_ name: String, _ hue: CGFloat) throws -> LumenCore.Attachment {
        let img = NSImage(size: NSSize(width: 960, height: 600), flipped: false) { r in
            NSGradient(colors: [NSColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1), NSColor(hue: hue + 0.12, saturation: 0.7, brightness: 0.5, alpha: 1)])?.draw(in: r, angle: 35)
            return true
        }
        return try #require(app.importImage(img, name: name))
    }
    var shots = [try shot("Снимок 1.png", 0.55), try shot("Снимок 2.png", 0.05), try shot("Снимок 3.png", 0.3), try shot("Снимок 4.png", 0.8)]
    for i in shots.indices { shots[i].snapshot = true }
    let shown = try shot("Вёрстка.png", 0.12)
    var steps = [AgentStep(kind: .web, text: "Открывает вкладку", at: 0)]
    for s in shots {
        var step = AgentStep(kind: .read, text: "Смотрит на страницу", at: 0)
        step.shot = s.id
        steps.append(step)
    }
    var message = ChatMessage(conversationID: "snap", role: .assistant, text: "Готово: вот страница после правки.")
    message.steps = steps
    message.attachments = shots + [shown]
    try await Snap.save(MessageRow(message: message, chat: nil).environment(\.palette, Palette.lumen).padding(24).frame(width: 760).background(Palette.lumen.background),
                        "step-shots", size: CGSize(width: 760, height: 560))
}
