import LumenCore
import SwiftUI

/// Окно Lumen: боковая панель и содержимое. Знакомство — поверх, при первом запуске.
public struct RootView: View {
    @Bindable var app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        let p = Palette.of(app.prefs.theme, custom: app.prefs.customTheme)
        GeometryReader { g in
        HStack(spacing: 0) {
            if !app.prefs.sidebarHidden { Sidebar(app: app).transition(.move(edge: .leading)) }
            Group {
                switch app.page {
                case .chat:
                    HStack(spacing: 0) {
                        ChatView(app: app)
                        if let s = app.split {
                            ChatView(app: app, controller: s)
                                .overlay(alignment: .leading) { p.border.frame(width: 1) }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: app.split == nil)
                case .memory: MemoryView(app: app)
                case .project(let id): ProjectView(app: app, projectID: id)
                case .settings: SettingsView(app: app)
                case .bots: BotsView(app: app)
                case .bot, .group: ChatView(app: app)
                case .groupEditor(let id): GroupEditor(app: app, groupID: id).id(id ?? "new")
                case .botEditor(let id): BotEditor(app: app, botID: id).id(id ?? "new")
                case .skills: SkillsView(app: app)
                case .artifacts: ArtifactsView(app: app)
                case .skillEditor(let name): SkillEditor(app: app, name: name).id(name ?? "new")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if app.browserOpen { BrowserPane(app: app, browser: app.browser).transition(.move(edge: .trailing)) }
        }
        .environment(\.windowWidth, g.size.width)
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.2), value: app.prefs.sidebarHidden)
        .animation(.easeOut(duration: 0.2), value: app.browserOpen)
        // агент открыл страницу или показал макет — браузер выезжает сам
        .onChange(of: app.browser.wantsOpen) { if !app.browserOpen { app.browserOpen = true } }
        .task { app.startBrowser() }
        // панель спрятана — её кнопки остаются рядом с кнопками окна, как в Claude
        .overlay(alignment: .topLeading) {
            if app.prefs.sidebarHidden { WindowControls(app: app).padding(.leading, 76).ignoresSafeArea() }
        }
        .overlay { MenuLayer(app: app) }
        .overlay { if app.searchOpen { SearchLayer(app: app) } }
        .background {
            // ⌘K — поиск, ⌘N — новый чат, ⌘\ — панель
            Group {
                Button("") { app.searchOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
                Button("") { app.newChat() }.keyboardShortcut("n", modifiers: .command)
                Button("") { app.update { $0.sidebarHidden.toggle() } }.keyboardShortcut("\\", modifiers: .command)
                Button("") { app.toggleBrowser() }.keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .opacity(0)
        }
        // `.lumen-light` на всём окне: панель полупрозрачная, свет проходит сквозь неё
        .background(LumenLight(level: app.orb == .thinking ? 1.9 : 1).ignoresSafeArea())
        .overlay {
            if !app.prefs.onboarded {
                OnboardingView(app: app).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.prefs.onboarded)
        .background(p.background.ignoresSafeArea())
        // чат по подписке должен знать, где claude и есть ли вход
        .task { if app.claude == .checking { await app.refreshClaude() } }
        .task { if app.codex == .checking { await app.refreshCodex() } }
        .task { await app.selfShotIfAsked() }
        .task {
            // после проверки claude — назвать старые разговоры по-человечески (один раз)
            while app.claude == .checking { try? await Task.sleep(for: .milliseconds(300)) }
            if ProcessInfo.processInfo.environment["LUMEN_SELFSHOT"] == nil { await app.nameOldConversations() }
        }
        .environment(\.palette, p)
        .environment(\.lessMotion, app.prefs.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .preferredColorScheme(p.scheme)
        .tint(p.glow)
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// Боковая панель (`Shell` в App.tsx): знак, список, внизу разделы и профиль.
/// Вкладки, поиск и разделы, которые ещё не работают, не показываем.
struct Sidebar: View {
    @Bindable var app: AppModel
    @Environment(\.windowWidth) private var windowWidth

    /// Навыки + коннекторы + хуки
    private var customizeCount: Int { app.skills.count + app.connectors.mcpServers.count + app.hooks.count }

    private var skillsActive: Bool {
        switch app.page {
        case .skills, .skillEditor: true
        default: false
        }
    }


    @State private var importing = false
    @Environment(\.palette) private var p

    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // как в Claude: в одной строке с кнопками окна — «спрятать панель» и поиск
            WindowControls(app: app)
                .padding(.leading, 76)
                .frame(maxWidth: .infinity, alignment: .leading)

            TabSwitch(app: app).padding(.horizontal, 12).padding(.top, 12)

            if app.tab == .bots {
                ScrollView {
                    BotsSidebar(app: app).padding(.horizontal, 12).padding(.vertical, 12)
                }
                .scrollIndicators(.never)
            } else {
                // как в Claude: сверху — действия строками с иконками
                VStack(spacing: 2) {
                    NavRow(title: app.tab == .agent ? "Новая задача" : "Новый чат", icon: "square-pen", active: false) {
                        app.tab == .agent ? app.newAgentTask() : app.newChat()
                    }
                    NavRow(title: "Поиск", icon: "search", active: app.searchOpen, trailing: "⌘K") { app.searchOpen = true }
                    if app.tab == .agent {
                        NavRow(title: "Импорт из Claude Code", icon: "download", active: false) { importing = true }
                    }
                    NavRow(title: "Кастомизация", icon: "wrench", active: skillsActive,
                           trailing: customizeCount == 0 ? nil : "\(customizeCount)") { app.page = .skills }
                    NavRow(title: "Память", icon: "brain", active: app.page == .memory, trailing: "\(app.memoryCount)") { app.page = .memory }
                    NavRow(title: "Артефакты", icon: "layout-grid", active: app.page == .artifacts) { app.page = .artifacts }
                }
                .padding(.horizontal, 12).padding(.top, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let kind: ConversationKind = app.tab == .agent ? .agent : .chat
                        let mine = app.conversations.filter { $0.kind == kind }
                        let pinned = mine.filter(\.pinned)
                        if !pinned.isEmpty || app.draggingChat != nil {
                            section("pinned", "Закреплённые", pinned, drop: .pin)
                        }
                        // проекты — с папками, внутри их разговоры
                        if !app.projects.isEmpty {
                            SidebarSectionHeader(app: app, title: "Проекты", collapsed: nil, project: nil, toggle: {},
                                                 plus: { app.createProject(folder: app.tab == .agent ? app.agentFolder : nil) })
                        }
                        ForEach(app.projects) { pr in
                            let items = mine.filter { $0.projectID == pr.id && !$0.pinned }
                            section("p:" + pr.id, pr.name, items, project: pr)
                        }
                        if !app.projects.isEmpty { Color.clear.frame(height: 8) }
                        let recent = mine.filter { $0.projectID == nil && !$0.pinned }
                        section("recent", app.tab == .agent ? "Сессии" : "Недавние", recent, plus: { app.tab == .agent ? app.newAgentTask() : app.newChat() }, drop: .loose)
                        if app.projects.isEmpty {
                            Button { app.createProject(folder: app.tab == .agent ? app.agentFolder : nil) } label: {
                                HStack(spacing: 6) {
                                    Icon("folder-plus", 14)
                                    Text("Новый проект").tw(12, lh: 16)
                                }
                                .foregroundStyle(p.mutedFg)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }

            Button { app.page = .settings(.look) } label: { profile }
                .buttonStyle(.plain)
                .help("Настройки")
                .padding(12)
                .overlay(alignment: .top) { p.border.frame(height: 1) }
        }
        .foregroundStyle(p.foreground)
        .frame(width: CGFloat(ResizeHandle.clamp(app.sidebarWidth, min: 220, window: Double(windowWidth))))
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            ResizeHandle(side: .trailing, width: $app.sidebarWidth, minWidth: 220) { app.update { $0.sidebarWidth = app.sidebarWidth } }
                .offset(x: 4).ignoresSafeArea()
        }
        // bg-sidebar/70 + backdrop-blur-sm
        .background(p.sidebar.opacity(0.7).ignoresSafeArea())
        .overlay(alignment: .trailing) { p.border.frame(width: 1).ignoresSafeArea() }
        .sheet(isPresented: $importing) { ImportClaudeSheet(app: app) { importing = false }.environment(\.palette, p) }
        .onChange(of: app.chat.conversation?.projectID) { _, id in if let id { collapsed.remove("p:" + id) } }
    }

    /// Раздел как в Claude: серое название (у проекта — сворачивается), «+» справа, ниже строки разговоров
    /// Что делает бросок разговора на раздел
    enum SectionDrop { case pin, loose }

    @ViewBuilder
    private func section(_ key: String, _ title: String, _ items: [Conversation], project: Project? = nil,
                         plus: (() -> Void)? = nil, drop: SectionDrop? = nil) -> some View {
        let isCollapsed = collapsed.contains(key)
        if let project {
            // проект — строкой с папкой, как раньше; внутри — его разговоры; брось разговор — переложится сюда
            ProjectRow(app: app, project: project, open: !isCollapsed, count: items.count) {
                if isCollapsed { collapsed.remove(key) } else { collapsed.insert(key) }
            }
            .dropTarget(app) { c in
                if c.pinned { app.togglePin(c) }
                app.move(c, to: project.id)
                collapsed.remove(key)
            }
        } else {
            SidebarSectionHeader(app: app, title: app.draggingChat != nil && drop == .pin && items.isEmpty ? "Закреплённые — отпусти, чтобы закрепить" : title,
                                 collapsed: nil, project: nil, toggle: {}, plus: plus)
                .dropTarget(app, enabled: drop != nil) { c in
                    switch drop {
                    case .pin: if !c.pinned { app.togglePin(c) }
                    case .loose:
                        if c.pinned { app.togglePin(c) }
                        if c.projectID != nil { app.move(c, to: nil) }
                    case nil: break
                    }
                }
        }
        if !isCollapsed {
            ForEach(items) { c in ChatRow(app: app, c: c).padding(.leading, project == nil ? 0 : 14) }
            if items.isEmpty && project != nil {
                Text("Пусто").tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.7)).padding(.leading, 38).padding(.vertical, 4)
            }
        }
        Color.clear.frame(height: project == nil ? 14 : 6)
    }

    private var sessions: [Conversation] {
        let s = app.conversations.filter { $0.kind == .agent && $0.projectID == nil }
        return s.filter(\.pinned) + s.filter { !$0.pinned }
    }

    /// «Закреплённые», «Сегодня» и «Раньше»
    private var groups: [(String, [Conversation])] {
        // разговоры проектов — внутри своих проектов
        let chats = app.conversations.filter { $0.kind == .chat && $0.projectID == nil }
        let pinned = chats.filter(\.pinned)
        let rest = chats.filter { !$0.pinned }
        let today = rest.filter { Calendar.current.isDateInToday($0.updatedAt) }
        let earlier = rest.filter { !Calendar.current.isDateInToday($0.updatedAt) }
        return [("Закреплённые", pinned), ("Сегодня", today), ("Раньше", earlier)].filter { !$0.1.isEmpty }
    }

    private var profile: some View {
        ProfileCard(name: app.profile.name, plan: plan)
    }

    private var plan: String {
        switch app.prefs.backend {
        case .api: return "Anthropic API · ключ"
        case .subscription:
            if case .signedIn(_, let a) = app.claude { return "Claude \(a.planName ?? "") · подписка" }
            return "Claude Code · подписка"
        }
    }
}

/// Заголовок раздела в панели, как в Claude: «LUMEN ›  +». У проекта: щелчок — свернуть, «…» — меню (открыть, переименовать…)
struct SidebarSectionHeader: View {
    @Bindable var app: AppModel
    let title: String
    /// nil — раздел не сворачивается
    let collapsed: Bool?
    let project: Project?
    let toggle: () -> Void
    let plus: (() -> Void)?

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var dotsHover = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Text(title).tw(12, lh: 16).lineLimit(1)
                    if collapsed == true || (collapsed == false && hover) {
                        Icon(collapsed == true ? "chevron-right" : "chevron-down", 12)
                    }
                }
                .foregroundStyle(hover ? p.foreground.opacity(0.8) : p.mutedFg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(collapsed != nil)
            .simultaneousGesture(TapGesture(count: 2).onEnded { if let project { app.openProject(project) } })
            Spacer(minLength: 4)
            if let project, hover || dotsHover {
                GeometryReader { g in
                    let f = g.frame(in: .global)
                    DotsButton { app.showProjectMenu(project, at: CGPoint(x: f.minX, y: f.maxY + 4)) }
                }
                .frame(width: 20, height: 20)
                .onHover { dotsHover = $0 }
            }
            if let plus { SmallPlus(help: project == nil ? "Новый разговор" : "Новый разговор в «\(title)»", action: plus) }
        }
        .padding(.leading, 10).padding(.trailing, 4).frame(height: 24)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Карточка профиля внизу панели: m-3 rounded-xl border bg-card/40 px-2.5 py-2
struct ProfileCard: View {
    let name: String
    let plan: String

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(String(name.prefix(1)).uppercased())
                .font(.geist(12, .medium))
                .frame(width: 28, height: 28)
                .background(p.foreground.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(name.isEmpty ? "Без имени" : name).tw(14, lh: 20).lineLimit(1)
                Text(plan).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(hover ? p.card : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Две вкладки, как Chat / Code в Claude (`tablist` в макете): mx-3 rounded-xl bg-foreground/[0.05] p-0.5.
/// «Боты» появятся, когда заработают.
struct TabSwitch: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 2) {
            tab(.chat, "Чат", "message-square")
            tab(.agent, "Агент", "square-terminal")
            tab(.bots, "Боты", "bot")
        }
        .padding(2)
        .background(p.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
    }

    private func tab(_ t: AppModel.Tab, _ name: String, _ icon: String) -> some View {
        let active = app.tab == t
        return Button {
            app.switchTab(t)
        } label: {
            HStack(spacing: 6) {
                Icon(icon, 14).foregroundStyle(active ? p.glow : p.mutedFg)
                Text(name).font(.geist(13))
            }
            .foregroundStyle(active ? p.foreground : p.mutedFg)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(active ? p.background : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? p.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// «+ Новый чат»: h-8 rounded-lg bg-foreground/[0.06] px-2.5 text-sm
struct NewButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon("plus", 16)
                Text(title).font(.geist(14))
            }
            .padding(.horizontal, 10).frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.foreground.opacity(hover ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: R.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Строка разговора (`Row`): px-2.5 py-1.5 text-sm text-foreground/80, активная — bg-foreground/[0.07] и световая черта
struct ChatRow: View {
    @Bindable var app: AppModel
    let c: Conversation

    @Environment(\.palette) private var p
    @State private var hover = false

    @State private var newTitle = ""
    @FocusState private var focused: Bool
    /// Мышь на «…»: строка при этом не должна прятать их (иначе нажать невозможно)
    @State private var dotsHover = false

    private var renaming: Bool { app.renamingID == c.id }

    private var active: Bool { app.page == .chat && app.chat.conversation?.id == c.id }
    private var running: Bool { app.chat.isRunning(c.id) }

    var body: some View {
        Button { app.openChat(c) } label: {
            HStack(alignment: c.kind == .agent ? .top : .center, spacing: 8) {
                if c.kind == .agent {
                    // как в макете: ноутбук (на этом Маке) или крутилка, пока работает
                    Group {
                        if running { LiveDot(color: p.glow) } else { Icon("laptop", 14) }
                    }
                    .foregroundStyle(p.mutedFg).frame(width: 20, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        if renaming {
                            renameField
                        } else {
                            Text(c.title).font(.geist(14)).lineLimit(1)
                                .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                        }
                        Text(AppModel.folderName(URL(fileURLWithPath: c.folder ?? ""))).font(.geist(11)).foregroundStyle(p.mutedFg).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(when).font(.geist(11)).foregroundStyle(p.mutedFg).opacity(hover ? 0 : 1)
                } else {
                    if renaming {
                        renameField
                    } else {
                        Text(c.title).font(.geist(14)).lineLimit(1)
                            .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                    }
                    Spacer(minLength: 4)
                    if running {
                        LiveDot(color: p.glow)
                    } else {
                        Text(when).font(.geist(11)).foregroundStyle(p.mutedFg).opacity(hover ? 0 : 1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) {
                if active { GlowBar() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { app.renamingID = c.id })
        // «…» при наведении, как в Claude — меню без двойного щелчка
        .overlay(alignment: .trailing) {
            if (hover || dotsHover) && !renaming {
                GeometryReader { g in
                    let f = g.frame(in: .global)
                    DotsButton { app.showChatMenu(c, at: CGPoint(x: f.minX, y: f.maxY + 4)) }
                }
                .frame(width: 26, height: 26)
                .onHover { dotsHover = $0 }
                .padding(.trailing, 4)
            }
        }
        .onRightClick { point in app.showChatMenu(c, at: point) }
        // тянется: в проект, в «Закреплённые», в «Недавние» (вытащить из проекта) или в правую половину окна — рядом
        .onDrag { app.startDrag(c) }
        .onChange(of: app.renamingID) { _, id in
            if id == c.id {
                newTitle = c.title
                focused = true
            }
        }
    }

    /// Меню открыто для этой строки — «…» не прячем
    private var menuFor: Bool { false }

    /// Поле переименования прямо в строке: Enter — сохранить, Esc — отменить
    private var renameField: some View {
        TextField("", text: $newTitle)
            .textFieldStyle(.plain).font(.geist(14))
            .focused($focused)
            .onSubmit {
                app.renameChat(c, newTitle)
                app.renamingID = nil
            }
            .onExitCommand { app.renamingID = nil }
            .onChange(of: focused) { _, f in if !f && app.renamingID == c.id { app.renamingID = nil } }
    }

    /// «сейчас», «2 ч», «12 окт» — как в макете
    private var when: String { RelativeWhen.string(c.updatedAt) }
}

enum RelativeWhen {
    /// Один на всё приложение: DateFormatter дорого создавать на каждую строку списка
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    static func string(_ d: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "сейчас" }
        if s < 3600 { return "\(Int(s / 60)) мин" }
        if Calendar.current.isDateInToday(d) { return "\(Int(s / 3600)) ч" }
        if Calendar.current.isDateInYesterday(d) { return "вчера" }
        return day.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// Световая черта слева у активного пункта: top-1.5 bottom-1.5 w-[2px] bg-glow, свечение 10px
struct GlowBar: View {
    @Environment(\.palette) private var p

    var body: some View {
        Capsule().fill(p.glow).frame(width: 2).padding(.vertical, 6).shadow(color: p.glow, radius: 5)
    }
}

/// Пункт нижнего меню (`NavItem`): h-8 gap-2.5 px-2.5 text-sm text-foreground/75
struct NavRow: View {
    let title: String
    let icon: String
    let active: Bool
    var trailing: String?
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, 16).foregroundStyle(active ? p.glow : p.mutedFg).frame(width: 16)
                Text(title).font(.geist(14))
                Spacer(minLength: 0)
                if let trailing { Text(trailing).font(.geist(12)).foregroundStyle(p.mutedFg).monospacedDigit() }
            }
            .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.75))
            .padding(.horizontal, 10).frame(height: 32)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.05) : .clear),
                        in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) { if active { GlowBar() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Кнопка-иконка 28×28 rounded-lg, иконка 16, приглушённая
struct IconButton: View {
    let icon: String
    let help: String
    var active = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(icon, 16)
                .foregroundStyle(hover || active ? p.foreground : p.mutedFg)
                .frame(width: 28, height: 28)
                .background(active ? p.secondary : (hover ? p.foreground.opacity(0.05) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Кнопки в строке с кнопками окна: спрятать / показать панель и поиск (⌘K)
struct WindowControls: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: 4) {
            IconButton(icon: "panel-left", help: app.prefs.sidebarHidden ? "Показать панель · ⌘\\" : "Спрятать панель · ⌘\\") {
                app.update { $0.sidebarHidden.toggle() }
            }
            IconButton(icon: "search", help: "Найти в разговорах · ⌘K") { app.searchOpen = true }
        }
        .frame(height: 28)
        .padding(.top, 0)
    }
}

/// «…» на строке разговора
struct DotsButton: View {
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon("ellipsis", 16)
                .foregroundStyle(hover ? p.foreground : p.mutedFg)
                .frame(width: 26, height: 26)
                // подложка — только когда мышь на самих «…», иначе кажется, что на них уже навели
                .background(hover ? p.foreground.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Ещё")
    }
}


/// Вкладка «Боты» в панели: создать, каталог и список ботов — как разговоры у Чата и Агента
struct BotsSidebar: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewButton(title: "Создать бота") { app.page = .botEditor(nil) }
                .padding(.bottom, 12)
            NavRow(title: "Все боты", icon: "layout-grid", active: app.page == .bots) { app.page = .bots }
                .padding(.bottom, 12)
            if !app.bots.isEmpty {
                HStack {
                    Text("Группы").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    Spacer()
                    IconButton(icon: "plus", help: "Создать группу ботов") { app.page = .groupEditor(nil) }
                }
                .padding(.horizontal, 10).padding(.bottom, 4)
                if app.groups.isEmpty {
                    Button { app.page = .groupEditor(nil) } label: {
                        IconLabel(text: "Собрать группу из ботов", icon: "users", size: 14).tw(13, lh: 18).foregroundStyle(p.mutedFg)
                            .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(app.groups) { g in GroupRow(app: app, group: g) }
                Text("Боты").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    .padding(.horizontal, 10).padding(.bottom, 4).padding(.top, 12)
                ForEach(app.bots) { b in BotRow(app: app, bot: b) }
            }
        }
    }
}

private struct BotRow: View {
    @Bindable var app: AppModel
    let bot: Bot

    @Environment(\.palette) private var p
    @State private var hover = false

    private var active: Bool {
        switch app.page {
        case .bot(let id), .botEditor(.some(let id)): id == bot.id
        default: false
        }
    }

    private var working: Bool {
        app.botRuns[bot.id] != nil || app.chat.turns.values.contains { $0.conversation.kind == .bot && $0.conversation.botID == bot.id }
    }

    var body: some View {
        Button { app.openBot(bot.id) } label: {
            HStack(spacing: 10) {
                BotAvatar(bot: bot, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot.name).tw(14, lh: 20).lineLimit(1)
                    Text("@\(bot.id)").tw(11, lh: 14).foregroundStyle(BotColor.accent(bot.hue).opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if working { LiveDot(color: BotColor.accent(bot.hue)) }
            }
            .foregroundStyle(active ? p.foreground : p.foreground.opacity(0.8))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .leading) {
                if active { Capsule().fill(p.glow).frame(width: 2, height: 16).offset(x: -2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onRightClick { app.showBotMenu(bot, at: $0) }
    }
}


/// Место, куда бросают разговор из списка: подсвечивается, пока над ним
private struct ChatDropTarget: ViewModifier {
    @Bindable var app: AppModel
    var enabled = true
    let action: (Conversation) -> Void

    @Environment(\.palette) private var p
    @State private var over = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .background(over ? p.glow.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(over ? p.glow.opacity(0.6) : .clear))
                .dropDestination(for: String.self) { items, _ in
                    guard let c = app.dropped(items) else { return false }
                    action(c)
                    return true
                } isTargeted: { over = $0 }
        } else {
            content
        }
    }
}

extension View {
    func dropTarget(_ app: AppModel, enabled: Bool = true, action: @escaping (Conversation) -> Void) -> some View {
        modifier(ChatDropTarget(app: app, enabled: enabled, action: action))
    }
}
