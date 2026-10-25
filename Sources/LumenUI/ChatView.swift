import AppKit
import LumenCore
import SwiftUI
import UniformTypeIdentifiers

/// Чат (`pages/chat-page.tsx`): шапка, переписка, поле ввода — размеры из макета.
/// Чего нет, потому что ещё не работает: «+», голос, песочница и правая панель контекста.
struct ChatView: View {
    @Bindable var app: AppModel
    /// Разговор рядом (разделённый экран) — со своим контроллером; nil — главный
    var controller: ChatController?

    @Environment(\.palette) private var p
    @Environment(\.petMark) private var petMark
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var dropping = false
    /// Переписка у самого низа — тогда кнопка «вниз» не нужна, а при смене ширины окна держимся низа
    @State private var atBottom = true
    /// Сколько блоков шагов раскрыто: пока человек их читает, переписка не уезжает вниз за ответом (Рома, 19.10)
    @State private var openedSteps = 0
    /// Был ли внизу, когда начала меняться ширина, и счётчик изменений ширины
    @State private var wasAtBottom: Bool?
    @State private var widthGeneration = 0
    /// Поле ввода в фокусе — шар приветствия «горячий», ореол ярче
    @State private var composerFocused = false
    /// Переписка прокручена больше чем на 4 pt — у шапки появляются размытие и линия
    @State private var scrolled = false
    /// Название разговора правят прямо в шапке
    @State private var titleEditing = false

    private var chat: ChatController { controller ?? app.chat }
    private var isSplit: Bool { controller != nil }
    private var backend: Backend { chat.conversation?.backend ?? app.prefs.backend }
    private var agent: Bool { chat.conversation.map { $0.kind == .agent } ?? (app.tab == .agent) }
    private var folder: URL? { chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder }
    /// Проект разговора — в шапке видно, что чат создан именно в нём (и у начатого, и у нового)
    private var projectName: String? { app.project(chat.conversation?.projectID ?? chat.newProjectID)?.name }
    /// Открыт постоянный разговор бота
    private var bot: Bot? { chat.conversation?.kind == .bot ? app.bot(chat.conversation?.botID) : nil }
    private var group: BotGroup? { chat.conversation?.kind == .group ? app.group(chat.conversation?.groupID) : nil }

