import AppKit
import LumenCore
import SwiftUI

// Боты (`pages/bots-page.tsx`, `pages/bot-page.tsx`): каталог карточками, конструктор, паспорт.
// Только то, что работает: без навыков, расписаний, облака и групп — их ещё нет.

/// Знак бота — его капля (1.5): форма, лицо и цвет свои у каждого. Lumen — сфера, бот — капля с глазами:
/// в ленте сразу видно, кто говорит. В списках капля стоит, пока бот работает — живая.
struct BotAvatar: View {
    let look: BlobLook
    var size: CGFloat = 28
    var anim: BlobAnim = .idle
    var animated = false

    init(bot: Bot, size: CGFloat = 28, anim: BlobAnim = .idle, animated: Bool = false) {
        look = bot.blobLook
        self.size = size
        self.anim = anim
        self.animated = animated
    }

    init(look: BlobLook, size: CGFloat = 28, animated: Bool = false) {
        self.look = look
        self.size = size
        self.animated = animated
    }

    var body: some View {
        // сама капля занимает ~72% своего квадрата — рисуем крупнее, чтобы она заполняла место значка
        BlobView(look: look, anim: anim, size: size * 1.32, animated: animated)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Цвет бота по оттенку (в макете oklch(0.8 0.12 h) — здесь близкий HSB)
enum BotColor {
    static func accent(_ h: Double) -> Color { Color(hue: h / 360, saturation: 0.42, brightness: 0.93) }
    static func soft(_ h: Double) -> Color { accent(h).opacity(0.14) }
    static func faint(_ h: Double) -> Color { accent(h).opacity(0.06) }
    static func tileTop(_ h: Double) -> Color { Color(hue: h / 360, saturation: 0.55, brightness: 0.42) }
    static func tileBottom(_ h: Double) -> Color { Color(hue: h / 360, saturation: 0.45, brightness: 0.2) }
}

// MARK: все боты

struct BotsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(title: "Боты", lead: "Агенты под одну роль. Позови любого в чате через @ — Lumen передаст ему задачу. Всё, что вне роли, у бота отрезано в коде.") {
            LButton(title: "Создать бота", icon: "plus", kind: .primary) { app.page = .botEditor(nil) }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    if !working.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            GroupTitle(text: "Работают", aside: "\(working.count) сейчас")
                            VStack(spacing: 8) {
                                ForEach(working, id: \.0.id) { b, from in WorkingRow(bot: b, from: from) { app.openBot(b.id) } }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        GroupTitle(text: "Все", aside: app.bots.isEmpty ? nil : Plural.bots(app.bots.count))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(app.bots) { b in BotCard(app: app, bot: b) }
                            NewBotTile { app.page = .botEditor(nil) }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
    }

    /// Кто сейчас работает: позван через @ из чата или идёт ход в его разговоре
    private var working: [(Bot, String)] {
        app.bots.compactMap { b in
            if let from = app.botRuns[b.id] { return (b, "позвали из «\(from)»") }
            if app.chat.turns.values.contains(where: { $0.conversation.kind == .bot && $0.conversation.botID == b.id }) { return (b, "в своём разговоре") }
            return nil
        }
    }

    private struct WorkingRow: View {
        let bot: Bot
        let from: String
        let open: () -> Void

        @Environment(\.palette) private var p

        var body: some View {
            Button(action: open) {
                HStack(spacing: 14) {
                    BotAvatar(bot: bot, size: 34, anim: .orbit, animated: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bot.name).tw(14, .medium, lh: 20)
                        Text(from).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                    }
                    Spacer()
                    LiveDot(color: BotColor.accent(bot.hue))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(BotColor.faint(bot.hue), in: RoundedRectangle(cornerRadius: R.xl))
                .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(BotColor.soft(bot.hue)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct BotCard: View {
    @Bindable var app: AppModel
    let bot: Bot

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                BotAvatar(bot: bot, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot.name).tw(14, .medium, lh: 20).lineLimit(1)
                    Text("@\(bot.id)").tw(12, lh: 16).foregroundStyle(BotColor.accent(bot.hue))
                }
                Spacer(minLength: 0)
                GeometryReader { g in
                    let f = g.frame(in: .global)
                    DotsButton { app.showBotMenu(bot, at: CGPoint(x: f.minX, y: f.maxY + 4)) }
                }
                .frame(width: 26, height: 26)
                .opacity(hover ? 1 : 0)
            }
            Text(bot.role.isEmpty ? "Роль не описана" : bot.role)
                .tw(14, lh: 20).foregroundStyle(p.foreground.opacity(0.8)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            HStack(spacing: 6) {
                let blocked = BotPermissions.blocked(bot).count
                Chip(text: "\(blocked) запрещено", icon: "lock")
                Chip(text: bot.model.name, icon: nil)
            }
            .padding(.top, 12)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                LButton(title: copied ? "Скопировано" : "Позвать", icon: copied ? "check" : "at-sign", kind: .ghost, small: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("@\(bot.id) ", forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .help("Скопировать @\(bot.id) — вставь в любом чате")
            }
        }
        .padding(16)
        .frame(minHeight: 196, alignment: .top)
        .background(alignment: .topTrailing) {
            Circle().fill(BotColor.faint(bot.hue)).frame(width: 160, height: 160).blur(radius: 30).offset(x: 60, y: -60)
                .opacity(hover ? 1 : 0.6)
        }
        .background(p.card.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(hover ? BotColor.soft(bot.hue) : p.border))
        .contentShape(RoundedRectangle(cornerRadius: R.xxl))
        // щелчок по карточке открывает бота; кнопки внутри («Позвать», меню «…») работают сами
        .onTapGesture { app.openBot(bot.id) }
        .onHover { hover = $0 }
        .onRightClick { app.showBotMenu(bot, at: $0) }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    private struct Chip: View {
        let text: String
        let icon: String?
        @Environment(\.palette) private var p
        var body: some View {
            HStack(spacing: 4) {
                if let icon { Icon(icon, 11) }
                Text(text)
            }
            .tw(11, lh: 14).foregroundStyle(p.mutedFg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.md))
        }
    }
}

private struct NewBotTile: View {
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Icon("plus", 20)
                Text("Создать бота").tw(14, lh: 20)
                Text("Роль, разрешённые инструменты и папка").tw(12, lh: 16).multilineTextAlignment(.center).frame(maxWidth: 190)
            }
            .foregroundStyle(hover ? p.foreground : p.mutedFg)
            .frame(maxWidth: .infinity, minHeight: 196)
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(hover ? p.glow.opacity(0.4) : p.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: паспорт бота (правая панель его разговора)

struct BotPassport: View {
    @Bindable var app: AppModel
    let bot: Bot

    @Environment(\.palette) private var p
    @Environment(\.windowWidth) private var windowWidth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    BotAvatar(bot: bot, size: 56)
                    Text(bot.name).tw(16, .semibold, lh: 22)
                    Text(bot.role).tw(13, lh: 18).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
                section("Может") {
                    let granted = BotCapability.allCases.filter { bot.can.contains($0) }
                    if granted.isEmpty { Text("Только разговаривать").tw(13, lh: 18).foregroundStyle(p.mutedFg) }
                    ForEach(granted, id: \.self) { c in
                        IconLabel(text: c.name, icon: c.icon, size: 14).tw(13, lh: 18).foregroundStyle(BotColor.accent(bot.hue))
                    }
                    if bot.can.contains(.run) && !bot.can.contains(.write) {
                        Text("Команды: " + (bot.commands.isEmpty ? "ни одной" : bot.commands.joined(separator: ", ")))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("Отрезано в коде") {
                    ForEach(BotPermissions.blocked(bot), id: \.self) { name in
                        IconLabel(text: name, icon: "lock", size: 14).tw(13, lh: 18).foregroundStyle(p.mutedFg)
                    }
                    Text("Этих инструментов в процессе бота нет вовсе — просьбой их не включить.")
                        .tw(11, lh: 15).foregroundStyle(p.mutedFg.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }
                if !bot.learned.isEmpty {
                    section("Чему научился") {
                        ForEach(bot.learned, id: \.self) { l in
                            IconLabel(text: l, icon: "lightbulb", size: 13).tw(12, lh: 16)
                        }
                    }
                }
                if !bot.skills.isEmpty {
                    section("Навыки") {
                        ForEach(bot.skills, id: \.self) { s in
                            IconLabel(text: s, icon: "book-open", size: 13).tw(12, lh: 16)
                        }
                    }
                }
                if !bot.connectors.isEmpty {
                    section("Коннекторы") {
                        ForEach(bot.connectors, id: \.self) { s in
                            IconLabel(text: s, icon: app.connectors.mcpServers[s]?.isRemote == true ? "globe" : "terminal", size: 13).tw(12, lh: 16)
                        }
                    }
                }
                section("Где работает") {
                    IconLabel(text: bot.folder.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "Своя пустая папка", icon: "folder", size: 14)
                        .tw(12, lh: 16).lineLimit(2).truncationMode(.middle)
                    IconLabel(text: "\(bot.model.name) · \(bot.effort.name.lowercased())", icon: "sparkles", size: 14).tw(12, lh: 16)
                    if let h = bot.handoff.flatMap({ app.bot($0) }) {
                        IconLabel(text: "Чужое передаёт @\(h.id)", icon: "at-sign", size: 14).tw(12, lh: 16)
                    }
                }
                LButton(title: "Изменить бота", icon: "pencil", kind: .outline, small: true) { app.page = .botEditor(bot.id) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(width: RightPanel.width(windowWidth))
        // тот же цвет, что у основной области, и тонкая линия слева (Рома, 19.10)
        .background(p.background)
        .overlay(alignment: .leading) { p.border.frame(width: 1).ignoresSafeArea() }
        .foregroundStyle(p.foreground)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
            content()
        }
    }
}

// MARK: конструктор

struct BotEditor: View {
    @Bindable var app: AppModel
    let botID: String?

    @Environment(\.palette) private var p
    @State private var draft = Bot(id: "", name: "")
    @State private var idText = ""
    @State private var commandsText = ""
    @State private var startersText = ""
    @State private var loaded = false
    @State private var phrase = ""
    @State private var drafting = false
    @State private var describeNote: String?

    private var existing: Bot? { app.bot(botID) }

    var body: some View {
        PageFrame(title: existing == nil ? "Новый бот" : "Бот «\(existing?.name ?? "")»",
                  lead: "Права выбираешь ты: чего не отмечено, того у бота нет в коде — модель даже не видит таких инструментов.") {
            HStack(spacing: 8) {
                LButton(title: "Отмена", kind: .ghost) { cancel() }
                LButton(title: existing == nil ? "Создать" : "Сохранить", icon: "check", kind: .primary) { save() }
                    .disabled(problem != nil)
            }
        } content: {
            // слева форма (прокручивается), справа — как бот будет выглядеть: всегда на виду, едет вместе с прокруткой
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    form.padding(.bottom, 40)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: 780)
                ScrollView {
                    preview.frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(width: 320)
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: load)
        .onChange(of: botID) { loaded = false; load() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 28) {
            if existing == nil { describeCard }
            field("Название") { GlowField(placeholder: "Например, Тестировщик", text: $draft.name) }
            field("Имя для вызова", aside: "в чате: @\(idText.isEmpty ? "id" : idText)") {
                GlowField(placeholder: "tester", text: $idText, mono: true)
                    .onChange(of: idText) { _, v in
                        let clean = v.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                        if clean != v { idText = clean }
                    }
            }
            field("Капля") {
                BlobLookEditor(look: Binding(get: { draft.blobLook }, set: { v in draft.look = v; draft.hue = v.hue }))
            }
            field("Роль", aside: "одна строка") { GlowField(placeholder: "Проверяет приложения и правки — и только", text: $draft.role) }
            field("Инструкции") {
                Editor(text: $draft.instructions, placeholder: "Как работать: что делать, в каком виде отчитываться, чего не делать никогда", minHeight: 110)
            }
            field("Что разрешено") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(BotCapability.choosable, id: \.self) { c in
                        HStack(spacing: 12) {
                            Icon(c.icon, 16).foregroundStyle(draft.capabilities.contains(c) ? BotColor.accent(draft.hue) : p.mutedFg)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.name).tw(14, lh: 20)
                                Text(note(c)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                            }
                            Spacer()
                            LSwitch(isOn: Binding(get: { draft.capabilities.contains(c) },
                                                  set: { on in if on { draft.capabilities.insert(c) } else { draft.capabilities.remove(c) } }))
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
                    }
                    // у всех ботов всегда — без переключателя
                    ForEach(BotCapability.allCases.filter { BotCapability.always.contains($0) }, id: \.self) { c in
                        HStack(spacing: 12) {
                            Icon(c.icon, 16).foregroundStyle(BotColor.accent(draft.hue))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.name).tw(14, lh: 20)
                                Text(note(c)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                            }
                            Spacer()
                            Text("всегда").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(p.foreground.opacity(0.06), in: Capsule())
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
                    }
                    HStack(spacing: 12) {
                        Icon("lock", 16).foregroundStyle(p.mutedFg)
                        Text("Push на GitHub — никогда, это делаешь ты").tw(14, lh: 20).foregroundStyle(p.mutedFg)
                    }
                    .padding(.vertical, 10)
                }
            }
            if draft.capabilities.contains(.run) && !draft.capabilities.contains(.write) {
                field("Какие команды можно", aside: "через запятую") {
                    VStack(alignment: .leading, spacing: 6) {
                        GlowField(placeholder: "swift test, ./build.sh", text: $commandsText, mono: true)
                        Text("Без права править файлы бот запускает только эти команды — иначе он мог бы писать в файлы через терминал.")
                            .tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            field("Папка") {
                HStack(spacing: 10) {
                    Icon("folder", 16).foregroundStyle(draft.folder == nil ? p.mutedFg : p.glow)
                    Text(draft.folder?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Своя пустая папка — чужих файлов бот не видит")
                        .tw(13, lh: 18).foregroundStyle(draft.folder == nil ? p.mutedFg : p.foreground).lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if draft.folder != nil { IconButton(icon: "x", help: "Без папки") { draft.folder = nil } }
                    LButton(title: "Выбрать…", kind: .outline, small: true) { chooseFolder() }
                }
            }
            field("Модель") {
                Segmented(value: $draft.model, options: ChatModel.claude.filter { app.availableModels(for: .subscription).contains($0) }.map { ($0, $0.name) })
            }
            field("Сколько думать") {
                Segmented(value: $draft.effort, options: [Effort.low, .medium, .high].map { ($0, $0.name) })
            }
            if !app.skills.isEmpty {
                field("Навыки", aside: "бот видит только отмеченные") {
                    FlowWrap(spacing: 6) {
                        ForEach(app.skills) { s in
                            let on = draft.skills.contains(s.name)
                            Button {
                                if on { draft.skills.removeAll { $0 == s.name } } else { draft.skills.append(s.name) }
                            } label: {
                                HStack(spacing: 6) {
                                    Icon(on ? "check" : "book-open", 12)
                                    Text(s.name)
                                }
                                .tw(12, lh: 16).foregroundStyle(on ? BotColor.accent(draft.hue) : p.mutedFg)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? BotColor.faint(draft.hue) : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? BotColor.soft(draft.hue) : p.border))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(s.description)
                        }
                    }
                }
            }
            if !app.connectors.mcpServers.isEmpty {
                field("Коннекторы", aside: "сайты и программы из «Кастомизации» — бот видит только отмеченные") {
                    FlowWrap(spacing: 6) {
                        ForEach(app.connectors.mcpServers.keys.sorted(), id: \.self) { name in
                            let s = app.connectors.mcpServers[name]!
                            let on = draft.connectors.contains(name)
                            Button {
                                if on { draft.connectors.removeAll { $0 == name } } else { draft.connectors.append(name) }
                            } label: {
                                HStack(spacing: 6) {
                                    Icon(on ? "check" : (s.isRemote ? "globe" : "terminal"), 12)
                                    Text(name)
                                    if s.disabled { Text("выключен").foregroundStyle(p.mutedFg.opacity(0.7)) }
                                }
                                .tw(12, lh: 16).foregroundStyle(on ? BotColor.accent(draft.hue) : p.mutedFg)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? BotColor.faint(draft.hue) : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? BotColor.soft(draft.hue) : p.border))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(s.note.isEmpty ? s.summary : s.note)
                        }
                    }
                }
            }
            if let b = existing, !b.learned.isEmpty {
                field("Чему научился", aside: "из прошлых задач — попадает в его правила") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(draft.learned, id: \.self) { l in
                            HStack(alignment: .top, spacing: 8) {
                                Icon("lightbulb", 13).foregroundStyle(BotColor.accent(draft.hue)).padding(.top, 2)
                                Text(l).tw(13, lh: 18).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                IconButton(icon: "x", help: "Забыть вывод") { draft.learned.removeAll { $0 == l } }
                            }
                        }
                    }
                }
            }
            field("Подсказки", aside: "по одной в строке") {
                Editor(text: $startersText, placeholder: "Протестируй последний коммит\nЧто сломалось в прошлый раз?", minHeight: 70)
            }
            if app.bots.contains(where: { $0.id != botID }) {
                field("Чужое передаёт") {
                    Segmented(value: $draft.handoff, options: [(String?.none, "Lumen")] + app.bots.filter { $0.id != botID }.map { (Optional($0.id), "@\($0.id)") })
                }
            }
            if let problem {
                IconLabel(text: problem, icon: "triangle-alert", size: 14).tw(13, lh: 18).foregroundStyle(p.mutedFg)
            }
        }
    }

    /// Как бот будет выглядеть в чате
    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Так его увидишь").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
            HStack(spacing: 12) {
                BotAvatar(look: draft.blobLook, size: 44, animated: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(draft.name.isEmpty ? "Без названия" : draft.name).tw(14, .medium, lh: 20)
                    Text("@\(idText.isEmpty ? "id" : idText)").tw(12, lh: 16).foregroundStyle(BotColor.accent(draft.hue))
                }
            }
            Text(draft.role.isEmpty ? "Роль одной строкой" : draft.role).tw(13, lh: 18).foregroundStyle(p.mutedFg)
            VStack(alignment: .leading, spacing: 6) {
                Text("Отрезано в коде").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
                ForEach(BotPermissions.blocked(normalized), id: \.self) { n in
                    IconLabel(text: n, icon: "lock", size: 13).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
            }
            .padding(.top, 6)
            if let existing {
                LButton(title: "Удалить бота", icon: "trash", kind: .ghost, small: true) { app.deleteBot(existing) }
                    .foregroundStyle(Palette.destructive).padding(.top, 10)
            }
        }
        .padding(16)
        .background(BotColor.faint(draft.hue), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(BotColor.soft(draft.hue)))
    }

    /// Самое быстрое: описать бота одной фразой — Lumen (Haiku 5.5) заполнит всё ниже, права проверяешь ты
    private var describeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Icon("sparkles", 18).foregroundStyle(p.glow)
                    .frame(width: 34, height: 34)
                    .background(p.glow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Опиши бота одной фразой").tw(16, .semibold, lh: 22)
                    Text("Lumen сам заполнит название, роль, инструкции, знак и минимум прав. Включаешь права — ты.")
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                // в несколько строк: длинное описание видно целиком, курсор не уезжает за край
                TextField(text: $phrase, axis: .vertical) {
                    Text("Например: проверяет сборки моих Mac-приложений и пишет, что сломалось").foregroundStyle(p.mutedFg.opacity(0.7))
                }
                .textFieldStyle(.plain)
                .font(.geist(16))
                .lineLimit(1...5)
                .onSubmit { describe() }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.glow.opacity(0.35)))
                LButton(title: drafting ? "Настраиваю…" : "Настроить", icon: "sparkles", kind: .primary, busy: drafting) { describe() }
                    .disabled(phrase.trimmingCharacters(in: .whitespaces).isEmpty || drafting || app.cli == nil)
            }
            FlowWrap(spacing: 6) {
                ForEach(["Тестирует сборки и пишет, что сломалось", "Пишет тексты для сайта", "Ревьюит код перед коммитом"], id: \.self) { idea in
                    Button { phrase = idea; describe() } label: {
                        Text(idea).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(p.border))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(drafting || app.cli == nil)
                }
            }
            if let describeNote {
                IconLabel(text: describeNote, icon: "circle-check", size: 13).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
        }
        .padding(18)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.glow.opacity(0.3)))
    }