    var body: some View {
        HStack(spacing: 0) {
            // переписка меняет ширину сразу (см. RootView): анимирует только выезжающая панель
            content.transaction { $0.animation = nil }
            if app.prefs.contextOpen && !isSplit {
                Group {
                    if let group { GroupPanel(app: app, group: group) } else if let bot { BotPassport(app: app, bot: bot) } else { ContextPanel(app: app) }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.prefs.contextOpen)
    }

    /// Ширина колонки переписки: у агента — из настроек, у чата и ботов — всегда обычная, не меняется (Рома, 18.10)
    static func columnWidth(app: AppModel, conversation: Conversation?, agent: Bool = false) -> CGFloat {
        let isAgent = conversation.map { $0.kind == .agent } ?? agent
        return CGFloat(isAgent ? app.prefs.chatWidth.points : ChatWidth.normal.points)
    }

    private var columnWidth: CGFloat { Self.columnWidth(app: app, conversation: chat.conversation, agent: agent) }

    private var content: some View {
        // шапка лежит поверх переписки и фона: сама прозрачная, размытие — только когда под ней уже что-то прокрутилось
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if chat.messages.isEmpty && !chat.busy {
                    // как в Claude: на пустом экране приветствие и поле ввода — по центру; в разговоре поле внизу
                    Group {
                        if agent { AgentHome(app: app, draft: $draft, attachments: $attachments, backend: backend) } else { startScreen }
                    }
                    .padding(.top, Self.headerHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    transcript
                    Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: agent, controller: controller, disclaimer: true)
                }
            }
            header
        }
        .foregroundStyle(p.foreground)
        // файлы и картинки можно бросить в любое место разговора, не только в поле
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            app.attach(providers) { attachments.append($0) }
            return true
        }
        .overlay {
            if dropping {
                ZStack {
                    p.background.opacity(0.7)
                    VStack(spacing: 10) {
                        Icon("paperclip", 28).foregroundStyle(p.glow)
                        Text("Отпусти — прикреплю").tw(16, .medium, lh: 22)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(12))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropping)
        // тянут разговор из списка — правая половина: «откроется рядом»
        .overlay(alignment: .trailing) {
            if app.draggingChat != nil, !isSplit, app.split == nil {
                SplitDropZone(app: app).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.draggingChat)
        // прикрепили с «Артефактов» — в поле ввода этого разговора
        .onAppear(perform: takeInbox)
        .onChange(of: app.attachInbox) { takeInbox() }
        .onAppear(perform: takeDraftInbox)
        .onChange(of: app.draftInbox) { takeDraftInbox() }
    }

    /// Цитата из файла в панели сбоку — в конец текста в поле ввода (с новой строки)
    private func takeDraftInbox() {
        guard !isSplit, !app.draftInbox.isEmpty else { return }
        draft += (draft.isEmpty || draft.hasSuffix("\n") ? "" : "\n\n") + app.draftInbox
        app.draftInbox = ""
    }

    private func takeInbox() {
        guard !isSplit, !app.attachInbox.isEmpty else { return }
        // каждый файл — карточкой в тексте, с новой строки: после неё человек пишет правку, потом прикладывает следующий
        for a in app.attachInbox where !attachments.contains(where: { $0.path == a.path }) {
            attachments.append(a)
            draft += (draft.isEmpty || draft.hasSuffix("\n") ? "" : "\n") + FileMarks.marker(a.id)
        }
        app.attachInbox = []
    }

    static let headerHeight: CGFloat = 40

    /// Пустой экран и новый чат: названия нет — его роль у приветствия
    private var showsTitle: Bool { !(chat.messages.isEmpty && !chat.busy) }
    private var barSolid: Bool { scrolled && showsTitle }

    /// Шапка — часть окна: 52 pt, прозрачная, вся — место, за которое тянут окно. Название по центру,
    /// справа фоновые задачи и кнопки. Размытие и линия — только когда переписка прокручена
    private var header: some View {
        GeometryReader { g in
            // как в Claude: название слева, у окна, кнопки справа — всё на одной линии со светофором. После значков окна (сайдбар спрятан) — правее
            HStack(spacing: 2) {
                if showsTitle { headerTitle.frame(maxWidth: g.size.width * 0.5, alignment: .leading) }
                Spacer(minLength: 0)
                headerButtons
            }
            .padding(.leading, app.prefs.sidebarHidden ? 168 : 24).padding(.trailing, 12)
            .frame(width: g.size.width, height: Self.headerHeight)
            // светофор сидит выше середины шапки — поднимаем строку на его линию
            .offset(y: -4)
        }
        .frame(height: Self.headerHeight)
        .background(WindowDragArea())
        // плашки нет: под шапкой текст не обрезается краем, а растворяется (маска у прокрутки) — шва с фоном не бывает
        .onChange(of: chat.conversation?.id) { scrolled = false }
    }

    @ViewBuilder private var headerTitle: some View {
        if let group {
            HeaderTitle(text: group.name, project: nil, editing: .constant(false), conversation: nil, app: app, onMenu: { _ in })
        } else if let bot {
            HeaderTitle(text: bot.name, project: nil, editing: .constant(false), conversation: nil, app: app, onMenu: { _ in })
        } else if let c = chat.conversation {
            // меню разговора («⋯» раньше сбоку) — по галочке у названия, как в Claude
            HeaderTitle(text: c.title, project: app.project(c.projectID), editing: $titleEditing, conversation: c, app: app) { point in
                app.showChatMenu(c, at: point) { titleEditing = true }
            }
        }
    }

    /// Справа: задачи в фоне, браузер сбоку, панель контекста, «⋯»
    @ViewBuilder private var headerButtons: some View {
        let running = chat.openBackgroundTasks.filter { $0.status == .running }.count
        if running > 0 {
            HStack(spacing: 7) {
                PillSpinner(color: p.accentSoft)
                Text("\(running) " + Plural.form(running, "задача", "задачи", "задач"))
            }
            .tw(12.5, lh: 16).foregroundStyle(p.accentSoft)
            .padding(.horizontal, 11).frame(height: 28)
            .background(p.accentTint, in: Capsule())
            .padding(.trailing, 6)
            .help("Фоновые задачи агента — под перепиской")
        }
        if isSplit {
            IconButton(icon: "x", help: chat.busy ? "Закроется, когда ответ закончится" : "Закрыть разговор рядом", side: 32, iconSize: 17) { app.closeSplit() }
                .disabled(chat.busy)
        }
        if !isSplit {
            if let bot { IconButton(icon: "pencil", help: "Изменить бота", side: 32, iconSize: 17) { app.page = .botEditor(bot.id) } }
            if let group { IconButton(icon: "pencil", help: "Изменить группу", side: 32, iconSize: 17) { app.page = .groupEditor(group.id) } }
            IconButton(icon: "globe", help: "Браузер сбоку (⇧⌘B): агенты работают в нём, ты входишь в аккаунты", active: app.browserOpen,
                       side: 32, iconSize: 17) {
                app.toggleBrowser()
            }
            IconButton(icon: "panel-right", help: bot == nil ? "Контекст: память, окно, расход" : "Паспорт бота: что может и что отрезано",
                       active: app.prefs.contextOpen, side: 32, iconSize: 17) {
                app.update { $0.contextOpen.toggle() }
            }
        }
    }

    /// Меню под названием: переименовать, перенести, удалить («Поделиться» нет — такой возможности в Lumen нет)
    private func titleMenu(_ c: Conversation, at point: CGPoint) {
        app.menu = MenuState(items: [
            MenuItem(title: "Переименовать", key: "r") { titleEditing = true },
            MenuItem(title: "Переместить в проект…", key: "m") { [app] in
                DispatchQueue.main.async { app.showMoveMenu(c, at: point) }
            },
            MenuItem(title: "Удалить", key: "d", destructive: true, separated: true) { [app] in app.deleteChat(c) },
        ], anchor: point)
    }

    /// Пустой экран как в Claude: крупное приветствие, под ним сразу поле ввода, ниже — подсказки
    private var startScreen: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                greeting
                    .padding(.bottom, 46)
                Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: false, focusedOut: $composerFocused)
                // подсказок для начала разговора в чате нет (Рома, 18.10). Снизу запас ~13% высоты — всё чуть выше центра
                Spacer(minLength: 24)
                Color.clear.frame(height: g.size.height * 0.13)
            }
            .frame(maxWidth: .infinity)
        }
    }


    @ViewBuilder private var greeting: some View {
        if let group {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    GroupAvatars(bots: app.groupMembers(group), size: 40)
                    Text(group.name).font(.greeting(38)).tracking(-0.76).foregroundStyle(p.textStrong).lineLimit(1)
                }
                Text("Пиши всем — ответят по очереди. «@id …» — ответит только он.")
                    .tw(13, lh: 18).foregroundStyle(p.mutedFg)
            }
        } else if let bot {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    BotAvatar(bot: bot, size: 44)
                    Text(bot.name).font(.greeting(38)).tracking(-0.76).foregroundStyle(p.textStrong).lineLimit(1)
                }
                if !bot.role.isEmpty { Text(bot.role).tw(13, lh: 18).foregroundStyle(p.mutedFg) }
            }
        } else {
            // шар 78 и «Привет, имя» — Literata 60, в узком окне шар встаёт над текстом. Без свечения сзади (Рома, 21.10)
            let hot = composerFocused || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let text = Text(app.profile.name.isEmpty ? "Привет" : "Привет, \(app.profile.name)")
                .font(.greeting(60)).tracking(-1.2).foregroundStyle(p.textStrong)
                .lineLimit(1).fixedSize()
                .accessibilityAddTraits(.isHeader)
            let orb = LumenMark(state: app.orb, size: 78, hot: hot).skyAnchor()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 26) { orb; text }
                VStack(spacing: 26) { orb; text.minimumScaleFactor(0.5) }
            }
            .padding(.horizontal, 28)
        }
    }

    @ViewBuilder private var startChips: some View {
        if let group {
            let first = app.groupMembers(group).first?.id ?? "бот"
            StartChips(items: ["Обсудите, с чего начать", "Каждый — по одной идее", "@\(first) начни"],
                       icons: ["users", "lightbulb", "at-sign"], tint: p.glow) { draft = $0 }
        } else if let bot {
            if !bot.starters.isEmpty {
                StartChips(items: bot.starters, icons: [bot.icon], tint: BotColor.accent(bot.hue)) { draft = $0 }
            }
        } else {
            StartChips(items: app.suggestions, icons: ["lightbulb", "pen-line", "sparkles", "message-circle"], tint: p.glow) { draft = $0 }
                .animation(.easeOut(duration: 0.3), value: app.suggestions)
                .task { app.refreshSuggestionsIfNeeded() }
        }
    }

    /// Питомец сидит рядом с последним ответом (на месте знака), если он включён «всегда в переписке», не висит поверх окон
    /// и не стоит сейчас на строке «думаю» вместо знака — тогда двух не бывает, и паузы между ними нет
    private var restingPet: Bool {
        let pet = app.prefs.pet
        guard pet.enabled, pet.alwaysInChat, !pet.floating, !chat.messages.isEmpty || chat.streaming != nil else { return false }
        return !(pet.inChat && (chat.thinking || liveStepRowShown))
    }

    /// Питомец уже стоит на строке идущего шага: отдельной строкой «Запускает…» (ответ ещё не начат)
    /// или в группе шагов внутри пишущегося ответа, если она в нём последняя (см. MessageRow)
    private var liveStepRowShown: Bool {
        guard chat.busy, !chat.thinking, chat.pendingPermission == nil, chat.liveStep != nil else { return false }
        guard let s = chat.streaming else { return true }
        if let last = AnswerPiece.layout(text: NextStep.split(s.text).text, steps: s.steps).last, case .steps = last { return true }
        return false
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            transcriptScroll(proxy)
        }
        // свой список на каждый разговор: ленивый список не путает строки при смене вкладки
        .id(chat.conversation?.id ?? "new")
    }

    private func transcriptScroll(_ proxy: ScrollViewProxy) -> some View {
        Group {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { m in
                        // между сообщениями 32 (макет 21.10); строки состояния под ответом — ближе, через 14
                        MessageRow(message: m, chat: chat, isLast: m.id == chat.messages.last?.id,
                                   pet: restingPet && chat.streaming == nil && m.role == .assistant
                                       && m.id == chat.messages.last(where: { $0.role == .assistant })?.id
                                       ? (chat.busy ? .thinking : app.petMood) : nil,
                                   // знак один на весь чат: у последнего ответа, и только когда ход не идёт — иначе он у строки «работает»
                                   showsMark: !chat.busy && chat.streaming == nil
                                       && m.id == chat.messages.last(where: { $0.role == .assistant })?.id).id(m.id)
                            .padding(.top, m.id != chat.messages.first?.id ? 18 : 0)
                    }
                    if !chat.busy, let last = chat.messages.last, let next = last.next {
                        NextStepCard(next: next) { chat.answer($0, on: last) } close: { chat.dismissNext(last) }
                    }
                    // план — над идущим ответом, близко к нему; что агент делает сейчас — уже под планом
                    VStack(alignment: .leading, spacing: 6) {
                        // план — в самой переписке, после последнего сообщения: листается вместе с чатом и не закрывает экран
                        // план — только пока идёт ход (здесь или в приложении Claude) и в нём есть несделанное.
                        // Ход кончился — план уходит, даже если агент не отметил шаги; весь сделан — тоже уходит,
                        // и новый ход в Claude не показывает старый план, пока не составит свой (Рома, 17.10)
                        if let c = chat.conversation, c.kind != .chat, !c.plan.isEmpty,
                           chat.busy || app.claudeBusy(c.id), c.plan.contains(where: { $0.state != .done }) {
                            PlanCard(items: c.plan)
                        }
                        if let s = chat.streaming {
                            MessageRow(message: s, chat: chat, streaming: true, pet: restingPet ? .writing : nil).padding(.top, chat.messages.isEmpty ? 0 : 18)
                        }
                    }
                    // позванный бот работает: что делает и что пишет — прямо в чате, пока не закончит
                    if let c = chat.conversation, let w = chat.liveWork[c.id] {
                        LiveBotWork(work: w, bot: app.bot(w.bot))
                    }
                    // разговор сейчас идёт в приложении Claude — видно здесь (по записям сессии, а не по времени файла)
                    if !chat.busy, let c = chat.conversation, let live = app.claudeLive[c.id] {
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            let steps = chat.messages.last.flatMap { $0.role == .assistant && $0.via?.isClaudeCode == true ? $0.steps : nil } ?? []
                            switch live.active(now: ctx.date) {
                            case .working(let since, let step): ClaudeLiveLine(text: step ?? "Работает", since: since, steps: steps)
                            case .retrying(let since):
                                ClaudeLiveLine(text: "Нет связи с API, повторяет", since: since, steps: steps, tint: Palette.destructive)
                            case .idle: EmptyView()
                            }
                        }
                    }
                    // что агент делает прямо сейчас — пока идёт инструмент (текст после него ещё не пошёл)
                    // (если шаги уже в ответе — это его последняя группа шагов, отдельной строки не нужно)
                    if chat.busy, !chat.thinking, chat.pendingPermission == nil, let live = chat.liveStep, chat.streaming == nil,
                       (live.step.at ?? 0) >= (chat.streaming?.text.count ?? 0) {
                        LiveStepLine(text: live.step.text, since: live.since, tint: app.bot(chat.turnBot).map { BotColor.accent($0.hue) }, bot: app.bot(chat.turnBot))
                    }
                    // шага на экране нет (пишется текст) — время хода всё равно на виду
                    if chat.busy, !chat.thinking, chat.pendingPermission == nil, !liveStepRowShown, let start = chat.turnStart {
                        TurnClockLine(text: chat.streaming == nil ? "Работает" : "Пишет ответ", since: start,
                                      tint: app.bot(chat.turnBot).map { BotColor.accent($0.hue) })
                    }
                    // фоновые задачи агента: работают — видно всегда; закончились — пока идёт ход и ещё полчаса
                    if let c = chat.conversation, let tasks = chat.backgroundTasks[c.id],
                       tasks.contains(where: { $0.status == .running || chat.busy || ($0.ended ?? .distantFuture) > Date().addingTimeInterval(-1800) }) {
                        // под строкой «что делает сейчас», в одну колонку с ней: знак слева 26 + зазор 16 = 42; ближе, чем остальные строки (Рома, 22.10)
                        BackgroundTasksBar(tasks: tasks).padding(.leading, 42).padding(.top, -10)
                    }
                    // ответила другая модель (лимит) или ночью ждём сброса лимита — сказать прямо
                    if let c = chat.conversation, let note = chat.modelNote[c.id] {
                        HStack(spacing: 8) {
                            Icon("info", 13)
                            Text(note).tw(13, lh: 18)
                        }
                        .foregroundStyle(p.mutedFg)
                    }
                    // claude долго молчит — сказать прямо, что происходит, и дать выход
                    // сбой связи: Lumen сам повторяет или ждёт сеть — видно, что не завис
                    if chat.busy, let c = chat.conversation, let note = chat.retryNote[c.id] {
                        HStack(spacing: 10) {
                            Icon("refresh-cw", 14)
                            Text(note).tw(13, lh: 18)
                            Button("Стоп") { chat.stop() }.buttonStyle(.plain).foregroundStyle(p.glow)
                        }
                        .foregroundStyle(p.mutedFg)
                        
                    }
                    if chat.busy, chat.pendingPermission == nil, chat.conversation?.usesCLI == true,
                       chat.conversation.map({ chat.retryNote[$0.id] == nil }) ?? true {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            // идёт инструмент (Bash, сборка) — тишина ожидаемая: не «молчит», а «выполняет»
                            let tool = chat.conversation.map { chat.toolRunning[$0.id] == true } ?? false
                            if let s = chat.silence(now: ctx.date), s >= (tool ? 60 : 30) {
                                // одной строкой текста: слова переносятся по ширине колонки, кнопки — следом, а не столбиком
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Icon("clock", 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                                        Text(tool ? "\(chat.liveStep?.step.text ?? "Выполняет команду") — \(Int(s)) с. Ждёт, пока команда закончится: для сборок и тестов это нормально"
                                             : "Claude Code молчит \(Int(s)) с — \(s > 90 ? "ждёт ответа API; на 3-й минуте прерву и повторю сам" : "думает или ждёт ответа API")")
                                            .tw(13, lh: 18).fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    HStack(spacing: 14) {
                                        Button("Журнал") { app.update { $0.contextOpen = true; $0.panelHidden.removeAll { $0 == "log" } } }
                                            .buttonStyle(.plain).foregroundStyle(p.glow)
                                        Button("Стоп") { chat.stop() }.buttonStyle(.plain).foregroundStyle(p.glow)
                                    }
                                    .padding(.leading, 21)
                                }
                                .font(.geist(13))
                                .foregroundStyle(s > 90 && !tool ? Palette.destructive : p.mutedFg)
                                
                            }
                        }
                    }
                    if let ask = chat.pendingPermission, ask.conversationID == chat.conversation?.id {
                        PermissionCard(chat: chat, ask: ask.request).id("permission-\(ask.request.id)")
                    } else if chat.thinking {
                        HStack(spacing: 10) {
                            if let b = app.bot(chat.turnBot) {
                                DotsSpinner(color: BotColor.accent(b.hue), bot: b)
                                Text(chat.launching ? "\(b.name) запускается…" : "\(b.name) работает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(BotColor.accent(b.hue))
                            } else {
                                // знак у ответа — свет бежит по кругу, пока нет первого слова; питомец «вместо точек» — вместо него
                                if petMark != nil {
                                    DotsSpinner(color: p.glow).frame(width: 26).padding(.trailing, 6)
                                } else if !(app.prefs.pet.enabled && !app.prefs.pet.floating) {
                                    // питомец в переписке включён — затмения нет, даже если «вместо знака» выключено
                                    LumenMark(state: .thinking, size: 26).padding(.trailing, 6)
                                }
                                Text(chat.launching ? "Запускаю…" : "Думаю…").tw(16, lh: 26).foregroundStyle(p.mutedFg)
                            }
                            if let start = chat.turnStart {
                                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                    Text(LiveStepLine.elapsed(ctx.date.timeIntervalSince(start))).tw(13, lh: 20)
                                        .foregroundStyle(p.faint).monospacedDigit()
                                }
                            }
                        }
                        .padding(.top, chat.streaming == nil && !chat.messages.isEmpty ? 18 : 0)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                // без «резинки» сверху и снизу
                .background(NoBounce())
                // поля по бокам: на узком окне переписка не упирается в края
                // слева 44: знак (затмение, питомец, бот) висит левее текста ответа, в этом поле; поле ввода ниже — с теми же отступами
                .padding(.leading, 44).padding(.trailing, 28).padding(.top, 18).padding(.bottom, 48)
                .frame(maxWidth: columnWidth)
                .animation(.easeInOut(duration: 0.3), value: app.prefs.chatWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .contentMargins(.top, Self.headerHeight, for: .scrollContent)
            // верх переписки растворяется под шапкой: вместо плашки с краем, который виден швом на фоне со звёздами
            .modifier(HeaderFade(height: Self.headerHeight + 22))
            .modifier(ScrolledPast(scrolled: $scrolled, threshold: 4))
            // к концу — когда страница уже разложена (иначе после смены вкладки переписка оказывалась пустой)
            // разговор открывается сразу внизу и держится у низа, пока высоты сообщений досчитываются
            // (раньше прокрутка «к низу» при открытии промахивалась мимо ленивого списка — экран был пустой)
            .defaultScrollAnchor(.bottom)
            // перенесённый из Claude Code разговор: пока открыт — догоняет то, что пишется там (раз в 3 с, только если файл менялся)
            .task(id: chat.conversation?.id) {
                while !Task.isCancelled {
                    if let c = chat.conversation, c.kind == .agent {
                        await app.syncFromClaude(c, in: chat)
                        chat.claudeWentIdle(c.id)
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            // за ответом вниз — только если человек и так внизу; отлистал вверх читать — не дёргать
            .onChange(of: chat.messages.count) { if (atBottom && openedSteps == 0) || chat.messages.last?.role == .user { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.streaming?.text.count) { if atBottom && openedSteps == 0 { proxy.scrollTo("bottom", anchor: .bottom) } }
            .environment(\.stepsOpened) { opened in openedSteps = max(0, openedSteps + (opened ? 1 : -1)) }
            .onChange(of: chat.pendingPermission?.request.id) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.scrollTarget) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .top) }
                chat.scrollTarget = nil
            }
            // оглавление: главы разговора справа сверху
            .overlay(alignment: .topTrailing) {
                if chat.messages.contains(where: \.chapter) { ChaptersButton(chat: chat).padding([.horizontal, .bottom], 16).padding(.top, Self.headerHeight + 6) }
            }
            // где мы в переписке: у низа ли и какое сообщение сверху
            .modifier(ScrollTracking(atBottom: $atBottom) { if openedSteps == 0 { proxy.scrollTo("bottom", anchor: .bottom) } })
            // ширина поменялась (спрятали или показали панель, потянули окно) — ленивый список теряет место:
            // вернуть к низу или к тому сообщению, что было сверху
            // ширина поменялась (панель, браузер): был внизу — остаться внизу, когда ширина успокоится.
            // Середину не трогаем: прыжок к сообщению в ленивом списке оставлял экран пустым до прокрутки
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                if wasAtBottom == nil { wasAtBottom = atBottom }
                widthGeneration += 1
                let gen = widthGeneration
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard gen == widthGeneration, let bottom = wasAtBottom else { return }
                    wasAtBottom = nil
                    if bottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            // окно переписки стало ниже или выше — выросло поле ввода (очередь, вложения, длинный черновик). Был внизу —
            // остаться внизу: иначе последние строки уезжали под поле, и казалось, что переписку подняло вверх (Рома, 19.10)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // кнопка «вниз», когда отлистал вверх
            .overlay(alignment: .bottom) {
                if !atBottom && !chat.messages.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Icon("arrow-down", 16).foregroundStyle(p.foreground)
                            .frame(width: 34, height: 34)
                            .background(p.popover, in: Circle())
                            .overlay(Circle().strokeBorder(p.foreground.opacity(0.12)))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .help("Вниз, к последнему сообщению")
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
        }
    }
}

/// Подсказки пустого чата: rounded-full border bg-card/50 px-3.5 py-1.5 text-sm, в несколько строк по центру
struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        // в макете flex-wrap justify-center: при узком окне переносятся
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(spacing: 8) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { i in Chip(text: i) { pick(i) } }
    }

    private struct Chip: View {
        let text: String
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                Text(text).tw(14, lh: 20)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(hover ? p.card : p.card.opacity(0.5), in: Capsule())
                    .overlay(Capsule().strokeBorder(hover ? p.glow.opacity(0.4) : p.border))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

enum Plural {
    /// «1 факт», «3 факта», «15 фактов»
    static func facts(_ n: Int) -> String { "\(n) " + form(n, "факт", "факта", "фактов") }
    static func links(_ n: Int) -> String { "\(n) " + form(n, "связь", "связи", "связей") }
    static func bots(_ n: Int) -> String { "\(n) " + form(n, "бот", "бота", "ботов") }

    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}

/// Одно сообщение: своё — пузырём справа (`UserMsg`), ответ Lumen — со сферой слева (`LumenMsg`)
struct MessageRow: View {
    let message: ChatMessage
    var chat: ChatController?
    var streaming = false
    /// Последнее сообщение — действия видны всегда, у остальных — при наведении
    var isLast = false
    /// Питомец на месте знака слева от ответа (в каком он состоянии); nil — обычный знак
    var pet: PetMood?
    /// Знак слева (затмение, питомец или бот) — один на весь чат: только у последнего ответа, у остальных пусто (Рома, 22.10)
    var showsMark = true

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var editing = false
    @State private var editText = ""
    /// Какой из прежних вариантов ответа показан (nil — нынешний)
    @State private var variant: Int?

    /// Ответ с выбранным вариантом вместо нынешнего
    private var shownMessage: ChatMessage {
        guard let i = variant, let alts = message.alternates, alts.indices.contains(i) else { return message }
        var m = message
        let v = alts[i]
        m.text = v.text
        m.steps = v.steps
        m.attachments = v.attachments
        m.error = v.error
        m.changes = nil
        m.next = nil
        m.createdAt = v.createdAt
        return m
    }

    /// Прежний вопрос, на который отвечал показанный вариант (если вопрос потом изменили)
    private var variantPrompt: String? {
        guard let i = variant, let alts = message.alternates, alts.indices.contains(i) else { return nil }
        return alts[i].prompt
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.chapter { ChapterMark(title: ChapterMark.title(message)) }
            content
        }
        .onHover { hover = $0 }
    }

    /// Пузырь человека: 20/20/6/20, мягкий градиент и тонкое кольцо внутри, без тени (макет 21.10)
    private func userBubble(_ text: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            let bubble = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20,
                                                style: .continuous)
            Text(text)
                .chatTw(15.5, lh: 24)
                .textSelection(.enabled)
                .padding(.horizontal, 17).padding(.vertical, 11)
                .background(bubble.fill(p.bubbleFill))
                .overlay(bubble.strokeBorder(p.bubbleRing))
                // 74% колонки переписки, а не окна: иначе на широком окне пузырь вылезает к правому краю
                .frame(maxWidth: bubbleMax, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Действия под сообщением: как в Claude
    private var showActions: Bool { chat != nil && !streaming && message.note == nil && (hover || isLast || editing) }

    @ViewBuilder private var content: some View {
        if let note = message.note {
            HStack(spacing: 8) {
                Icon("rotate-ccw", 14)
                Text(note)
            }
            .font(.geist(12)).foregroundStyle(p.mutedFg)
            .frame(maxWidth: .infinity)
        } else if message.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
            // приписка агенту с путями вложений — не для человека
            let shownText = Attachment.splitSavedNote(message.text).text
            let segments = FileMarks.segments(shownText)
            // карточки, на которые ссылается текст («[Файл: имя]»), стоят в нём; остальные — над сообщением
            let cited = Set(segments.compactMap { if case .file(let n) = $0 { return n } else { return nil } })
            let loose = message.attachments.filter { !cited.contains($0.name) }
            if !loose.isEmpty {
                MessageAttachments(items: loose).frame(maxWidth: .infinity, alignment: .trailing)
            }
            if editing {
                editor
            } else if FileMarks.hasFiles(shownText) {
                // карточка файла и под ней правка к нему; дальше — следующий файл и его правка
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .file(let name):
                        if let a = message.attachments.first(where: { $0.name == name }) {
                            MessageAttachments(items: [a]).frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Text(name).font(.geist(13)).foregroundStyle(p.mutedFg)
                        }
                    case .text(let t): userBubble(t)
                    }
                }
            } else if !shownText.isEmpty {
                userBubble(shownText)
            }
            if let via = message.via, !via.isClaudeCode { ViaChip(via: via, app: chat?.app) }
            if !editing, let chat {
                MessageActions(message: message, chat: chat, user: true) { editText = message.text; editing = true }
                    .opacity(showActions ? 1 : 0)
            }
            }
        } else {
            // выбран прежний вариант ответа (‹ 1/3 ›) — показываем его
            let original = message
            let message = shownMessage
            // источники ответа (вариант A): чипы под текстом и номера у ссылок; пока печатается — не считаем
            let sources = streaming ? [] : SourceCache.sources(for: message)
            let sourceNumbers = Dictionary(sources.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a })
            // текст ответа стоит ровно по левому краю поля ввода (Рома, 22.10): знак (затмение, питомец, бот) висит левее, в поле
            HStack(alignment: .top, spacing: 0) {
                // шар 26 слева от ответа (макет 21.10); у бота — его знак
                Group {
                    if !showsMark {
                        Color.clear.frame(width: 26, height: 26)
                    } else if let b = chat?.app.bot(message.botID) {
                        BotAvatar(bot: b, size: 26)
                    } else if let prefs = chat?.app.prefs.pet, prefs.enabled, !prefs.floating {
                        // питомец включён и живёт в переписке — затмения нет совсем (Рома, 22.10): на месте знака либо он, либо пусто
                        Color.clear.frame(width: 26, height: 26)
                            .overlay {
                                if let mood = pet {
                                    // питомец крупнее места под знак: сидит на нём и немного выходит за него
                                    let side: CGFloat = prefs.kind.isPixel ? 32 : 44
                                    PetView(pet: prefs, mood: mood, size: side, followsCursor: true).frame(width: side, height: side)
                                }
                            }
                            .allowsHitTesting(false)
                    } else {
                        LumenMark(size: 26, animated: false)
                    }
                }
                .padding(.top, 1)
                .frame(width: 26, height: 26, alignment: .topLeading)
                .frame(width: 0, alignment: .leading)
                .offset(x: -38)
                VStack(alignment: .leading, spacing: 12) {
                    // ответ бота в чужом чате — подписан, чтобы было видно, кто отвечал
                    if let b = chat?.app.bot(message.botID), chat?.conversation?.kind != .bot {
                        Text("@\(b.id) · \(b.name)").tw(12, .medium, lh: 16).foregroundStyle(BotColor.accent(b.hue))
                    }
                    // листаем к ответу на прежнюю формулировку вопроса — видно, на что он был
                    if let prompt = variantPrompt {
                        IconLabel(text: "Ответ на прежний вопрос: «\(prompt.prefix(80))\(prompt.count > 80 ? "…" : "")»", icon: "clock", size: 13)
                            .font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(2)
                    }
                    // как в Claude Code: абзац — шаги — абзац; блок «что дальше» пока пишется — не показывать сырым
                    let pieces = AnswerPiece.layout(text: NextStep.split(message.text).text, steps: message.steps)
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                        let last = i == pieces.count - 1
                        switch piece {
                        case .text(let t): RichText(text: t, caret: streaming && last)
                        // последняя группа шагов идущего ответа — она же «что делает сейчас»
                        case .steps(let s):
                            let shotIDs = Set(s.compactMap(\.shot))
                            let shots = message.attachments.filter { shotIDs.contains($0.id) }
                            if streaming && last, let chat, chat.busy, !chat.thinking, chat.pendingPermission == nil, let live = chat.liveStep {
                                StepsView(steps: s, live: (live.since, chat.app.bot(chat.turnBot).map { BotColor.accent($0.hue) }), shots: shots, app: chat.app)
                            } else {
                                StepsView(steps: s, shots: shots, app: chat?.app)
                            }
                        }
                    }
                    if !sources.isEmpty, let app = chat?.app {
                        SourceStrip(sources: sources) { s in if let u = URL(string: s.url) { app.openLink(u) } }
                    }
                    // снимки страниц и файлы, которые агент показал в чате
                    // снимки, сделанные на шагах, уже превью на их строке; то, что агент показал сам (show_in_chat), — крупно, файлы — карточками
                    let stepShots = Set(message.steps.compactMap(\.shot))
                    let rest = message.attachments.filter { !stepShots.contains($0.id) }
                    let big = rest.filter { $0.kind == .image && $0.snapshot != true }
                    let small = rest.filter { !($0.kind == .image && $0.snapshot != true) }
                    if !big.isEmpty { MessageAttachments(items: big, leading: true) }
                    if !small.isEmpty { AttachmentThumbs(items: small, app: chat?.app) }
                    if let changes = message.changes, let chat {
                        ChangeCard(message: message, changes: changes, chat: chat)
                    }
                    if let d = message.skillDraft, let chat {
                        SkillProposalCard(app: chat.app, message: message, draft: d)
                    }
                    if let chat {
                        ForEach(message.proposals) { pr in ProposalCard(app: chat.app, message: message, proposal: pr) }
                    }
                    if let chat {
                        // один-два факта — карточками; больше — одной сворачиваемой плашкой, а не лентой из тридцати
                        if message.remembered.count > 2 {
                            RememberedGroup(app: chat.app, ids: message.remembered)
                        } else {
                            ForEach(message.remembered, id: \.self) { id in RememberedCard(app: chat.app, id: id) }
                        }
                        if !message.recalled.isEmpty && !streaming {
                            RecalledLine(app: chat.app, ids: message.recalled)
                        }
                    }
                    if message.stopped {
                        IconLabel(text: "Остановлено", icon: "circle-stop", size: 14).font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    if let error = message.error {
                        IconLabel(text: error, icon: "triangle-alert", size: 16)
                            .font(.geist(14)).foregroundStyle(Palette.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chat, !streaming {
                            HStack(spacing: 8) {
                                LButton(title: "Повторить", icon: "rotate-ccw", kind: .outline, small: true) { chat.retry(message) }
                                    .disabled(chat.busy)
                                LButton(title: "Журнал", icon: "file-text", kind: .ghost, small: true) {
                                    NSWorkspace.shared.open(chat.app.logFile)
                                }
                                .disabled(!FileManager.default.fileExists(atPath: chat.app.logFile.path))
                            }
                        }
                    }
                    if let chat, message.error == nil {
                        MessageActions(message: original, chat: chat, user: false, variant: $variant) {}
                            .opacity(showActions ? 1 : 0)
                    }
                }
                .environment(\.sourceNumbers, sourceNumbers)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension MessageRow {
    /// Самый широкий пузырь человека — 74% колонки переписки
    var bubbleMax: CGFloat { (chat.map { ChatView.columnWidth(app: $0.app, conversation: $0.conversation) } ?? 720) * 0.74 }

    var editor: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.geist(14))
                .lineLimit(1...14)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(p.secondary, in: RoundedRectangle(cornerRadius: R.xxl))
                .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(0.35)))
                .onSubmit(sendEdit)
            HStack(spacing: 8) {
                Text("Ответ ниже заменится — Lumen забудет, что было после").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                LButton(title: "Отмена", kind: .ghost, small: true) { editing = false }
                LButton(title: "Отправить", kind: .primary, small: true, action: sendEdit)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat?.busy == true)
            }
        }
        .frame(maxWidth: bubbleMax, alignment: .trailing)
    }

    private func sendEdit() {
        let t = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let chat, !chat.busy else { return }
        editing = false
        chat.resend(from: message, text: t)
    }
}

/// Строка действий: у своего — время, «Попробовать снова», «Изменить», «Копировать», «Глава»;
/// у ответа — «Копировать», «Попробовать снова», «Глава», время
struct MessageActions: View {
    let message: ChatMessage
    let chat: ChatController
    let user: Bool
    /// Варианты ответа: какой показан (nil — нынешний, последний)
    var variant: Binding<Int?>? = nil
    let edit: () -> Void

    @Environment(\.palette) private var p
    @State private var copied = false

    init(message: ChatMessage, chat: ChatController, user: Bool, variant: Binding<Int?>? = nil, edit: @escaping () -> Void) {
        self.message = message
        self.chat = chat
        self.user = user
        self.variant = variant
        self.edit = edit
    }