    private func field<C: View>(_ title: String, aside: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle(text: title, aside: aside)
            content()
        }
    }

    private func note(_ c: BotCapability) -> String {
        switch c {
        case .read: "в своей папке: файлы, поиск по коду"
        case .write: "правка и создание файлов в своей папке"
        case .run: "терминал; без правки — только команды из списка"
        case .web: "поиск и чтение страниц"
        case .git: "status, diff, commit — без push"
        case .memory: "запоминает важное о тебе и проектах, вспоминает прошлое"
        case .bots: "передаёт чужую часть задачи другому боту — на один шаг"
        case .skills: "ищет и ставит навыки из skills.sh, пишет свои, предлагает коннекторы и хуки"
        case .browser: "работает в браузере сбоку, с твоими входами в аккаунты; показывает тебе макеты и сайты"
        }
    }

    /// То, что будет сохранено
    private var normalized: Bot {
        var b = draft
        b.id = idText
        b.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        b.role = draft.role.trimmingCharacters(in: .whitespacesAndNewlines)
        b.commands = commandsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        b.starters = startersText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return b
    }

    private var problem: String? {
        let b = normalized
        if b.name.isEmpty { return "Дай боту название" }
        if !Bot.isValidID(b.id) { return "Имя для вызова: от 2 до 32 знаков — латиница, цифры, дефис" }
        if b.id != botID && app.bot(b.id) != nil { return "@\(b.id) уже занят другим ботом" }
        return nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        var b = existing ?? Bot(id: "", name: "", hue: Double(Int.random(in: 0..<12) * 30), capabilities: [.read],
                                commands: Bot.defaultCommands, model: .sonnet)
        if existing == nil {
            // новому боту — случайная капля: форма и цвет из палитры, оттенок подписей — по цвету
            let look = BlobLook(shape: BlobShape.allCases.randomElement() ?? .circle, face: .attentive,
                                color: BlobLook.palette.randomElement()?.hex ?? "#eab04a")
            b.look = look
            b.hue = look.hue
        }
        draft = b
        idText = b.id
        commandsText = b.commands.joined(separator: ", ")
        startersText = b.starters.joined(separator: "\n")
    }

    private func describe() {
        let text = phrase.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !drafting else { return }
        drafting = true
        Task {
            if let b = await app.draftBot(text) {
                draft = b
                idText = b.id
                commandsText = (b.commands.isEmpty ? Bot.defaultCommands : b.commands).joined(separator: ", ")
                startersText = b.starters.joined(separator: "\n")
                describeNote = "Готово — проверь ниже, особенно «Что разрешено», и нажми «Создать»."
            } else {
                describeNote = "Lumen не ответил — попробуй ещё раз."
            }
            drafting = false
        }
    }

    private func save() {
        guard problem == nil else { return }
        let b = normalized
        app.saveBot(b, replacing: existing?.id)
        app.openBot(b.id)
    }

    private func cancel() {
        if let existing { app.openBot(existing.id) } else { app.page = .bots }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Выбрать"
        panel.message = "Папка, в которой бот будет работать"
        if panel.runModal() == .OK, let url = panel.url { draft.folder = url.path }
    }
}

/// Многострочное поле в стиле полей ввода
private struct Editor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 100

    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.horizontal, 12).padding(.vertical, 8)
            }
            TextEditor(text: $text)
                .font(.geist(14)).scrollContentBackground(.hidden)
                .padding(.horizontal, 7).padding(.vertical, 8)
        }
        .frame(minHeight: minHeight)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
}

/// Полоса оттенков: щелчок или перетаскивание выбирает цвет бота
struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                LinearGradient(colors: stride(from: 0.0, through: 360, by: 30).map { BotColor.accent($0) }, startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                Circle().fill(BotColor.accent(hue)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: CGFloat(hue / 360) * (g.size.width - 18))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                hue = (min(max(0, v.location.x - 9), g.size.width - 18) / (g.size.width - 18) * 360).rounded()
            })
        }
        .frame(height: 18)
    }
}