    var body: some View {
        HStack(spacing: 2) {
            if user {
                time.padding(.trailing, 6)
                act("refresh-cw", "Попробовать снова — прежний ответ останется вариантом") {
                    // ответ на это сообщение есть — он станет вариантом нового, как в Claude
                    if let i = chat.messages.firstIndex(where: { $0.id == message.id }),
                       let answer = chat.messages[(i + 1)...].prefix(while: { $0.role != .user }).last(where: { $0.role == .assistant && $0.note == nil }) {
                        chat.retry(answer)
                    } else {
                        chat.resend(from: message, text: message.text)
                    }
                }
                .disabled(chat.busy)
                act("pencil", "Изменить", action: edit).disabled(chat.busy)
                copy
                chapter
            } else {
                copy
                act("refresh-cw", "Попробовать снова — этот ответ останется вариантом") { chat.retry(message) }.disabled(chat.busy)
                chapter
                variants
                time.padding(.leading, 6)
            }
        }
        .animation(.easeOut(duration: 0.12), value: copied)
    }

    /// ‹ 2/3 › — листать прежние варианты ответа
    @ViewBuilder private var variants: some View {
        if let variant, let alts = message.alternates, !alts.isEmpty {
            let total = alts.count + 1
            let current = (variant.wrappedValue ?? alts.count) + 1
            HStack(spacing: 0) {
                act("chevron-down", "Прежний вариант") {
                    let i = (variant.wrappedValue ?? alts.count) - 1
                    if i >= 0 { variant.wrappedValue = i }
                }
                .rotationEffect(.degrees(90)).disabled(current <= 1)
                Text("\(current) / \(total)").tw(12, lh: 16).foregroundStyle(p.mutedFg).monospacedDigit().padding(.horizontal, 2)
                act("chevron-down", "Следующий вариант") {
                    let i = (variant.wrappedValue ?? alts.count) + 1
                    variant.wrappedValue = i >= alts.count ? nil : i
                }
                .rotationEffect(.degrees(-90)).disabled(current >= total)
            }
            .padding(.leading, 4)
        }
    }

    private var time: some View {
        Text(Self.when(message.createdAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.8))
            .help(message.createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute()))
    }

    private var copy: some View {
        act(copied ? "check" : "copy", copied ? "Скопировано" : "Копировать") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NextStep.split(message.text).text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        }
    }

    private var chapter: some View {
        act("bookmark", message.chapter ? "Убрать главу" : "Закрепить главу — появится в оглавлении разговора", on: message.chapter) {
            chat.toggleChapter(message)
        }
    }

    private func act(_ icon: String, _ help: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        ActionIcon(icon: icon, on: on, action: action).help(help)
    }

    /// «сейчас», «14:32», «вчера, 14:32», «12 окт, 14:32»
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if Date().timeIntervalSince(d) < 60 { return "сейчас" }
        let hm = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return hm }
        if cal.isDateInYesterday(d) { return "вчера, " + hm }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return f.string(from: d).replacingOccurrences(of: ".", with: "") + ", " + hm
    }
}

private struct ActionIcon: View {
    let icon: String
    var on = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(on && Icon.image(icon + "-fill") != nil ? icon + "-fill" : icon, 16)
                .foregroundStyle(on ? p.glow : hover && enabled ? p.foreground : p.mutedFg)
                .frame(width: 32, height: 32)
                .background(hover && enabled ? p.hover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// Метка над сообщением-главой
struct ChapterMark: View {
    let title: String
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(p.border).frame(height: 1).frame(maxWidth: 40)
            IconLabel(text: title, icon: "bookmark", size: 12).tw(12, .medium, lh: 16).foregroundStyle(p.glow).lineLimit(1)
            Rectangle().fill(p.border).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Название главы — первая строка сообщения, коротко
    static func title(_ m: ChatMessage) -> String {
        let line = NextStep.split(m.text).text.split(separator: "\n").first.map(String.init) ?? "Глава"
        let clean = line.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        return clean.count > 60 ? String(clean.prefix(58)) + "…" : (clean.isEmpty ? "Глава" : clean)
    }
}

/// Оглавление разговора: главы по порядку, щелчок — прокрутить к ней
struct ChaptersButton: View {
    let chat: ChatController
    @Environment(\.palette) private var p
    @State private var open = false

    var body: some View {
        let chapters = chat.messages.filter(\.chapter)
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Icon("list", 13)
                Text("Главы · \(chapters.count)").font(.geist(12, .medium))
            }
            .foregroundStyle(p.foreground.opacity(0.85))
            .padding(.horizontal, 10).frame(height: 28)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(p.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Главы").tw(11, .medium, lh: 14).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.bottom, 4)
                ForEach(Array(chapters.enumerated()), id: \.element.id) { i, m in
                    Button {
                        chat.scrollTarget = m.id
                        open = false
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.geist(12, .medium)).foregroundStyle(p.glow).frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ChapterMark.title(m)).tw(13, lh: 18).lineLimit(1)
                                Text(MessageActions.when(m.createdAt)).tw(11, lh: 14).foregroundStyle(p.mutedFg)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(width: 300)
        }
    }
}

/// Текст ответа: text-[0.9375rem] leading-[1.65], абзацы через 12; разметка (жирный, курсив, `код`, ссылки) и блоки кода ```
struct RichText: View {
    let text: String
    /// Пока ответ печатается — в конце мигает светящийся курсор (`.caret` в макете)
    var caret = false

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let parts = Self.parts(text)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                switch part {
                case .prose(let s):
                    // весь текст между блоками кода — одним выделяемым полем: заголовки, списки, цитаты и линии рисуются в нём же;
                    // ссылки кликаются без ⌘ и подчёркиваются под курсором (LinkText.swift)
                    LinkText(source: s, size: 16, lineHeight: 26.9, caret: caret && i == parts.count - 1)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let s, let lang):
                    CodeBlock(code: s, lang: lang)
                case .table(let rows):
                    MarkdownTable(rows: rows)
                case .visual(let code, let done):
                    VisualBlock(code: code, done: done)
                }
            }
        }
    }

    enum Part: Equatable { case prose(String), code(String, lang: String?), table([[String]]), visual(String, done: Bool) }

    /// Черта курсора 2 × 17.6 (1.1em при 16): шаблон, красится цветом текста
    @MainActor static let caretBar: NSImage = {
        let img = NSImage(size: NSSize(width: 2, height: 17.6), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    /// Таблица markdown: строки «| a | b |», вторая — «|---|---|». Не таблица — nil
    static func table(_ para: String) -> [[String]]? {
        let lines = para.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("|") }),
              lines[1].replacingOccurrences(of: " ", with: "").allSatisfy({ "|-:".contains($0) }) else { return nil }
        func cells(_ l: String) -> [String] {
            var t = l
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return [cells(lines[0])] + lines.dropFirst(2).map(cells)
    }

    static func parts(_ text: String) -> [Part] {
        var out: [Part] = []
        let chunks = text.components(separatedBy: "```")
        for (i, chunk) in chunks.enumerated() {
            if i % 2 == 1 {
                // первая строка блока — язык: он подписью над кодом
                var lines = chunk.components(separatedBy: "\n")
                var lang: String?
                if let first = lines.first, !first.contains(" ") {
                    lines.removeFirst()
                    let l = first.trimmingCharacters(in: .whitespaces)
                    if !l.isEmpty { lang = l }
                }
                let code = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                // ```visual — живая картинка; пока блок не закрыт (ответ ещё пишется), рисовать нечего
                if let l = lang?.lowercased(), Visuals.langs.contains(l) {
                    out.append(.visual(code, done: i < chunks.count - 1))
                } else if !code.isEmpty {
                    out.append(.code(code, lang: lang))
                }
            } else {
                // абзацы между блоками кода — одним куском: он рисуется и выделяется как один текст
                var run: [String] = []
                func flush() {
                    let s = run.joined(separator: "\n\n")
                    if !s.isEmpty { out.append(.prose(s)) }
                    run = []
                }
                for para in chunk.components(separatedBy: "\n\n") {
                    let s = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty else { continue }
                    // таблица может идти сразу под строкой текста, без пустой строки
                    let lines = s.components(separatedBy: "\n")
                    let isRow = { (l: String) in l.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
                    if let first = lines.firstIndex(where: isRow) {
                        let end = lines[first...].firstIndex(where: { !isRow($0) }) ?? lines.endIndex
                        if let rows = table(lines[first..<end].joined(separator: "\n")) {
                            let before = lines[..<first].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            let after = lines[end...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !before.isEmpty { run.append(before) }
                            flush()
                            out.append(.table(rows))
                            if !after.isEmpty { run.append(after) }
                        } else {
                            run.append(s)
                        }
                    } else {
                        run.append(s)
                    }
                }
                flush()
            }
        }
        return out
    }

    /// Разобранные куски: во время стрима текст меняется 30 раз в секунду, а готовые абзацы — нет
    @MainActor private static var parsed: [String: AttributedString] = [:]

    /// Строчная разметка куска без заголовков: блоки (заголовки, списки…) уже разобраны MarkdownBlocks
    @MainActor private static var inlined: [String: AttributedString] = [:]

    @MainActor static func inline(_ s: String) -> AttributedString {
        if let hit = inlined[s] { return hit }
        var out = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        detectLinks(&out)
        if inlined.count > 600 { inlined.removeAll() }
        inlined[s] = out
        return out
    }

    @MainActor static func markdown(_ s: String) -> AttributedString {
        if let hit = parsed[s] { return hit }
        let out = parseMarkdown(s)
        if parsed.count > 400 { parsed.removeAll() }
        parsed[s] = out
        return out
    }

    private static func parseMarkdown(_ s: String) -> AttributedString {
        // заголовки «## …» и «**…**» в начале строки — жирным, списки оставляем как есть
        let cleaned = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let l = String(line)
            if let r = l.range(of: #"^#{1,6}\s+"#, options: .regularExpression) { return "**" + l[r.upperBound...] + "**" }
            return l
        }.joined(separator: "\n")
        var out = (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        detectLinks(&out)
        return out
    }

    /// Голые адреса в тексте («https://…», «www.…») — тоже ссылки. Имена файлов вроде README.md ссылками не становятся,
    /// уже размеченные ссылки и код не трогаем
    static func detectLinks(_ a: inout AttributedString) {
        let plain = String(a.characters)
        guard plain.contains("://") || plain.lowercased().contains("www."),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        for m in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = m.url, let r = Range(m.range, in: plain) else { continue }
            let raw = plain[r].lowercased()
            guard raw.contains("://") || raw.hasPrefix("www.") else { continue }
            let lo = a.characters.index(a.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = a.characters.index(lo, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            if a[lo..<hi].runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) { continue }
            a[lo..<hi].link = url
        }
    }
}

/// Поле ввода (`Composer`): px-5 pt-1 pb-5, сверху плавный переход в фон; поле rounded-2xl border bg-card/60 p-3
struct Composer: View {
    @Bindable var app: AppModel
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let backend: Backend
    /// Ширина поля — своя, не зависит от «Ширины переписки» (Рома, 16.10)
    static let width: CGFloat = 640
    var agent = false
    /// Большое поле по центру экрана новой задачи (вариант A): выше, крупнее текст, папка — кнопкой
    var big = false
    /// Поле разговора рядом (разделённый экран)
    var controller: ChatController?
    /// Сообщить наружу, что поле в фокусе (шар приветствия «горячий»)
    var focusedOut: Binding<Bool>?
    /// Под полем — «Ответы могут быть неточными» (в переписке, не на пустом экране)
    var disclaimer = false

    @Environment(\.palette) private var p
    @State private var focused = false
    @State private var modelOpen = false
    @State private var effortOpen = false
    @State private var folderOpen = false
    @State private var modeOpen = false

    private var chat: ChatController { controller ?? app.chat }
    private var model: ChatModel { chat.conversation?.model ?? (agent ? app.defaultAgentModel : app.prefs.model) }
    private var effort: Effort { chat.conversation?.effort ?? (agent ? app.prefs.agentEffort ?? .high : app.prefs.effort) }
    /// Начатый разговор продолжается тем же движком: Claude не продолжит ход ChatGPT и наоборот
    private var models: [ChatModel] {
        let all = app.availableModels(for: backend)
        guard chat.conversation != nil else { return all }
        return all.filter { $0.isGPT == model.isGPT }
    }
    /// Агенту без папки отправлять нечего
    private var ready: Bool { !agent || chat.conversation != nil || app.agentFolder != nil }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    /// Набирают «@…» в начале — какие боты подходят (в разговоре самого бота не нужно)
    private var mentionHits: [Bot] {
        guard chat.conversation?.kind != .bot, draft.hasPrefix("@"), !draft.contains(" "), !draft.contains("\n") else { return [] }
        let q = draft.dropFirst().lowercased()
        // в группе — только её участники
        let pool = chat.conversation?.kind == .group ? (app.group(chat.conversation?.groupID).map(app.groupMembers) ?? []) : app.bots
        return pool.filter { q.isEmpty || $0.id.hasPrefix(q) || $0.name.lowercased().contains(q) }
    }
    private var inBot: Bool { chat.conversation?.kind == .bot }
    /// Позванный бот — чипом в его цвете в начале поля, «@id» из текста убран (как в Codex). ⌫ в пустом поле — убрать
    @State private var mentioned: Bot?
    /// Навык из «/» — тоже чипом; при отправке становится просьбой взять этот навык
    @State private var pickedSkill: Skill?
    @State private var slashIndex = 0

    /// Что предлагает «/»: действия Lumen и навыки из библиотеки Lumen (навыков Claude Code здесь нет)
    struct SlashItem: Identifiable {
        enum Kind { case action, skill }
        let id: String
        let kind: Kind
        let icon: String
        let note: String
    }

    /// Набирают команду: «/» в начале и ещё без пробела — меню видно, даже если ничего не подходит
    private var slashOpen: Bool { draft.hasPrefix("/") && !draft.contains(" ") && !draft.contains("\n") }

    private var slashItems: [SlashItem] {
        guard slashOpen else { return [] }
        let q = draft.dropFirst().lowercased()
        var all: [SlashItem] = []
        if !inGroup {
            all.append(SlashItem(id: agent ? "new" : "new", kind: .action, icon: "square-pen", note: agent ? "Новая задача" : "Новый чат"))
            if chat.conversation?.usesCLI == true && !chat.busy {
                all.append(SlashItem(id: "compact", kind: .action, icon: "layers", note: "Сжать разговор: пересказать старое и освободить место"))
            }
            all.append(SlashItem(id: "remember", kind: .action, icon: "brain", note: "Запомнить то, что напишешь дальше"))
            all.append(SlashItem(id: "browser", kind: .action, icon: "globe", note: app.browserOpen ? "Спрятать браузер" : "Открыть браузер сбоку"))
            all.append(SlashItem(id: "memory", kind: .action, icon: "book-text", note: "Открыть память"))
        }
        all += app.skills.map { SlashItem(id: $0.name, kind: .skill, icon: "book-open", note: $0.description) }
        return all.filter { q.isEmpty || $0.id.lowercased().hasPrefix(q) || $0.note.lowercased().contains(q) }
    }

    /// Выбрали строку «/»: действие — сразу, навык — чипом
    private func pickSlash(_ item: SlashItem) {
        draft = ""
        slashIndex = 0
        switch (item.kind, item.id) {
        case (.action, "new"): agent ? app.newAgentTask() : app.newChat()
        case (.action, "compact"): chat.compact()
        case (.action, "remember"): draft = "Запомни: "
        case (.action, "browser"): app.toggleBrowser()
        case (.action, "memory"): app.page = .memory
        case (.skill, _): pickedSkill = app.skills.first { $0.name == item.id }
        default: break
        }
        focused = true
    }

    /// «@id » в начале текста (выбрали из списка, вставили, нажали участника группы) — превратить в чип
    /// Файл бросили прямо на поле — оно вставило путь текстом («/var/folders/…/Снимок экрана….png»).
    /// Путь убираем из черновика, а файл прикрепляем как вложение (Рома, 19.10). Папки остаются текстом: агенту это путь.
    private func absorbDroppedFiles(old: String, new: String) {
        guard let ins = DroppedPaths.insertion(old: old, new: new) else { return }
        let fm = FileManager.default
        guard let urls = DroppedPaths.files(in: ins.text, exists: { p in
            var dir: ObjCBool = false
            return fm.fileExists(atPath: p, isDirectory: &dir) && !dir.boolValue
        }) else { return }
        let added = urls.compactMap(app.importAttachment)
        guard !added.isEmpty else { return }
        attachments.append(contentsOf: added)
        draft = ins.prefix + ins.suffix
    }

    private func absorbMention() {
        guard !inBot, mentioned == nil, draft.hasPrefix("@"), let space = draft.firstIndex(where: { $0 == " " || $0 == "\n" }) else { return }
        let id = String(draft[draft.index(after: draft.startIndex)..<space]).lowercased()
        let pool = inGroup ? (app.group(chat.conversation?.groupID).map(app.groupMembers) ?? []) : app.bots
        guard let b = pool.first(where: { $0.id == id }) else { return }
        mentioned = b
        draft = String(draft[draft.index(after: space)...])
    }

    /// Вложения, стоящие карточкой в тексте (остальные — в ряду над полем)
    private var inlineIDs: Set<String> { Set(FileMarks.ids(in: draft)) }

    private var inlineChips: [String: FieldChip] {
        var out: [String: FieldChip] = [:]
        for a in attachments where inlineIDs.contains(a.id) {
            let title = a.name.count > 28 ? String(a.name.prefix(26)) + "…" : a.name
            out[a.id] = FieldChip(id: "file:" + a.id, title: title, tint: p.glow, symbol: FileKind.of(a.url).icon)
        }
        return out
    }

    private var stripItems: Binding<[Attachment]> {
        Binding(
            get: { attachments.filter { !inlineIDs.contains($0.id) } },
            set: { new in
                let keep = Set(new.map(\.id)), inline = inlineIDs
                attachments.removeAll { !inline.contains($0.id) && !keep.contains($0.id) }
            })
    }

    /// Чипы в начале текста поля: позванный бот и выбранный навык
    private var fieldChips: [FieldChip] {
        var out: [FieldChip] = []
        if let b = mentioned { out.append(FieldChip(id: "bot:" + b.id, title: b.name, tint: BotColor.accent(b.hue), bot: b)) }
        if let sk = pickedSkill { out.append(FieldChip(id: "skill:" + sk.name, title: "/" + sk.name, tint: p.glow, symbol: "book-open")) }
        return out
    }

    /// Цвет поля: бот, в чьём разговоре мы, или позванный чипом
    private var tintBot: Bot? { currentBot ?? mentioned }
    private var currentBot: Bot? { inBot ? app.bot(chat.conversation?.botID) : nil }
    /// «Ресерч» на следующее сообщение: после отправки выключается
    @State private var research = false
    /// Репозитории GitHub, добавленные в это сообщение (таблетки у «+»)
    @State private var githubAdded: [GitHubAdded] = []
    @State private var botFolderOpen = false
    @State private var botEffortOpen = false

    /// Кому пишешь: знак и @имя в цвете бота
    private func botChip(_ b: Bot) -> some View {
        HStack(spacing: 6) {
            BotAvatar(bot: b, size: 18)
            Text("@\(b.id)").font(.geist(12, .medium)).foregroundStyle(BotColor.accent(b.hue))
        }
        .padding(.leading, 4).padding(.trailing, 8).frame(height: 26)
        .background(BotColor.faint(b.hue), in: Capsule())
        .overlay(Capsule().strokeBorder(BotColor.soft(b.hue)))
        .help(b.role)
    }

    /// Папка бота — меняется прямо здесь (как у агента), сразу для его следующего ответа
    private func botFolderPicker(_ b: Bot) -> some View {
        let current = b.folder.map { URL(fileURLWithPath: $0) }
        return PickerButton(open: $botFolderOpen) {
            Icon("folder", 14).foregroundStyle(BotColor.accent(b.hue))
            Text(current.map(AppModel.folderName) ?? "Своя папка").font(.geist(14))
        } panel: {
            PopoverPanel(title: "Где работает бот", width: 256) {
                PopoverOption(name: "Своя папка", note: "пустая, чужих файлов не видит", active: current == nil) {
                    Icon("folder", 16).foregroundStyle(p.mutedFg)
                } action: { setBotFolder(b, nil) }
                PopoverOption(name: "Мои файлы", note: "вся домашняя папка, ~", active: current.map(AppModel.isHome) ?? false) {
                    Icon("laptop", 16).foregroundStyle(p.mutedFg)
                } action: { setBotFolder(b, AppModel.home.path) }
                ForEach(app.recentFolders.filter { !AppModel.isHome($0) }, id: \.self) { f in
                    PopoverOption(name: f.lastPathComponent, note: f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                  active: f.standardizedFileURL.path == current?.standardizedFileURL.path) {
                        Icon("folder", 16).foregroundStyle(p.mutedFg)
                    } action: { setBotFolder(b, f.path) }
                }
                Button {
                    botFolderOpen = false
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Выбрать"
                    if panel.runModal() == .OK, let url = panel.url { setBotFolder(b, url.path) }
                } label: {
                    Text("Другая папка…").font(.geist(12)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(chat.busy)
    }

    private func botEffortPicker(_ b: Bot) -> some View {
        PickerButton(open: $botEffortOpen) {
            Text(b.effort.name).font(.geist(14))
        } panel: {
            PopoverPanel(title: "Сколько думать") {
                ForEach(Effort.allCases) { e in
                    PopoverOption(name: e.name, note: e.note, active: e == b.effort) { EmptyView() } action: {
                        var nb = b
                        nb.effort = e
                        app.saveBot(nb)
                        chat.refresh(app.botConversation(for: nb))
                        botEffortOpen = false
                    }
                }
            }
        }
        .disabled(chat.busy)
    }

    private func setBotFolder(_ b: Bot, _ path: String?) {
        var nb = b
        nb.folder = path
        app.saveBot(nb)
        if let path { app.rememberFolder(URL(fileURLWithPath: path)) }
        chat.refresh(app.botConversation(for: nb))
        botFolderOpen = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mentionHits.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(mentionHits) { b in
                        Button { draft = "@\(b.id) " } label: {
                            HStack(spacing: 10) {
                                BotAvatar(bot: b, size: 22)
                                Text("@\(b.id)").font(.geist(13, .medium)).foregroundStyle(BotColor.accent(b.hue))
                                Text(b.role).font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            }
            if !chat.openQueue.isEmpty { queueList }
            if !stripItems.wrappedValue.isEmpty { AttachmentStrip(items: stripItems) }
            // чипы бота и навыка лежат внутри текста — на одном уровне с буквами, ⌫ стирает их как символ
            ComposerTextView(
                text: $draft, chips: fieldChips, inline: inlineChips, palette: p,
                placeholder: mentioned.map { "Задача для «\($0.name)»" } ?? (agent ? "Опиши задачу · / — навыки агента" : (currentBot.map { "Напиши боту «\($0.name)»" } ?? (chat.conversation?.kind == .group ? "Написать группе · @id — ответит один" : "Просто напиши · / — команды и навыки"))),
                focused: $focused,
                // 16.5 / 1.5; растёт до 240 pt (9 строк), дальше листается
                minLines: big ? 4 : 1, maxLines: 9,
                // Enter — отправить, Shift+Enter — новая строка; в настройках можно наоборот: ⌘Enter — отправить, Enter — строка
                onReturn: { shift, command in
                    if app.prefs.sendWithCommand && slashItems.isEmpty {
                        if command { send(); return true }
                        return false
                    }
                    if shift { return false }
                    send()
                    return true
                },
                // стрелки и Tab — по меню «/»
                onArrow: { down in
                    guard !slashItems.isEmpty else { return false }
                    slashIndex = (slashIndex + (down ? 1 : -1) + slashItems.count) % slashItems.count
                    return true
                },
                onTab: {
                    guard slashItems.indices.contains(slashIndex) else { return false }
                    pickSlash(slashItems[slashIndex])
                    return true
                },
                onEscape: {
                    if slashOpen {
                        draft = ""
                        return true
                    }
                    // Esc — остановить ответ
                    guard chat.busy else { return false }
                    chat.stop()
                    return true
                },
                onRemoveChip: { id in
                    if id.hasPrefix("file:") {
                        let file = String(id.dropFirst(5))
                        draft = draft.replacingOccurrences(of: FileMarks.marker(file), with: "")
                        attachments.removeAll { $0.id == file }
                    } else if id.hasPrefix("bot:") { mentioned = nil } else { pickedSkill = nil }
                },
                onFiles: { providers in app.attach(providers) { attachments.append($0) } }
            )
            .onChange(of: draft) { old, new in
                // карточку стёрли ⌫ — вложение уходит вместе с ней
                let gone = Set(FileMarks.ids(in: old)).subtracting(FileMarks.ids(in: new))
                if !gone.isEmpty { attachments.removeAll { gone.contains($0.id) } }
                absorbDroppedFiles(old: old, new: new)
                absorbMention()
                if slashIndex >= slashItems.count { slashIndex = 0 }
            }
            .frame(minHeight: big ? 96 : 25, alignment: .topLeading) // одна строка, растёт с текстом (минимализм, 19.10)
            .padding(.bottom, 6)
            // один ряд: слева «+», папка и режим, справа модель, «сколько думать» и отправить
            // узкая область (браузер сбоку, спрятанная панель): кнопки не вылезают за край, а встают в два ряда
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    leftControls
                    Spacer(minLength: 8)
                    rightControls
                }
                .frame(height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) { leftControls; Spacer(minLength: 0) }.frame(height: 38)
                    HStack(spacing: 4) { Spacer(minLength: 0); rightControls }.frame(height: 38)
                }
            }
        }
        .padding(.top, 18).padding(.leading, 20).padding(.trailing, 12).padding(.bottom, 12)
        .background { glass }
        .animation(.easeOut(duration: 0.2), value: focused)
        // меню «/» — плавающим окном: над полем, а у большого поля новой задачи — под ним (сверху заголовок)
        .overlay(alignment: big ? .bottom : .top) {
            if slashOpen {
                // якорь нулевой высоты на краю поля: меню растёт от него наружу
                Color.clear.frame(height: 0)
                    .overlay(alignment: big ? .top : .bottom) {
                        slashMenu.padding(big ? .top : .bottom, 8)
                    }
                    .transition(.opacity)
            }
        }
        .zIndex(1)
        .onPasteCommand(of: [.fileURL, .png, .tiff, .jpeg]) { providers in app.attach(providers) { attachments.append($0) } }
        // метка в тексте без вложения (разговор сменился, вложение убрали) — лишняя
        .onChange(of: attachments.map(\.id)) {
            let clean = FileMarks.strip(draft, keeping: Set(attachments.map(\.id)))
            if clean != draft { draft = clean }
        }
        // ширина — как у колонки переписки (Рома, 17.10), не шире 700 (макет 21.10).
        // Без белой полосы-градиента над полем: она закрывала последние строки ответа
        .frame(maxWidth: big ? .infinity : min(700, ChatView.columnWidth(app: app, conversation: chat.conversation, agent: agent) - 72))
        .overlay(alignment: .bottom) {
            if disclaimer {
                Color.clear.frame(height: 0).overlay(alignment: .top) {
                    Text("Ответы могут быть неточными. Важное проверяй.").font(.geist(12.5)).foregroundStyle(p.faint)
                        .fixedSize().padding(.top, 10)
                }
            }
        }
        .padding(.leading, big ? 0 : 44).padding(.trailing, big ? 0 : 28).padding(.bottom, big ? 0 : (disclaimer ? 40 : 16)).padding(.top, big ? 0 : 8)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .onChange(of: focused) { _, f in focusedOut?.wrappedValue = f }
        // щелчок по имени папки в заголовке новой задачи — тот же выбор папки
        .onChange(of: app.folderPickerRequest) { if agent && chat.conversation == nil { folderOpen = true } }
        // щелчок по участнику группы справа — «@id » в начало поля
        .onChange(of: chat.mentionRequest) { _, m in
            guard let m else { return }
            if !draft.hasPrefix(m) { draft = m + draft }
            focused = true
            chat.mentionRequest = nil
        }
    }

    private var inGroup: Bool { chat.conversation?.kind == .group }

    /// Поле ввода (lumen-theme.css): фон сплошной `--composer-bg` — лучи и звёзды сквозь него не просвечивают, без размытия.
    /// Тёмная: кольцо 1px .09, светлая кромка сверху, тень 0 24 70 .38; в фокусе кольцо синее .42 и ореол 4px .10.
    /// Светлая: кольцо снаружи .09 и две мягкие тени. У бота — его цвет вместо синего
    @ViewBuilder private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let tint = tintBot.map { BotColor.accent($0.hue) } ?? p.glow
        let ring: Color = tintBot.map { focused ? BotColor.accent($0.hue).opacity(0.45) : BotColor.soft($0.hue) }
            ?? (focused ? tint.opacity(0.42) : p.borderBase.opacity(p.isLight ? 0.09 : 0.09))
        ZStack {
            shape.fill(p.composerFill)
                .shadow(color: p.isLight ? p.borderBase.opacity(focused ? 0.08 : 0.06) : .black.opacity(focused ? 0.45 : 0.38),
                        radius: p.isLight ? 15 : 35, y: p.isLight ? 10 : 24)
            if p.isLight { shape.fill(p.composerFill).shadow(color: p.borderBase.opacity(0.04), radius: 1, y: 1) }
            // ореол 4px в фокусе (0 0 0 4px)
            if focused { shape.inset(by: -2).stroke(tint.opacity(0.10), lineWidth: 4) }
            shape.strokeBorder(ring)
            if !p.isLight {
                // inset 0 1px 0 rgba(255,255,255,.05): светлая кромка по верху
                shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(focused ? 0.06 : 0.05), .clear],
                                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)))
            }
        }
        .allowsHitTesting(false)
    }

    /// Слева: «+», папка и режим агента, бот — каждая кнопка во всю подпись
    @ViewBuilder private var leftControls: some View {
        // как в Claude: «+» в левом нижнем углу — картинки и файлы
        PlusMenu(app: app, agent: agent, canPickFolder: agent && chat.conversation == nil, chat: chat, draft: $draft, attachments: $attachments,
                 research: $research, github: $githubAdded, showsTools: !inBot && !inGroup).fixedSize()
        // рядом с «+» — только то, что включено или добавлено в это сообщение: «Ресерч» и репозитории GitHub
        if !inBot && !inGroup && (research || !githubAdded.isEmpty) {
            ToolPills(research: $research, github: $githubAdded, removeGitHub: removeGitHub).fixedSize()
        }
        // агент: папка (единственная кнопка с рамкой) и «Режим» — в нём и режим, и «Ночь» (Рома, 21.10)
        if agent { folderPicker.fixedSize(); modeMenu.fixedSize(); modePills }
        if let b = currentBot { botChip(b).fixedSize(); botFolderPicker(b).fixedSize(); botEffortPicker(b).fixedSize() }
        ElsewherePill(app: app)
    }

    /// Справа: модель, «сколько думать», отправить
    @ViewBuilder private var rightControls: some View {
        // у бота модель задана в его паспорте
        if !inBot {
            modelPicker.fixedSize()
            effortPicker.fixedSize()
        }
        sendButton.padding(.leading, 6)
    }

    /// Очередь: что уйдёт после ответа — «Сейчас» (остановить ответ и отправить это) или убрать
    private var queueList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.claudeBusy(chat.conversation?.id) && !chat.busy ? "В очереди — уйдёт, когда Claude Code закончит" : "В очереди — уйдёт после ответа")
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            ForEach(chat.openQueue) { q in
                HStack(spacing: 8) {
                    Icon("clock", 14).foregroundStyle(p.mutedFg)
                    Text(q.text.isEmpty ? (q.attachments.first?.name ?? "Вложение") : q.text)
                        .tw(13, lh: 18).lineLimit(1)
                    if !q.attachments.isEmpty, !q.text.isEmpty {
                        Icon("paperclip", 12).foregroundStyle(p.mutedFg)
                    }
                    Spacer(minLength: 8)
                    Button { chat.sendNow(q.id) } label: { Text("Сейчас").tw(12, .medium, lh: 16).foregroundStyle(p.glow) }
                        .buttonStyle(.plain).help("Остановить ответ и отправить это")
                    Button { chat.unqueue(q.id) } label: { Icon("x", 12).foregroundStyle(p.mutedFg) }
                        .buttonStyle(.plain).help("Убрать из очереди")
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(p.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: R.md))
            }
        }
        .padding(.bottom, 4)
    }

    private func send() {
        // открыто меню «/» — Enter выбирает строку
        if slashItems.indices.contains(slashIndex) { pickSlash(slashItems[slashIndex]); return }
        // идёт ответ — сообщение встаёт в очередь (в группе — сразу в комнату)
        guard canSend, ready else { return }
        var text = FileMarks.readable(draft, names: Dictionary(attachments.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }))
        if let sk = pickedSkill { text = "Возьми навык «\(sk.name)»: " + text }
        if let b = mentioned { text = "@\(b.id) " + text }
        // «/что-то», что не наша команда, не уходит в claude командой: там свои навыки Claude Code
        if text.hasPrefix("/") { text = "\u{200B}" + text }
        chat.researchOnce = research && !inBot && !inGroup
        research = false
        githubAdded = []
        chat.send(text, attachments: attachments)
        draft = ""
        attachments = []
        mentioned = nil
        pickedSkill = nil
    }

    /// Меню «/»: «Команды» и «Навыки» разделами, значок в квадратике, выбранная строка подсвечена; ↑↓ Tab Enter.
    /// Плавает над полем, не выше 320 и листается — выбранная строка всегда видна
    /// Меню во всю ширину поля, как остальные всплывающие (макет 21.10): «/команда» синим, пояснение тихим.
    /// Ничего не подошло — сказать, как увидеть все
    @ViewBuilder private var slashMenu: some View {
        let items = slashItems
        Group {
            if items.isEmpty {
                Text("Такой команды нет. Сотри символы после /, чтобы увидеть все.")
                    .font(.geist(13)).foregroundStyle(p.mutedFg)
                    .padding(.horizontal, 17).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                                if Set(items.map(\.kind)).count > 1, i == 0 || items[i - 1].kind != it.kind {
                                    Text(it.kind == .action ? "Команды" : "Навыки").font(.geist(12, .medium)).foregroundStyle(p.faint)
                                        .padding(.horizontal, 11).padding(.top, i == 0 ? 4 : 10).padding(.bottom, 4)
                                }
                                Button { pickSlash(it) } label: {
                                    HStack(spacing: 12) {
                                        Text("/" + it.id).font(.geist(14, .medium)).foregroundStyle(p.accentSoft).lineLimit(1)
                                            .frame(minWidth: 88, alignment: .leading).layoutPriority(1)
                                        Text(it.note).font(.geist(13)).foregroundStyle(p.mutedFg).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .background(i == slashIndex ? p.borderBase.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(it.id)
                                .onHover { if $0 { slashIndex = i } }
                                .accessibilityAddTraits(i == slashIndex ? [.isSelected] : [])
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: min(320, CGFloat(items.count) * 34 + (Set(items.map(\.kind)).count > 1 ? 52 : 0) + 12))
                    .onChange(of: slashIndex) { _, i in if items.indices.contains(i) { proxy.scrollTo(items[i].id) } }
                }
            }
        }
        .popoverChrome()
    }

    /// `FolderPicker`: папка проекта; у начатой сессии папка уже не меняется
    private var folderPicker: some View {
        let started = chat.conversation != nil
        let current = chat.conversation?.folder.map { URL(fileURLWithPath: $0) } ?? app.agentFolder
        let extra = started ? (chat.conversation?.extraPaths ?? []).map { URL(fileURLWithPath: $0) } : app.agentExtraDirs
        return PickerButton(open: $folderOpen, bordered: true) {
            Icon("folder", 16).foregroundStyle(p.glow)
            Text((current.map(AppModel.folderName) ?? "Мои файлы") + (extra.isEmpty ? "" : " +\(extra.count)")).font(.geist(14))
        } panel: {
            PopoverPanel(title: started ? "Где работает задача" : "Где работать", width: 280) {
                if started {
                    // рабочая папка начатой задачи не меняется (в ней сессия claude), но доступ к другим — можно дать
                    PopoverOption(name: current.map(AppModel.folderName) ?? "Мои файлы", note: "рабочая папка — уже не сменить", active: true) {
                        Icon("folder", 16).foregroundStyle(p.glow)
                    } action: { folderOpen = false }
                } else {
                    PopoverOption(name: "Мои файлы", note: "вся домашняя папка, ~", active: current.map(AppModel.isHome) ?? true) {
                        Icon("laptop", 16).foregroundStyle(p.mutedFg)
                    } action: {
                        app.agentFolder = AppModel.home
                        folderOpen = false
                    }
                    ForEach(app.recentFolders.filter { !AppModel.isHome($0) }, id: \.self) { f in
                        PopoverOption(name: f.lastPathComponent, note: f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                      active: f.standardizedFileURL.path == current?.standardizedFileURL.path) {
                            Icon("folder", 16).foregroundStyle(p.mutedFg)
                        } action: {
                            app.agentFolder = f
                            folderOpen = false
                        }
                    }
                }
                if !extra.isEmpty {
                    Text("Ещё доступ").font(.geist(11, .medium)).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.top, 6)
                    ForEach(extra, id: \.self) { d in
                        HStack(spacing: 8) {
                            Icon("folder", 14).foregroundStyle(p.mutedFg)
                            Text(d.lastPathComponent).font(.geist(12)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button { removeExtra(d) } label: { Icon("x", 11).foregroundStyle(p.mutedFg) }.buttonStyle(.plain).help("Убрать доступ")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                }
                Button {
                    folderOpen = false
                    pickPaths()
                } label: {
                    IconLabel(text: "Папки или файлы… (можно несколько)", icon: "plus", size: 12).font(.geist(12)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(chat.busy)
    }

    /// Несколько папок и файлов сразу: папки — доступ агенту (первая у новой задачи — рабочая), файлы — вложениями
    private func pickPaths() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Папки — агент сможет в них работать; файлы — прикрепятся к сообщению"
        guard panel.runModal() == .OK else { return }
        let files = chat.addPaths(panel.urls)
        attachments += files.compactMap(app.importAttachment)
    }

    /// Убрать репозиторий GitHub из сообщения: у агента — доступ к его папке, у чата — вложенные README и список файлов
    private func removeGitHub(_ g: GitHubAdded) {
        githubAdded.removeAll { $0.id == g.id }
        if agent { removeExtra(g.folder) } else { attachments.removeAll { g.attachmentIDs.contains($0.id) } }
    }

    private func removeExtra(_ d: URL) {
        if var c = chat.conversation {
            c.extraPaths?.removeAll { $0 == d.path }
            chat.setExtraPaths(c.extraPaths ?? [])
        } else {
            app.agentExtraDirs.removeAll { $0 == d }
        }
    }

    /// `ModelPicker`: Sparkles text-glow + название text-xs medium + стрелка
    private var modelPicker: some View {
        PickerButton(open: $modelOpen, edge: .trailing) {
            Text(model.name).font(.geist(14))
        } panel: {
            ListboxPanel(items: models.map { m in
                ListboxPanel.Item(id: m, name: m.name, note: m.note, gap: m == ChatModel.gpt.first && models.contains(where: { !$0.isGPT }))
            }, selected: model, width: 260) { m in
                chat.set(model: m)
                modelOpen = false
            }
        }
        .disabled(chat.busy)
        .help("Модель")
    }

    /// Режим агента: как в Claude Code, Shift+Tab — следующий
    private var mode: AgentMode { chat.conversation?.mode ?? app.prefs.agentMode }

    /// «Режим ▾» (Рома, 21.10): как работает агент (План, Спрашивать, Принимать правки, Авто, Обход) и «Ночь» — в одном меню.
    /// Shift+Tab — следующий режим, как раньше
    private var modeMenu: some View {
        PickerButton(open: $modeOpen) {
            Icon("sliders-horizontal", 16).foregroundStyle(p.mutedFg)
            Text("Режим").font(.geist(14))
        } panel: {
            AgentModePanel(app: app, mode: mode, modes: app.prefs.visibleModes) { m in
                chat.set(mode: m)
            }
        }
        .background {
            Button("") {
                let all = app.prefs.visibleModes
                chat.set(mode: all[((all.firstIndex(of: mode) ?? -1) + 1) % all.count])
            }
            .keyboardShortcut(.tab, modifiers: .shift).opacity(0)
        }
        .help("Режим: \(mode.name.lowercased()) — \(mode.note)")
    }

    /// Что включено сейчас — плашками рядом с «Режимом»: режим, если он не обычный «Авто», и «Ночь до …»
    @ViewBuilder private var modePills: some View {
        if mode != .auto { ModePill(text: mode.name, icon: mode.icon).fixedSize() }
        let night = app.prefs.night
        if night.active() { ModePill(text: "Ночь до " + (night.until.map { Night.clock($0) } ?? night.wake), icon: "moon").fixedSize() }
    }

    /// `EffortPicker`: столбики уровня + название text-xs
    private var effortPicker: some View {
        PickerButton(open: $effortOpen, edge: .trailing) {
            Text(effort.name).font(.geist(14))
        } panel: {
            ListboxPanel(items: Effort.allCases.map { ListboxPanel.Item(id: $0, name: $0.name, note: $0.note) }, selected: effort, width: 260) { e in
                chat.set(effort: e)
                effortOpen = false
            }
        }
        .disabled(chat.busy)
        .help("Сколько думать")
    }

    @ViewBuilder private var sendButton: some View {
        if (chat.busy || app.claudeBusy(chat.conversation?.id)) && !inGroup && canSend {
            // ответ идёт, а в поле уже есть следующее — в очередь (↩ делает то же)
            Button(action: send) {
                HStack(spacing: 6) {
                    Icon("clock", 12)
                    Text("В очередь").font(.geist(13, .medium))
                }
                .foregroundStyle(p.orbSpec ? .white : p.onGlow)
                .padding(.horizontal, 14).frame(height: 38)
                .background(p.accent, in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(chat.busy ? "Отправится сам, когда Lumen закончит · ↩" : "Отправится сам, когда Claude Code закончит · ↩")
            .padding(.trailing, 4)
        }
        if chat.busy && !(inGroup && canSend) {
            // идёт ответ — круг цвета текста с тёмным квадратиком
            Button { chat.stop() } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.background)
                    .frame(width: 12, height: 12)
                    .frame(width: 38, height: 38)
                    .background(p.foreground, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .help("Остановить · Esc или ⌘.")
            .accessibilityLabel("Остановить ответ")
        } else if !(app.claudeBusy(chat.conversation?.id) && canSend) {
            let on = canSend && ready
            Button(action: send) {
                Icon("arrow-up", 18)
                    // у «Люмена» — белая стрелка на синем шаре из CSS; у других тем плоский круг цвета света, стрелка контрастная
                    .foregroundStyle(on ? (currentBot != nil || p.orbSpec ? .white : p.onGlow) : p.faint)
                    .frame(width: 38, height: 38)
                    .background {
                        if on {
                            // есть что отправить — маленький шар (у бота — его цвет)
                            if let b = currentBot {
                                Circle().fill(BotColor.accent(b.hue))
                            } else if p.orbSpec {
                                MiniOrbFill()
                            } else {
                                Circle().fill(p.accent)
                            }
                        } else {
                            Circle().fill(p.borderBase.opacity(0.06)).overlay(Circle().strokeBorder(p.borderBase.opacity(0.07)))
                        }
                    }
                    .shadow(color: on && (currentBot != nil || p.orbSpec) ? (currentBot.map { BotColor.accent($0.hue) } ?? p.accent).opacity(0.38) : .clear, radius: 9, y: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            // пустое поле — нечего отправлять: кнопка тихая и не нажимается
            .disabled(!on)
            .animation(.easeOut(duration: 0.14), value: on)
            .help(!ready ? "Сначала выбери папку проекта" : (canSend ? "Отправить · ↩" : "Напиши сообщение"))
            .accessibilityLabel("Отправить")
        }
    }
}

/// Кнопка под полем ввода, открывает меню над собой (макет 21.10): высота 34, скругление 10, подпись 14,
/// стрелка 13 тихим цветом. Меню — плавающее, прижато к краю кнопки; Esc или щелчок мимо закрывают его
struct PickerButton<Label: View, Panel: View>: View {
    @Binding var open: Bool
    /// Кнопка с рамкой (папка в большом поле новой задачи)
    var bordered = false
    /// К какому краю кнопки прижато меню: у кнопок справа — к правому
    var edge: HorizontalAlignment = .leading
    @ViewBuilder let label: Label
    @ViewBuilder let panel: Panel

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    /// Меню только что закрыл щелчок мимо — тот же щелчок по кнопке не должен открыть его снова
    @State private var closedAt = Date.distantPast

    var body: some View {
        Button {
            if Date().timeIntervalSince(closedAt) > 0.35 { open.toggle() }
        } label: {
            HStack(spacing: 6) {
                label
                Icon("chevron-down", 13).foregroundStyle(p.faint)
            }
            // все подписи под полем одного цвета и веса; ярче — под курсором и пока открыто (минимализм, 19.10)
            .foregroundStyle(hover || open ? p.foreground : p.textControl)
            .padding(.horizontal, 10).frame(height: 34)
            .background(hover || open ? p.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(bordered ? p.borderBase.opacity(0.10) : .clear))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityValue(open ? "открыто" : "закрыто")
        .overlay(alignment: Alignment(horizontal: edge, vertical: .top)) {
            if open {
                // над кнопкой, с зазором 8: якорь нулевой высоты по верху кнопки, меню растёт от него вверх
                Color.clear.frame(width: 0, height: 0)
                    .overlay(alignment: Alignment(horizontal: edge, vertical: .bottom)) {
                        panel
                            .environment(\.palette, p)
                            .popoverChrome()
                            .background(DismissMonitor {
                                open = false
                                closedAt = Date()
                            })
                            .fixedSize()
                            .padding(.bottom, 8)
                    }
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: open)
        .zIndex(open ? 10 : 0)
    }
}

/// Пять столбиков, закрашены до уровня — как индикатор сигнала (`EffortBars`)
struct EffortBars: View {
    let level: Int

    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<Effort.allCases.count, id: \.self) { i in
                Capsule().fill(i <= level ? p.glow : p.foreground.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .frame(height: 14, alignment: .bottom)
    }
}

/// Название разговора по центру шапки: 13.5 pt, средний вес, длинное — с многоточием. Щелчок — меню (переименовать, перенести,
/// удалить), у названия при наведении — шеврон. В проекте: «Проект / Разговор», имя проекта — ссылка на него
struct HeaderTitle: View {
    let text: String
    let project: Project?
    @Binding var editing: Bool
    /// nil — бот или группа: просто имя, без меню
    let conversation: Conversation?
    @Bindable var app: AppModel
    let onMenu: (CGPoint) -> Void

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var strong: Color { p.foreground }
    private var soft: Color { p.mutedFg }
    private var faint: Color { p.faint }

    var body: some View {
        HStack(spacing: 6) {
            if let project, !editing {
                Button { app.page = .project(project.id) } label: {
                    Text(project.name).tw(13.5, .medium, lh: 18).foregroundStyle(soft).lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Открыть проект")
                Text("/").tw(13.5, lh: 18).foregroundStyle(faint)
            }
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain).tw(13.5, .medium, lh: 18).foregroundStyle(strong)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .frame(maxWidth: 320)
                    .onSubmit { commit() }
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, f in if !f { editing = false } }
                    .onAppear { draft = text; focused = true }
            } else if conversation != nil {
                HStack(spacing: 6) {
                    Text(text).tw(13.5, .medium, lh: 18).foregroundStyle(strong).lineLimit(1).truncationMode(.tail)
                    Icon("chevron-down", 12).foregroundStyle(hover ? soft : faint)
                }
                .contentShape(Rectangle())
                .overlay {
                    GeometryReader { g in
                        Color.clear.contentShape(Rectangle()).onTapGesture {
                            let f = g.frame(in: .global)
                            onMenu(CGPoint(x: f.midX - 110, y: f.maxY + 8))
                        }
                    }
                }
                .onHover { hover = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Название разговора: \(text)")
                .accessibilityHint("Открывает меню разговора")
                .accessibilityAddTraits(.isButton)
            } else {
                Text(text).tw(13.5, .medium, lh: 18).foregroundStyle(strong).lineLimit(1).truncationMode(.tail)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private func commit() {
        if let c = conversation { app.renameChat(c, draft) }
        editing = false
    }
}

/// Под сообщением в разговоре бота: откуда его позвали (щелчок — открыть тот чат)
private struct ViaChip: View {
    let via: Via
    let app: AppModel?

    @Environment(\.palette) private var p

    var body: some View {
        Button {
            if let id = via.conversationID, let c = app?.conversations.first(where: { $0.id == id }) { app?.openChat(c) }
        } label: {
            HStack(spacing: 4) {
                if let why = via.autoReason {
                    // отправил сам Lumen за человека (утро, «тебя не было рядом», «лимит сбросился»)
                    Icon("sparkles", 11)
                    Text("отправил Lumen: \(why)").lineLimit(1)
                } else {
                    Icon("at-sign", 11)
                    Text(via.fromBot ? "позвал \(via.title)" : "из чата «\(via.title)»").lineLimit(1)
                }
            }
            .tw(11, lh: 14).foregroundStyle(p.mutedFg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(via.conversationID == nil)
        .help(via.conversationID == nil ? "" : "Открыть тот чат")
    }
}

/// Где ещё Lumen сейчас отвечает (писать здесь можно и так): живая точка и название, щелчок — открыть
private struct ElsewherePill: View {
    let app: AppModel

    @Environment(\.palette) private var p
    @State private var pulse = false
    @State private var hover = false

    var body: some View {
        let others = app.chat.turns.values.map(\.conversation).filter { $0.id != app.chat.conversation?.id }
            .sorted { $0.title < $1.title }
        if let first = others.first {
            Button { app.openChat(first) } label: {
                HStack(spacing: 7) {
                    Circle().fill(p.glow).frame(width: 6, height: 6)
                        .shadow(color: p.glow.opacity(pulse ? 0.9 : 0.2), radius: pulse ? 5 : 1)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                    Text(others.count == 1 ? "Ещё отвечаю: «\(first.title)»" : "Ещё отвечаю в \(others.count) разговорах")
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.geist(12)).foregroundStyle(hover ? p.foreground : p.mutedFg)
                .padding(.horizontal, 10).frame(height: 26)
                .background(p.glow.opacity(hover ? 0.12 : 0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(p.glow.opacity(0.22)))
                .frame(maxWidth: 150, alignment: .leading)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .onHover { hover = $0 }
            .help(others.map(\.title).joined(separator: "\n") + "\nЩелчок — открыть")
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }
}

/// Подсказки под полем на пустом экране: компактные пилюли в ряд по центру, со значком; при наведении — светятся
struct StartChips: View {
    let items: [String]
    var icons: [String] = ["lightbulb"]
    var tint: Color
    let pick: (String) -> Void

    @Environment(\.palette) private var p

    var body: some View {
        if items.contains(where: { $0.count > 34 }) {
            // длинные — списком под полем: весь текст виден, строки тонко разделены
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { i, text in
                    if i > 0 { p.border.frame(height: 1).padding(.horizontal, 14) }
                    Row(text: text, icon: icons[i % max(1, icons.count)], tint: tint) { pick(text) }
                }
            }
            .padding(.horizontal, 10)
        } else {
            CenterFlow(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element) { i, text in
                    Chip(text: text, icon: icons[i % max(1, icons.count)], tint: tint) { pick(text) }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private struct Row: View {
        let text: String
        let icon: String
        let tint: Color
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Icon(icon, 14).foregroundStyle(hover ? tint : p.mutedFg)
                    Text(text).font(.geist(13.5)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.72))
                    Spacer(minLength: 8)
                    Icon("arrow-up", 12).rotationEffect(.degrees(45)).foregroundStyle(tint).opacity(hover ? 1 : 0)
                }
                .padding(.horizontal, 14).frame(height: 42)
                .background(hover ? tint.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
    }

    private struct Chip: View {
        let text: String
        let icon: String
        let tint: Color
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 7) {
                    Icon(icon, 13).foregroundStyle(hover ? tint : p.mutedFg)
                    Text(text).font(.geist(13)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.75))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .frame(maxWidth: 320)
                .background(hover ? tint.opacity(0.08) : p.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(hover ? tint.opacity(0.35) : p.border))
                .contentShape(RoundedRectangle(cornerRadius: R.lg))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// Перенос по строкам с выравниванием каждой строки по центру
struct CenterFlow: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            let w = min(s.width, width)
            if x > 0 && x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, CGSize(width: w, height: s.height)))
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 640
        let rs = rows(subviews, width: width)
        let h = rs.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + spacing * CGFloat(max(0, rs.count - 1))
        return CGSize(width: width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowW = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rowH = row.map(\.1.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowW) / 2
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowH + spacing
        }
    }
}


/// Правая половина окна, пока тянут разговор: отпусти — откроется рядом
struct SplitDropZone: View {
    @Bindable var app: AppModel
    @Environment(\.palette) private var p
    @State private var over = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                p.background.opacity(over ? 0.85 : 0.6)
                VStack(spacing: 10) {
                    Icon("panel-right", 28).foregroundStyle(p.glow)
                    Text("Отпусти — откроется рядом").tw(15, .medium, lh: 20)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(over ? 0.8 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(12))
            .frame(width: g.size.width / 2)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .dropDestination(for: String.self) { items, _ in
                guard let c = app.dropped(items) else { return false }
                app.openSplit(c)
                return true
            } isTargeted: { over = $0 }
        }
    }
}

/// Таблица из ответа: шапка жирным, строки через тонкие линии, ячейки с разметкой; широкая — листается вбок.
/// Ширина каждой колонки считается по тексту и фиксируется: у ячейки с известной шириной текст переносится правильно,
/// и строка растёт по самой высокой ячейке. Без этого (Grid с ленивой шириной) переносы считались после высоты строки,
/// и длинные ячейки наезжали на соседние строки (Рома, 19.10).
struct MarkdownTable: View {
    let rows: [[String]]

    @Environment(\.palette) private var p

    static let minColumn: CGFloat = 80, maxColumn: CGFloat = 340, padding: CGFloat = 12

    /// Ширина колонки: самая длинная ячейка одной строкой, но не уже minColumn и не шире maxColumn (дальше — перенос).
    /// Считаем жирным шрифтом: он шире обычного, поэтому ячейка с **жирным** не обрежется.
    static func columnWidths(_ rows: [[String]]) -> [CGFloat] {
        let cols = rows.map(\.count).max() ?? 0
        let font = NSFont(name: "Geist-SemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        return (0..<cols).map { j in
            var widest: CGFloat = 0
            for row in rows where j < row.count {
                let plain = String(RichText.markdown(row[j]).characters)
                widest = max(widest, (plain as NSString).size(withAttributes: [.font: font]).width)
            }
            return min(maxColumn, max(minColumn, ceil(widest) + 2 * padding + 6))
        }
    }

    /// Если таблица шире места под ответом — сначала сжимаем самые широкие колонки (текст в них переносится),
    /// а вбок листаем, только когда и так тесно (все колонки по floor)
    static func fitted(_ widths: [CGFloat], to available: CGFloat, floor: CGFloat = 130) -> [CGFloat] {
        let total = widths.reduce(0, +)
        guard available > 0, total > available else { return widths }
        let spare = widths.map { max(0, $0 - floor) }
        let room = spare.reduce(0, +)
        guard room > 0 else { return widths }
        let k = min(1, (total - available) / room)
        return zip(widths, spare).map { $0 - $1 * k }
    }

    @State private var available: CGFloat = 0

    var body: some View {
        let natural = Self.columnWidths(rows)
        let widths = Self.fitted(natural, to: available)
        let total = widths.reduce(0, +)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(widths.enumerated()), id: \.offset) { j, w in
                            Text(RichText.markdown(j < row.count ? row[j] : ""))
                                .chatTw(14, lh: 21).fontWeight(i == 0 ? .semibold : .regular)
                                .textSelection(.enabled)
                                .frame(width: w - 2 * Self.padding, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Self.padding).padding(.vertical, 8)
                        }
                    }
                    .frame(width: total, alignment: .leading)
                    .background(i == 0 ? p.foreground.opacity(0.04) : .clear)
                    if i < rows.count - 1 { p.border.frame(width: total, height: 1) }
                }
            }
        }
        // узкая таблица не растягивается на всю ширину ответа; широкая сначала сжимается, потом листается вбок
        .frame(maxWidth: natural.reduce(0, +), alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
}

/// Следит за прокруткой переписки (macOS 15+): у низа ли она. Состояние меняется только на границе —
/// иначе переписка перерисовывалась бы на каждом шаге прокрутки и лагала.
/// И держит низ: переписка выросла (план, шаги, живая строка — не только новые сообщения и текст) или окно переписки
/// стало ниже (выросло поле ввода), а человек был внизу — `follow` возвращает к низу. Без этого всё новое уезжало под поле,
/// и казалось, что переписку подняло вверх (Рома, 19.10). Отлистал вверх читать — не трогаем.
struct ScrollTracking: ViewModifier {
    @Binding var atBottom: Bool
    var follow: () -> Void = {}

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                // [расстояние до низа, высота окна, высота переписки]; «внизу» с запасом в обе стороны, чтобы на границе не дёргалось
                .onScrollGeometryChange(for: [CGFloat].self) { g in
                    [g.contentSize.height - (g.contentOffset.y + g.containerSize.height), g.containerSize.height, g.contentSize.height]
                } action: { old, new in
                    if old.count == 3, atBottom, new[2] > old[2] + 0.5 || abs(new[1] - old[1]) > 0.5 {
                        follow()
                        return
                    }
                    let gap = new[0]
                    if atBottom && gap > 160 { atBottom = false } else if !atBottom && gap < 40 { atBottom = true }
                }
        } else {
            content
        }
    }
}

/// Прокручена ли переписка дальше `threshold` pt от верха (macOS 15+; на 14 шапка просто остаётся прозрачной)
struct ScrolledPast: ViewModifier {
    @Binding var scrolled: Bool
    let threshold: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > threshold
            } action: { _, new in
                if scrolled != new { scrolled = new }
            }
        } else {
            content
        }
    }
}

/// Позванный бот за работой: имя в его цвете, шаги (идущий — с точками и временем) и текст, пока пишется
struct LiveBotWork: View {
    let work: LiveWork
    let bot: Bot?

    @Environment(\.palette) private var p

    var body: some View {
        let tint = bot.map { BotColor.accent($0.hue) } ?? p.glow
        VStack(alignment: .leading, spacing: 12) {
            Text("@\(work.bot)\(bot.map { " · \($0.name)" } ?? "")").tw(12, .medium, lh: 16).foregroundStyle(tint)
            let pieces = AnswerPiece.layout(text: work.text, steps: work.steps)
            if pieces.isEmpty {
                HStack(spacing: 10) {
                    DotsSpinner(color: tint, bot: bot)
                    Text("\(bot?.name ?? "Бот") думает…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(tint)
                }
            }
            ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                let last = i == pieces.count - 1
                switch piece {
                case .text(let t): RichText(text: t, caret: last)
                case .steps(let s): StepsView(steps: s, live: last ? (work.started, tint) : nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension String {
    /// «Запускает swift test» → «запускает swift test»
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// Плашка включённого режима у «Режима»: синий текст на синей подложке, не красная
private struct ModePill: View {
    let text: String
    let icon: String

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 5) {
            Icon(icon, 12)
            Text(text).font(.geist(12.5, .medium))
        }
        .foregroundStyle(p.accentSoft)
        .padding(.horizontal, 10).frame(height: 28)
        .background(p.accentTint, in: Capsule())
    }
}

/// Меню «Режим»: режимы агента строками с пояснением (выбранный — с галочкой) и «Ночь» — с переключателем.
/// Рискованное («Обход», «Ночь» — без вопросов и разрешений) сначала переспрашивает прямо здесь
struct AgentModePanel: View {
    @Bindable var app: AppModel
    let mode: AgentMode
    let modes: [AgentMode]
    let set: (AgentMode) -> Void

    @Environment(\.palette) private var p
    /// Что ждёт подтверждения: режим «Обход» или включение «Ночи»
    @State private var confirm: Confirm?

    enum Confirm: Equatable { case bypass, night }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Как работает агент · Shift+Tab — следующий").font(.geist(12.5)).foregroundStyle(p.mutedFg)
                .padding(.horizontal, 11).padding(.top, 6).padding(.bottom, 6)
            ForEach(modes) { m in
                row(icon: m.icon, name: m.name, note: Self.sentence(m.note), selected: m == mode) {
                    if m == .bypassPermissions && mode != .bypassPermissions { confirm = .bypass } else { set(m); confirm = nil }
                }
                if confirm == .bypass && m == .bypassPermissions {
                    confirmBox("Агент будет менять файлы и запускать команды без вопросов. Включить?") { set(.bypassPermissions) }
                }
            }
            p.line.frame(height: 1).padding(.vertical, 6).padding(.horizontal, 4)
            nightRow
        }
        .padding(6)
        .frame(width: 360)
        .animation(.easeOut(duration: 0.15), value: confirm)
    }

    /// «спрашивает каждую правку» → «Спрашивает каждую правку.»
    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private func row(icon: String, name: String, note: String, selected: Bool, action: @escaping () -> Void) -> some View {
        ModeRow(icon: icon, name: name, note: note, selected: selected, action: action)
    }

    /// «Ночь»: до утра без вопросов и разрешений; утро — время, к которому агент отчитается
    @ViewBuilder private var nightRow: some View {
        let night = app.prefs.night
        let on = night.active()
        HStack(alignment: .top, spacing: 12) {
            Icon("moon", 16).foregroundStyle(on ? p.glow : p.mutedFg).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(on ? "Ночь до " + (night.until.map { Night.clock($0) } ?? night.wake) : "Ночь").font(.geist(14, .medium))
                Text("До утра без вопросов и разрешений. Мак не засыпает, кончится лимит — ждёт и продолжает, утром — отчёт.")
                    .font(.geist(12.5)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            LSwitch(isOn: Binding(get: { on }, set: { want in
                if want { confirm = .night } else { app.endNight(morning: false); confirm = nil }
            }))
            .padding(.top, 2)
            .accessibilityLabel("Ночь")
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        if !on {
            HStack(spacing: 4) {
                Text("Утро в").font(.geist(12.5)).foregroundStyle(p.mutedFg).fixedSize().padding(.trailing, 2)
                // время целиком, без обрезки: короткие кнопки в ряд (Рома, 19.10)
                ForEach(["05:00", "06:00", "07:00", "08:00", "09:00"], id: \.self) { t in
                    Button { app.update { $0.night.wake = t } } label: {
                        Text(t).font(.geist(12.5)).monospacedDigit().fixedSize()
                            .foregroundStyle(night.wake == t ? p.foreground : p.mutedFg)
                            .padding(.horizontal, 6).frame(height: 26)
                            .background(night.wake == t ? p.hover : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 41).padding(.bottom, 6)
        }
        if confirm == .night {
            confirmBox("До \(night.wake) агент работает без вопросов и разрешений. Включить?") { app.startNight() }
        }
    }

    /// Переспросить прямо в меню: значок предупреждения, вопрос, «Отмена» и «Включить»
    private func confirmBox(_ text: String, ok: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Icon("triangle-alert", 14).foregroundStyle(Color(hex: 0xF2766B)).padding(.top, 1)
                Text(text).font(.geist(13)).foregroundStyle(p.foreground).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Spacer()
                LButton(title: "Отмена", kind: .ghost, small: true) { confirm = nil }.fixedSize()
                LButton(title: "Включить", kind: .glow, small: true) { ok(); confirm = nil }.fixedSize()
            }
        }
        .padding(12)
        .background(p.hover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 4).padding(.vertical, 4)
        .transition(.opacity)
    }
}

/// Строка режима: значок, название, пояснение, галочка у выбранного
private struct ModeRow: View {
    let icon: String
    let name: String
    let note: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Icon(icon, 16).foregroundStyle(selected ? p.glow : p.mutedFg).frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.geist(14, .medium)).foregroundStyle(p.foreground)
                    Text(note).font(.geist(12.5)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected { Icon("check", 16).foregroundStyle(p.glow).padding(.top, 2) }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(hover ? p.borderBase.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}


/// Верх переписки растворяется под шапкой: прозрачная маска вместо плашки, у которой был бы край (шов на фоне со звёздами)
struct HeaderFade: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.45), .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                Color.black
            }
        }
    }
}
