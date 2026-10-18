import LumenCore
import LumenProviders
import SwiftUI

/// Настройки: слева разделы группами (как в Hermes: «Внешний вид ▾» с подпунктами, «О программе ▾»),
/// сверху крошки «Настройки › Внешний вид › Тема», справа выбранный раздел. Только то, что работает
/// (исключение — «Питомец», Рома разрешил «скоро», 17.10).
struct SettingsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var closed: Set<String> = []

    enum Section: String, CaseIterable, Hashable {
        case general = "Общие"
        case theme = "Тема"
        case fonts = "Шрифты и масштаб"
        case window = "Окно и расположение"
        case chat = "Отображение чата"
        case pet = "Питомец"
        case persona = "Характер"
        case models = "Модели и оплата"
        case importClaude = "Импорт из Claude Code"
        case data = "Данные"
        case about = "Версия и обновления"
        case uninstall = "Удаление"

        var icon: String {
            switch self {
            case .general: "hexagon"
            case .theme: "palette"
            case .fonts: "type"
            case .window: "monitor"
            case .chat: "message-circle"
            case .pet: "paw-print"
            case .persona: "sparkles"
            case .models: "key-round"
            case .importClaude: "download"
            case .data: "database"
            case .about: "refresh-cw"
            case .uninstall: "trash"
            }
        }

        /// Все разделы (снимки настроек обходят их)
        @MainActor static func visible(_ app: AppModel) -> [Section] { allCases }
    }

    /// Группа слева: одна строка или раскрывающийся список
    struct NavGroup: Identifiable {
        let title: String
        let icon: String
        let items: [Section]
        var id: String { title }
    }

    static let groups: [NavGroup] = [
        NavGroup(title: "Внешний вид", icon: "palette", items: [.general, .theme, .fonts, .window, .chat, .pet]),
        NavGroup(title: "Характер", icon: "sparkles", items: [.persona]),
        NavGroup(title: "Модели и оплата", icon: "key-round", items: [.models]),
        NavGroup(title: "Данные", icon: "database", items: [.data]),
        NavGroup(title: "О программе", icon: "info", items: [.about, .uninstall]),
    ]

    private var current: Section {
        if case .settings(let s) = app.page { return s }
        return .general
    }

    private var group: NavGroup { Self.groups.first { $0.items.contains(current) } ?? Self.groups[0] }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            nav
                .frame(width: 228)
                .padding(.top, 52)
            p.border.frame(width: 1).padding(.top, 52)
            VStack(alignment: .leading, spacing: 0) {
                crumbs.padding(.horizontal, 32).padding(.top, 52).padding(.bottom, 20)
                if current == .persona {
                    PersonaView(app: app, embedded: true).padding(.horizontal, 32)
                } else {
                    ScrollView {
                        content
                            .padding(.horizontal, 32).padding(.bottom, 48)
                            .frame(maxWidth: 860, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                    .id(current) // новый раздел открывается с начала
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(p.foreground)
        .task { if app.claude == .checking { await app.refreshClaude() } }
    }

    // MARK: слева

    private var nav: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.groups) { g in
                    if g.items.count == 1, let only = g.items.first {
                        SettingsNavRow(title: g.title, icon: g.icon, active: current == only) { go(only) }
                    } else {
                        let open = !closed.contains(g.id)
                        SettingsNavRow(title: g.title, icon: g.icon, active: false, chevron: open ? "chevron-down" : "chevron-right",
                                       framed: g.items.contains(current)) {
                            withAnimation(.easeOut(duration: 0.15)) { if open { closed.insert(g.id) } else { closed.remove(g.id) } }
                        }
                        if open {
                            ForEach(g.items, id: \.self) { s in
                                SettingsNavRow(title: s.rawValue, icon: s.icon, active: current == s, sub: true) { go(s) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
    }

    private func go(_ s: Section) {
        withAnimation(.easeOut(duration: 0.15)) { app.page = .settings(s) }
    }

    /// «Настройки › Внешний вид › Тема»; у раздела без подпунктов — два звена
    private var crumbs: some View {
        HStack(spacing: 10) {
            Text("Настройки").foregroundStyle(p.mutedFg)
            Icon("chevron-right", 13).foregroundStyle(p.mutedFg)
            if group.items.count > 1 {
                Button { go(group.items[0]) } label: { Text(group.title).foregroundStyle(p.mutedFg) }.buttonStyle(.plain)
                Icon("chevron-right", 13).foregroundStyle(p.mutedFg)
            }
            Text(current.rawValue)
        }
        .tw(15, lh: 20)
    }

    // MARK: справа

    @ViewBuilder private var content: some View {
        switch current {
        case .general: general
        case .theme: ThemeSettings(app: app)
        case .fonts: fonts
        case .window: window
        case .chat: chatLook
        case .pet: pet
        case .persona: EmptyView()
        case .models: page("Через что Lumen думает. Можно держать оба: подписку на каждый день и ключ API про запас.") { models }
        case .importClaude, .data: DataSettings(app: app)
        case .about: AboutSettings(app: app)
        case .uninstall: UninstallSettings(app: app)
        }
    }

    /// Заголовок раздела крупно и пояснение под ним
    private func page<C: View>(_ lead: String?, aside: AnyView? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.rawValue).tw(20, .semibold, lh: 28).tracking(-0.2)
                    if let lead { Text(lead).tw(14, lh: 20).foregroundStyle(p.mutedFg).frame(maxWidth: 560, alignment: .leading) }
                }
                Spacer(minLength: 16)
                if let aside { aside }
            }
            content().padding(.top, 20)
        }
    }

    /// Строка настройки: название и пояснение слева, управление справа, линия снизу
    private func row<C: View>(_ title: String, _ note: String? = nil, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tw(14, lh: 20)
                if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    private var lightBinding: Binding<Appearance> {
        Binding(get: { app.prefs.appearance }, set: { v in app.update { $0.appearance = v } })
    }

    // MARK: общие

    private var general: some View {
        page("Как выглядит Lumen целиком.") {
            VStack(alignment: .leading, spacing: 0) {
                row("Свет", "Тема подстраивается: у каждой есть светлые и тёмные цвета") {
                    LightSwitch(value: lightBinding)
                }
                row("Тема", "Сейчас — «\(Palette.Family.find(app.prefs.themeID, app.prefs).name)»") {
                    LButton(title: "Выбрать", icon: "palette", kind: .outline, small: true) { go(.theme) }
                }
                row("Меньше движения", "Сфера не дышит, свет не мерцает, значки не крутятся") {
                    PillPicker(value: Binding(get: { app.prefs.motion }, set: { v in app.update { $0.motion = v; $0.reducedMotion = v == .on } }),
                               options: [(.system, "Системный"), (.on, "Вкл."), (.off, "Выкл.")])
                }
            }
            .frame(maxWidth: 680)
        }
    }

    // MARK: шрифты

    private var fonts: some View {
        page("Текст переписки: чат, агент и боты.") {
            VStack(alignment: .leading, spacing: 0) {
                row("Шрифт") {
                    Segmented(value: Binding(get: { app.prefs.chatFont }, set: { v in app.update { $0.chatFont = v } }),
                              options: [(.geist, "Geist"), (.system, "Системный"), (.serif, "С засечками"), (.mono, "Моно")])
                        .frame(width: 400)
                }
                row("Размер", "\(Int((15 * app.prefs.textScale).rounded())) pt") {
                    Segmented(value: Binding(get: { app.prefs.textScale }, set: { v in app.update { $0.textScale = v } }),
                              options: [(0.87, "Мельче"), (1.0, "Обычный"), (1.13, "Крупнее"), (1.27, "Крупно")])
                        .frame(width: 400)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Так будет выглядеть ответ").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    RichText(text: "Привет! Это пример ответа: **жирный**, *курсив* и `код` в строке. Абзацы стоят свободно, чтобы читать было легко.")
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.xl))
                        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: 680)
        }
    }

    // MARK: окно

    private var window: some View {
        page("Панели по краям окна.") {
            VStack(alignment: .leading, spacing: 0) {
                row("Панель слева", "Её же прячет ⌘\\ и кнопка у кнопок окна") {
                    LSwitch(isOn: Binding(get: { !app.prefs.sidebarHidden }, set: { v in app.update { $0.sidebarHidden = !v } }))
                }
                row("Ширина панели слева", "\(Int(app.sidebarWidth)) pt") {
                    Slider(value: Binding(get: { app.sidebarWidth }, set: { v in app.sidebarWidth = v.rounded(); app.update { $0.sidebarWidth = v.rounded() } }),
                           in: 220...420).frame(width: 240)
                }
                row("Браузер выезжает сам", "Когда агент открывает страницу или показывает макет") {
                    LSwitch(isOn: Binding(get: { app.prefs.browserAutoOpen }, set: { v in app.update { $0.browserAutoOpen = v } }))
                }
            }
            .frame(maxWidth: 680)
        }
    }

    // MARK: переписка

    private var chatLook: some View {
        page("Как выглядит разговор.") {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Ширина переписки агента", aside: "у чата и ботов — всегда обычная")
                ThreeColumns(empty: 0) {
                    ForEach(ChatWidth.allCases, id: \.self) { w in WidthCard(app: app, width: w) }
                }
                GroupTitle(text: "Режимы агента в поле ввода", aside: "Shift+Tab — следующий из показанных").padding(.top, 32)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AgentMode.allCases) { m in
                        let shown = !app.prefs.hiddenModes.contains(m)
                        HStack(spacing: 12) {
                            Icon(m.icon, 16).foregroundStyle(shown ? p.glow : p.mutedFg)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.name).font(.geist(14))
                                Text(m.note).font(.geist(12)).foregroundStyle(p.mutedFg)
                            }
                            Spacer()
                            LSwitch(isOn: Binding(get: { shown }, set: { on in
                                app.update { prefs in
                                    if on { prefs.hiddenModes.removeAll { $0 == m } } else { prefs.hiddenModes.append(m) }
                                    // выбранный режим скрыли — встаёт первый из показанных
                                    if !prefs.visibleModes.contains(prefs.agentMode) { prefs.agentMode = prefs.visibleModes[0] }
                                }
                            }))
                            // последний показанный не выключить: без режима поле не работает
                            .disabled(shown && app.prefs.visibleModes.count == 1)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
                    }
                }
                .frame(maxWidth: 680)
            }
        }
    }

    // MARK: питомец

    private var pet: some View {
        page("Маленький спутник в углу окна: радуется, когда агент закончил, и засыпает, когда ты ушёл.") {
            HStack(spacing: 16) {
                Icon("paw-print", 28).foregroundStyle(p.glow)
                    .frame(width: 64, height: 64)
                    .background(p.glow.opacity(0.08), in: RoundedRectangle(cornerRadius: R.xl))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Скоро").tw(16, .medium, lh: 22)
                    Text("Питомец появится в одном из следующих выпусков.").tw(13, lh: 18).foregroundStyle(p.mutedFg)
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        }
    }

    // MARK: модели и оплата

    private var models: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Через что отвечать по умолчанию")
                ThreeColumns(spacing: 8) {
                    ChoiceCard(title: "Подписка", note: "Входит в тариф Claude. Есть лимит на 5 часов и на неделю.",
                               active: app.prefs.backend == .subscription, settingsStyle: true) { app.update { $0.backend = .subscription } }
                    ChoiceCard(title: "API", note: "Платишь за токены. Без лимитов по времени.",
                               active: app.prefs.backend == .api, settingsStyle: true) { app.update { $0.backend = .api } }
                }
                Text("Касается новых чатов. Начатый разговор продолжается тем же способом.")
                    .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.top, 8)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    SubscriptionCard(app: app).frame(minWidth: 300)
                    ApiKeyCard(app: app).frame(minWidth: 300)
                }
                VStack(spacing: 16) {
                    SubscriptionCard(app: app)
                    ApiKeyCard(app: app)
                }
            }
            ChatGPTCard(app: app)
        }
    }

}

/// Пункт слева: значок и название; у группы — шеврон и рамка, когда внутри открыт её раздел
struct SettingsNavRow: View {
    let title: String
    let icon: String
    let active: Bool
    var chevron: String?
    var framed = false
    var sub = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, 15).foregroundStyle(active ? p.glow : p.mutedFg).frame(width: 16)
                Text(title).tw(14, lh: 20).lineLimit(1)
                Spacer(minLength: 4)
                if let chevron { Icon(chevron, 13).foregroundStyle(p.mutedFg) }
            }
            .foregroundStyle(active || hover || framed ? p.foreground : p.foreground.opacity(0.75))
            .padding(.leading, sub ? 22 : 10).padding(.trailing, 8).frame(height: 32)
            .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(framed ? p.border : .clear))
            .overlay(alignment: .leading) { if active { GlowBar().padding(.leading, sub ? 12 : 0) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Переключатель света: «Светлая · Тёмная · Системная» с значками, как в Hermes
struct LightSwitch: View {
    @Binding var value: Appearance

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 2) {
            item(.light, "Светлая", "sun")
            item(.dark, "Тёмная", "moon")
            item(.system, "Системная", "monitor")
        }
        .padding(3)
        .background(p.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }

    private func item(_ a: Appearance, _ name: String, _ icon: String) -> some View {
        let on = value == a
        return Button { withAnimation(.easeOut(duration: 0.2)) { value = a } } label: {
            HStack(spacing: 6) {
                Icon(icon, 14)
                Text(name).tw(13, lh: 18)
            }
            .foregroundStyle(on ? p.foreground : p.mutedFg)
            .padding(.horizontal, 12).frame(height: 30)
            .background(on ? p.background : .clear, in: RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(on ? p.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: тема

/// «Тема» (как «Визуальный стиль» в ChatGPT): режим карточками; тема списком с выгрузкой и загрузкой;
/// свои акцент, фон и текст поверх темы; все темы карточками и «Новая тема»; «Расширенные» — шрифты, движение,
/// раздельные темы для света и тьмы, контраст, маркеры различий
struct ThemeSettings: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var advanced = true
    @State private var note: String?

    private var dark: Bool { !p.isLight }
    private var themeID: String { Palette.themeID(app.prefs, dark: dark) }
    private var key: String { Palette.overridesKey(themeID, dark: dark) }
    private var overrides: ThemeOverrides { app.prefs.themeOverrides[key] ?? ThemeOverrides() }

    private func setOverride(_ f: @escaping (inout ThemeOverrides) -> Void) {
        let k = key
        app.update { prefs in
            var o = prefs.themeOverrides[k] ?? ThemeOverrides()
            f(&o)
            prefs.themeOverrides[k] = o.isEmpty ? nil : o
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Тема").tw(20, .semibold, lh: 28).tracking(-0.2)
            Text("Свет, цвета и шрифты. У каждой темы есть светлые и тёмные цвета — режим выбирает, какие сейчас.")
                .tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.top, 4)

            card {
                line("Режим") {
                    HStack(spacing: 10) {
                        ModeCard(app: app, mode: .system)
                        ModeCard(app: app, mode: .light)
                        ModeCard(app: app, mode: .dark)
                    }
                }
            }
            .padding(.top, 20)

            card {
                if app.prefs.separateModes {
                    line("Тема при свете", divider: true) { themeMenu(dark: false) }
                    line("Тема в темноте", divider: true) { themeMenu(dark: true) }
                } else {
                    line("Тема", divider: true) {
                        HStack(spacing: 4) {
                            IconButton(icon: "download", help: "Загрузить тему из буфера обмена") { importTheme() }
                            IconButton(icon: "copy", help: "Скопировать тему — можно отдать другу") { exportTheme() }
                            themeMenu(dark: false).padding(.leading, 6)
                        }
                    }
                }
                line("Акцентный цвет", divider: true) { accentMenu }
                line("Фон", divider: true) {
                    ColorField(color: p.background) { c in setOverride { $0.background = c?.hexString } }
                }
                line("Цвет текста") {
                    ColorField(color: p.foreground) { c in setOverride { $0.foreground = c?.hexString } }
                }
                if !overrides.isEmpty {
                    HStack {
                        Text("Свои цвета — только для «\(Palette.Family.find(themeID, app.prefs).name)» \(dark ? "в темноте" : "при свете")")
                            .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        Spacer()
                        LButton(title: "Вернуть цвета темы", icon: "rotate-ccw", kind: .ghost, small: true) {
                            let k = key
                            app.update { $0.themeOverrides[k] = nil }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.top, 12)
            if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.top, 8) }

            GroupTitle(text: "Все темы", aside: "щелчок — выбрать").padding(.top, 28)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(Palette.Family.all(app.prefs)) { f in ThemeCard(app: app, family: f) }
                NewThemeCard { createTheme() }
            }
            if let i = app.prefs.userThemes.firstIndex(where: { $0.id == app.prefs.themeID }) {
                UserThemeEditor(app: app, index: i).padding(.top, 16)
            }

            Button { withAnimation(.easeOut(duration: 0.15)) { advanced.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Расширенные").tw(15, .medium, lh: 20)
                    Icon(advanced ? "chevron-down" : "chevron-right", 13).foregroundStyle(p.mutedFg)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 32)
            if advanced { advancedCards.padding(.top, 12) }
        }
    }

    // MARK: части

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card.opacity(0.45), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }

    private func line<C: View>(_ title: String, _ note: String? = nil, divider: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tw(14, .medium, lh: 20)
                if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if divider { p.border.frame(height: 1) } }
    }

    /// Список тем: «Aa» в цвете темы и название
    private func themeMenu(dark: Bool) -> some View {
        let current = Palette.Family.find(dark ? (app.prefs.darkThemeID ?? app.prefs.themeID) : app.prefs.themeID, app.prefs)
        return Menu {
            ForEach(Palette.Family.all(app.prefs)) { f in
                Button(f.name) {
                    app.update { prefs in
                        if dark && prefs.separateModes { prefs.darkThemeID = f.id } else { prefs.themeID = f.id }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Aa").font(.geist(12, .semibold)).foregroundStyle(current.palette(dark: dark || !p.isLight ? true : false).glow)
                    .frame(width: 24, height: 24).background(p.foreground.opacity(0.06), in: Circle())
                Text(current.name).tw(14, lh: 20)
                Icon("chevron-down", 13).foregroundStyle(p.mutedFg)
            }
            .padding(.leading, 4).padding(.trailing, 12).frame(height: 34)
            .overlay(Capsule().strokeBorder(p.border))
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    /// Готовые акценты и свой цвет
    private var accentMenu: some View {
        let presets: [(String, UInt32?)] = [("Цвет темы", nil), ("Янтарный", 0xFEC766), ("Красный", 0xE5484D), ("Оранжевый", 0xF76B15),
                                             ("Зелёный", 0x30A46C), ("Бирюзовый", 0x12A594), ("Синий", 0x3E63DD), ("Розовый", 0xD6409F),
                                             ("Белый", 0xEDEDED), ("Чёрный", 0x1A1A1A)]
        let name = overrides.accent.flatMap { hex in presets.first { $0.1.map { Color(hex: $0).hexString } == hex }?.0 } ?? (overrides.accent == nil ? "Цвет темы" : "Свой")
        return HStack(spacing: 8) {
            Menu {
                ForEach(presets, id: \.0) { n, v in
                    Button(n) { setOverride { $0.accent = v.map { Color(hex: $0).hexString } } }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(p.glow).frame(width: 16, height: 16).overlay(Circle().strokeBorder(p.foreground.opacity(0.2)))
                    Text(name).tw(14, lh: 20)
                    Icon("chevron-down", 13).foregroundStyle(p.mutedFg)
                }
                .padding(.horizontal, 12).frame(height: 34)
                .overlay(Capsule().strokeBorder(p.border))
                .contentShape(Capsule())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            ColorPicker("", selection: Binding(get: { p.glow }, set: { c in setOverride { $0.accent = c.hexString } }), supportsOpacity: false)
                .labelsHidden().help("Свой цвет")
        }
    }

    private var advancedCards: some View {
        VStack(spacing: 12) {
            card {
                line("Размер шрифта интерфейса", "Базовый размер текста в Lumen", divider: true) {
                    NumberField(value: Binding(get: { app.prefs.uiFontSize }, set: { v in app.update { $0.uiFontSize = v } }), range: 12...18)
                }
                line("Размер шрифта кода", "Блоки кода в чатах и разница правок") {
                    NumberField(value: Binding(get: { app.prefs.codeFontSize }, set: { v in app.update { $0.codeFontSize = v } }), range: 10...18)
                }
            }
            card {
                line("Уменьшение движения", "Меньше анимаций — или как в настройках macOS", divider: true) {
                    PillPicker(value: Binding(get: { app.prefs.motion }, set: { v in app.update { $0.motion = v; $0.reducedMotion = v == .on } }),
                               options: [(.system, "Системный"), (.on, "Вкл."), (.off, "Выкл.")])
                }
                line("Раздельные темы для света и темноты", "Своя тема при светлом режиме и своя — при тёмном") {
                    LSwitch(isOn: Binding(get: { app.prefs.separateModes }, set: { v in
                        app.update { $0.separateModes = v; if v && $0.darkThemeID == nil { $0.darkThemeID = $0.themeID } }
                    }))
                }
            }
            card {
                line("Контраст") {
                    HStack(spacing: 12) {
                        Slider(value: Binding(get: { app.prefs.contrast }, set: { v in app.update { $0.contrast = v.rounded() } }), in: 0...100)
                            .frame(width: 220)
                        Text("\(Int(app.prefs.contrast))").tw(14, lh: 20).monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
            }
            card {
                line("Маркеры различий", "Как показывать правки агента: цветом строк или знаками +/−") {
                    PillPicker(value: Binding(get: { app.prefs.diffMarkers }, set: { v in app.update { $0.diffMarkers = v } }),
                               options: [(.color, "Цвет"), (.signs, "+/−")])
                }
            }
        }
    }

    // MARK: выгрузка и загрузка

    /// Тема в буфер обмена: название, оттенок, окраска и свои цвета — текстом JSON
    private func exportTheme() {
        let f = Palette.Family.find(app.prefs.themeID, app.prefs)
        let user = app.prefs.userThemes.first { $0.id == f.id }
        var o: [String: Any] = ["lumenTheme": 1, "name": f.name]
        if let user { o["hue"] = user.hue; o["tint"] = user.tint } else { o["base"] = f.id }
        for d in [false, true] {
            if let ov = app.prefs.themeOverrides[Palette.overridesKey(f.id, dark: d)],
               let data = try? JSONEncoder().encode(ov), let j = try? JSONSerialization.jsonObject(with: data) { o[d ? "dark" : "light"] = j }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
        flash("Тема «\(f.name)» скопирована")
    }

    /// Тема из буфера обмена (то, что скопировал «Скопировать тему»)
    private func importTheme() {
        guard let s = NSPasteboard.general.string(forType: .string),
              let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any], o["lumenTheme"] != nil else {
            flash("В буфере нет темы Lumen — сначала скопируй её кнопкой рядом")
            return
        }
        let name = (o["name"] as? String) ?? "Тема"
        var id = (o["base"] as? String).flatMap { b in Palette.Family.builtIn.first { $0.id == b }?.id }
        app.update { prefs in
            if id == nil {
                let t = UserTheme(name: name, hue: o["hue"] as? Double ?? 205, tint: o["tint"] as? Double ?? 0.4)
                prefs.userThemes.append(t)
                id = t.id
            }
            guard let id else { return }
            prefs.themeID = id
            for d in [false, true] {
                if let j = o[d ? "dark" : "light"], let data = try? JSONSerialization.data(withJSONObject: j),
                   let ov = try? JSONDecoder().decode(ThemeOverrides.self, from: data) { prefs.themeOverrides[Palette.overridesKey(id, dark: d)] = ov }
            }
        }
        flash("Тема «\(name)» загружена")
    }

    private func flash(_ s: String) {
        note = s
        Task { try? await Task.sleep(for: .seconds(3)); if note == s { note = nil } }
    }

    /// Новая тема — сразу выбрана, дальше правится ниже
    private func createTheme() {
        let n = app.prefs.userThemes.count + 1
        let t = UserTheme(name: n == 1 ? "Моя тема" : "Моя тема \(n)", hue: 205, tint: 0.4)
        app.update { $0.userThemes.append(t); $0.themeID = t.id }
    }
}

/// Карточка режима: миниатюра окна светлая, тёмная или пополам (системный)
private struct ModeCard: View {
    @Bindable var app: AppModel
    let mode: Appearance

    @Environment(\.palette) private var p

    var body: some View {
        let on = app.prefs.appearance == mode
        let fam = Palette.Family.find(app.prefs.themeID, app.prefs)
        Button { app.update { $0.appearance = mode } } label: {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    if mode != .dark { mini(fam.light) }
                    if mode != .light { mini(fam.dark) }
                }
                .frame(width: 112, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(on ? p.glow : p.border, lineWidth: on ? 2 : 1))
                Text(["system": "Системный", "light": "Светлый", "dark": "Тёмный"][mode.rawValue]!)
                    .tw(12, lh: 16).foregroundStyle(on ? p.foreground : p.mutedFg).lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mini(_ t: Palette) -> some View {
        ZStack(alignment: .topLeading) {
            t.background
            t.sidebar.frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(t.foreground.opacity(0.25)).frame(width: 34, height: 3)
                Capsule().fill(t.foreground.opacity(0.18)).frame(width: 26, height: 3)
                Capsule().fill(t.glow).frame(width: 20, height: 3)
                Spacer()
                RoundedRectangle(cornerRadius: 3).strokeBorder(t.border).frame(height: 9)
                    .overlay(alignment: .trailing) { Circle().fill(t.glow).frame(width: 5, height: 5).padding(.trailing, 2) }
            }
            .padding(.leading, 24).padding(.trailing, 6).padding(.vertical, 8)
        }
    }
}

/// Цвет кружком и «#RRGGBB»: щелчок по кружку — палитра macOS, по тексту — ввести код
private struct ColorField: View {
    let color: Color
    let set: (Color?) -> Void

    @Environment(\.palette) private var p
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(get: { color }, set: { set($0) }), supportsOpacity: false).labelsHidden()
            TextField("", text: $text).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                .frame(width: 76).focused($focused)
                .onSubmit { if let c = Color(hexString: text) { set(c) } else { text = color.hexString } }
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
        .overlay(Capsule().strokeBorder(p.border))
        .onAppear { text = color.hexString }
        .onChange(of: color.hexString) { _, h in if !focused { text = h } }
    }
}

/// Число с «px»: поле и стрелки ±1
private struct NumberField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value))
                    .tw(14, lh: 20).monospacedDigit().frame(width: 44, alignment: .leading).padding(.leading, 10)
                VStack(spacing: 0) {
                    Button { value = min(range.upperBound, (value + 1).rounded()) } label: { Icon("chevron-down", 10).rotationEffect(.degrees(180)) }
                    Button { value = max(range.lowerBound, (value - 1).rounded()) } label: { Icon("chevron-down", 10) }
                }
                .buttonStyle(.plain).foregroundStyle(p.mutedFg).padding(.trailing, 6)
            }
            .frame(height: 32)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
            Text("px").tw(14, lh: 20).foregroundStyle(p.mutedFg)
        }
    }
}

/// Выбор из двух-трёх слов «пилюлями», как «Системный · Вкл. · Выкл.» в ChatGPT
struct PillPicker<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { v, name in
                Button { value = v } label: {
                    Text(name).tw(13, lh: 18)
                        .foregroundStyle(value == v ? p.foreground : p.mutedFg)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(value == v ? p.foreground.opacity(0.09) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Пустая карточка «Новая тема»: пунктир и плюс
private struct NewThemeCard: View {
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Icon("plus", 20)
                Text("Новая тема").tw(14, .medium, lh: 20)
                Text("Свой цвет — светлая и тёмная версии сами").tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.8))
            .frame(maxWidth: .infinity).frame(height: 168)
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(hover ? p.foreground.opacity(0.3) : p.foreground.opacity(0.15),
                                                                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: R.xxl))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Правка своей темы: имя, оттенок (готовые и ползунок), окраска фона, удалить
private struct UserThemeEditor: View {
    @Bindable var app: AppModel
    let index: Int

    @Environment(\.palette) private var p
    @State private var name = ""

    private var theme: UserTheme { app.prefs.userThemes[index] }

    private func set(_ f: @escaping (inout UserTheme) -> Void) {
        app.update { prefs in
            guard index < prefs.userThemes.count else { return }
            f(&prefs.userThemes[index])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text("Название").font(.geist(13, .medium)).frame(width: 110, alignment: .leading)
                TextField("", text: $name).textFieldStyle(.plain).font(.geist(14))
                    .padding(.horizontal, 10).frame(width: 260, height: 32)
                    .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    .onSubmit { set { $0.name = name } }
                    .onChange(of: name) { _, n in set { $0.name = n } }
                Spacer()
                LButton(title: "Удалить тему", icon: "trash", kind: .ghost, small: true) {
                    let id = theme.id
                    app.update { prefs in
                        prefs.userThemes.removeAll { $0.id == id }
                        prefs.themeID = "lumen"
                    }
                }
            }
            HStack(spacing: 16) {
                Text("Цвет").font(.geist(13, .medium)).frame(width: 110, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach([0.0, 16, 38, 85, 140, 175, 205, 230, 330], id: \.self) { h in
                        Button { set { $0.hue = h } } label: {
                            Circle().fill(Color(hue: h / 360, saturation: 0.62, brightness: 1)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(p.foreground.opacity(abs(theme.hue - h) < 1 ? 0.9 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    HueSlider(hue: Binding(get: { theme.hue }, set: { v in set { $0.hue = v } })).frame(width: 160).padding(.leading, 6)
                }
            }
            HStack(spacing: 16) {
                Text("Окраска фона").font(.geist(13, .medium)).frame(width: 110, alignment: .leading)
                Slider(value: Binding(get: { theme.tint }, set: { v in set { $0.tint = v } }), in: 0...1).frame(maxWidth: 320)
                Text(theme.tint < 0.2 ? "почти нейтральный" : theme.tint < 0.65 ? "лёгкий оттенок" : "насыщенный")
                    .font(.geist(12)).foregroundStyle(p.mutedFg)
            }
        }
        .padding(16)
        .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .onAppear { name = theme.name }
        .onChange(of: index) { name = theme.name }
    }
}

// MARK: данные

/// «Данные»: что и сколько хранится, выгрузка, журнал; ниже — всё про Claude Code: перенести разговоры,
/// подтянуть названия, проекты и картинки, перенести память
private struct DataSettings: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var importing = false
    @State private var sizes: (db: Int64, files: Int64)?
    @State private var busy: String?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Данные").tw(20, .semibold, lh: 28).tracking(-0.2)
            Text("Всё хранится на этом Маке. Ничего не уходит в облако, кроме самих запросов к модели; ключ API — в Связке ключей.")
                .tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.top, 4).frame(maxWidth: 620, alignment: .leading)

            card("Хранилище", icon: "database") {
                Text(app.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(p.mutedFg).textSelection(.enabled)
                HStack(spacing: 0) {
                    stat("\(app.conversations.filter { $0.kind != .bot }.count)", "разговоров")
                    stat("\(app.memoryCount)", "фактов памяти")
                    stat("\(app.projects.count)", "проектов")
                    stat("\(app.bots.count)", "ботов")
                    stat("\(app.skills.count)", "навыков")
                }
                .padding(.top, 14)
                Text(sizes.map { "База — \(Self.size($0.db)), вложения — \(Self.size($0.files))" } ?? "Считаю размер…")
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.top, 12)
                HStack(spacing: 8) {
                    LButton(title: "Показать в Finder", icon: "folder", kind: .outline, small: true) { app.showDataInFinder() }
                    LButton(title: "Выгрузить всё…", icon: "download", kind: .outline, small: true, busy: busy == "export") { export() }
                    LButton(title: "Журнал", icon: "file-text", kind: .ghost, small: true) { NSWorkspace.shared.open(app.paths.logs) }
                }
                .padding(.top, 14)
            }

            card("Claude Code", icon: "square-terminal") {
                let imported = app.conversations.filter { $0.cliSessionID != nil && $0.kind == .agent }
                Text("Разговоры из Claude Code и приложения Claude переносятся задачами агента: та же папка и сессия, названия, проекты, модель и режим — как там. Открытый разговор догоняет то, что пишется в Claude.")
                    .tw(13, lh: 19).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    stat("\(imported.count)", "перенесено")
                    stat("\(Set(imported.compactMap(\.projectID)).count)", "в проектах")
                    stat("\(app.memories.filter { $0.source == "Claude Code" }.count)", "фактов из памяти")
                }
                .padding(.top, 14)
                HStack(spacing: 8) {
                    LButton(title: "Выбрать разговоры…", icon: "download", kind: .primary, small: true) { importing = true }
                    LButton(title: "Обновить из Claude", icon: "refresh-cw", kind: .outline, small: true, busy: busy == "refresh") {
                        busy = "refresh"
                        Task {
                            let n = await app.refreshFromClaude()
                            busy = nil
                            flash(n == 0 ? "Всё уже как в Claude" : "Поправлено разговоров: \(n) — названия, проекты, картинки")
                        }
                    }
                    LButton(title: "Перенести память", icon: "brain", kind: .outline, small: true) {
                        let n = app.importClaudeMemory()
                        flash(n == 0 ? "Новых фактов в памяти Claude Code нет" : "Перенесено фактов: \(n)")
                    }
                    .help("Факты из памяти Claude Code (~/.claude/projects/*/memory) — в память Lumen")
                }
                .padding(.top, 14)
            }

            card("Знакомство", icon: "sparkles") {
                Text("Имя, обращение и первые настройки — как при первом запуске. Память и разговоры остаются.")
                    .tw(13, lh: 19).foregroundStyle(p.mutedFg)
                LButton(title: "Пройти знакомство заново", icon: "sparkles", kind: .ghost, small: true) { app.restartOnboarding() }
                    .padding(.top, 10)
            }
            if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.top, 10) }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .sheet(isPresented: $importing) { ImportClaudeSheet(app: app) { importing = false }.environment(\.palette, p) }
        .task {
            let root = app.paths
            sizes = await Task.detached { (Self.bytes(root.database) + Self.bytes(root.root.appendingPathComponent("lumen.sqlite-wal")), Self.bytes(root.attachments)) }.value
        }
    }

    private func card<C: View>(_ title: String, icon: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon(icon, 15).foregroundStyle(p.glow)
                Text(title).tw(15, .medium, lh: 20)
            }
            .padding(.bottom, 10)
            c()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.45), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .padding(.top, 16)
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).tw(20, .semibold, lh: 26).monospacedDigit()
            Text(label).tw(12, lh: 16).foregroundStyle(p.mutedFg)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private func flash(_ s: String) {
        note = s
        Task { try? await Task.sleep(for: .seconds(4)); if note == s { note = nil } }
    }

    /// Вся папка Lumen архивом туда, куда скажет человек (ditto, как «Сжать» в Finder)
    private func export() {
        let panel = NSSavePanel()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Lumen-\(f.string(from: Date())).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = "export"
        let root = app.paths.root
        Task {
            let ok = await Task.detached { () -> Bool in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, url.path]
                guard (try? p.run()) != nil else { return false }
                p.waitUntilExit()
                return p.terminationStatus == 0
            }.value
            busy = nil
            flash(ok ? "Выгружено: \(url.lastPathComponent)" : "Не получилось выгрузить")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    nonisolated static func bytes(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) }
        var total: Int64 = 0
        for case let f as URL in fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) ?? FileManager.DirectoryEnumerator() {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// «0 Б», «340 КБ», «12,4 МБ»
    static func size(_ b: Int64) -> String {
        let d = Double(b)
        if d < 1000 { return "\(b) Б" }
        if d < 1_000_000 { return "\(Int((d / 1000).rounded())) КБ" }
        if d < 1_000_000_000 { return String(format: "%.1f МБ", d / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.1f ГБ", d / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: о программе

/// «Версия и обновления»: значок, версия, карточка обновлений и сведения о сборке
private struct AboutSettings: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var automatic = true

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    /// Порядковый номер выпуска (1.0 — первый, 12 — двенадцатый). Не CFBundleVersion: тот — счётчик Sparkle и растёт не по выпускам
    private var release: String { Bundle.main.object(forInfoDictionaryKey: "LumenReleaseNumber") as? String ?? "—" }
    /// Сборка, которую ещё не выпускали: номер выпуска здесь не показываем, он совпадает с последним выпуском
    private var versionText: String {
        let unreleased = Bundle.main.object(forInfoDictionaryKey: "LumenUnreleased") as? Bool ?? false
        return unreleased ? "\(version) (разработка)" : "\(version) (\(release))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            Text("Lumen").tw(24, .semibold, lh: 30).padding(.top, 10)
            Text("Версия " + versionText).tw(14, lh: 20).foregroundStyle(p.mutedFg)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Icon("refresh-cw", 15)
                    Text("Обновления").tw(15, .medium, lh: 20)
                }
                .padding(.bottom, 12)
                updates
                info.padding(.top, 16)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            automatic = app.updater?.automatic ?? true
            app.updater?.probe()
        }
    }

    @ViewBuilder private var updates: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let u = app.updater {
                HStack(spacing: 10) {
                    Icon(u.available != nil ? "download" : "circle-check", 16).foregroundStyle(u.available != nil ? p.glow : Palette.ok)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.probing ? "Проверяю…" : (u.available.map { "Готово обновление \($0)" } ?? "Стоит последняя версия"))
                            .tw(15, .medium, lh: 20)
                        Text(u.lastCheck.map { "Проверено \(RelativeWhen.string($0)) назад".replacingOccurrences(of: "сейчас назад", with: "только что") } ?? "Ещё не проверял")
                            .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    }
                }
                HStack(spacing: 8) {
                    LButton(title: "Проверить сейчас", icon: "refresh-cw", kind: .ghost, small: true) { u.check() }
                        .disabled(!u.canCheck)
                    if u.available != nil {
                        LButton(title: "Обновить сейчас", kind: .primary, small: true) { u.check() }
                    }
                    Spacer()
                    LButton(title: "Что нового", icon: "external-link", kind: .ghost, small: true) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/romankandeevy/lumen/releases")!)
                    }
                }
                p.border.frame(height: 1)
                HStack(spacing: 12) {
                    LSwitch(isOn: Binding(get: { automatic }, set: { automatic = $0; u.automatic = $0 }))
                    Text("Проверять самому раз в день").font(.geist(14))
                }
                HStack(spacing: 12) {
                    LSwitch(isOn: Binding(get: { app.prefs.betaUpdates }, set: { v in app.update { $0.betaUpdates = v } }))
                    Text("Бета-версии").font(.geist(14))
                    Text("приходят раньше стабильных, могут быть сырыми").font(.geist(12)).foregroundStyle(p.mutedFg)
                }
            } else {
                HStack(spacing: 10) {
                    Icon("info", 16).foregroundStyle(p.mutedFg)
                    Text("Это сборка для проверки: обновления работают в приложении из «Программ».").tw(14, lh: 20)
                }
            }
        }
        .padding(16)
        .background(p.glow.opacity(0.04), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.25)))
    }

    private var info: some View {
        VStack(spacing: 0) {
            line("Версия", versionText)
            line("Канал", app.prefs.betaUpdates ? "бета" : "стабильный")
            line("Приложение", Bundle.main.bundleURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), mono: true)
            line("Данные", app.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), mono: true)
            line("Claude Code", claude, last: true)
        }
        .padding(.horizontal, 16)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }

    private var claude: String {
        switch app.claude {
        case .signedIn(let v, _), .signedOut(let v): v.description
        case .tooOld(let v): v.description + " — слишком старый"
        case .notInstalled: "не найден"
        default: "—"
        }
    }

    private func line(_ k: String, _ v: String, mono: Bool = false, last: Bool = false) -> some View {
        HStack {
            Text(k).tw(14, lh: 20).foregroundStyle(p.mutedFg)
            Spacer(minLength: 16)
            Text(v).font(mono ? .system(size: 12.5, design: .monospaced) : .geist(14)).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { p.border.frame(height: 1) } }
    }
}

/// «Удаление»: убрать только приложение (данные остаются) или вместе с данными. Всё уходит в Корзину, не стирается
private struct UninstallSettings: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var ask: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Удалить Lumen").tw(20, .semibold, lh: 28).tracking(-0.2)
            Text("Выбери, сколько убрать. Lumen закроется, файлы уйдут в Корзину — их можно вернуть, пока она не очищена.")
                .tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.top, 4).frame(maxWidth: 560, alignment: .leading)
            VStack(spacing: 12) {
                option("Только приложение", "Убрать Lumen.app. Память, разговоры, настройки и ключ API остаются — поставишь снова, всё на месте.", all: false)
                option("Приложение и все данные", "Ещё и папку Lumen: память, разговоры, боты, навыки, настройки. Ключ API в Связке ключей остаётся.", all: true)
            }
            .padding(.top, 20)
            .frame(maxWidth: 680)
        }
        .padding(20)
        .background(Palette.destructive.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(Palette.destructive.opacity(0.4)))
        .confirmationDialog(ask == true ? "Удалить Lumen и все данные?" : "Удалить приложение Lumen?",
                            isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })) {
            Button("Переместить в Корзину и закрыть", role: .destructive) { if let all = ask { uninstall(all: all) } }
        } message: {
            Text(ask == true ? "Память и разговоры уйдут в Корзину вместе с приложением." : "Данные останутся на этом Маке.")
        }
    }

    private func option(_ title: String, _ note: String, all: Bool) -> some View {
        Button { ask = all } label: {
            HStack(alignment: .top, spacing: 14) {
                Icon("trash", 16).foregroundStyle(all ? Palette.destructive : p.foreground.opacity(0.8)).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).tw(15, .medium, lh: 20)
                    Text(note).tw(13, lh: 18).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// В Корзину (не стирается насовсем), потом выход
    private func uninstall(all: Bool) {
        var urls = [Bundle.main.bundleURL]
        if all { urls.append(app.paths.root) }
        app.chat.closeAll()
        NSWorkspace.shared.recycle(urls) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Сетка sm:grid-cols-3: элементы занимают по трети ширины, даже если их два (пустые колонки добиваются)
struct ThreeColumns<Content: View>: View {
    var spacing: CGFloat = 12
    var empty = 1
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            Group { content }.frame(maxWidth: .infinity)
            ForEach(0..<empty, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
    }
}

/// Каркас страницы-раздела (`Page`): заголовок text-[1.65rem] px-8 pt-8 pb-5, ниже содержимое px-8
struct PageFrame<Actions: View, Content: View>: View {
    let title: String
    var lead: String?
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).tw(26.4, .semibold, lh: 33).tracking(-0.53)
                    if let lead {
                        Text(lead).tw(14, lh: 20).foregroundStyle(p.mutedFg).frame(maxWidth: 560, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 20)
            content
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(p.foreground)
    }
}

extension PageFrame where Actions == EmptyView {
    init(title: String, lead: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, lead: lead, actions: { EmptyView() }, content: content)
    }
}

/// Пункт подменю страницы
struct NavLink: View {
    let title: String
    let active: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .tw(14, lh: 20)
                .foregroundStyle(active || hover ? p.foreground : p.mutedFg)
                .padding(.vertical, 6).padding(.leading, 12).padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(active ? p.foreground.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .overlay(alignment: .leading) {
                    if active { Capsule().fill(p.glow).frame(width: 2).padding(.vertical, 6).shadow(color: p.glowSoft, radius: 4) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Карточка ширины переписки (`WidthSetting`): миниатюра окна с колонкой нужной ширины
struct WidthCard: View {
    @Bindable var app: AppModel
    let width: ChatWidth

    @Environment(\.palette) private var p
    @State private var hover = false

    private var info: (String, String, CGFloat) {
        switch width {
        case .normal: ("Обычно", "удобно читать", 0.46)
        case .wide: ("Шире", "для кода и таблиц", 0.66)
        case .full: ("Ещё шире", "почти весь экран", 0.9)
        }
    }

    var body: some View {
        let active = app.prefs.chatWidth == width
        Button { app.update { $0.chatWidth = width } } label: {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    let side = g.size.width * 0.18
                    let col = (g.size.width - side) * info.2
                    ZStack(alignment: .topLeading) {
                        p.background
                        p.sidebar.frame(width: side).overlay(alignment: .trailing) { p.border.frame(width: 1) }
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(p.secondary).frame(width: col / 2, height: 8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Capsule().fill(p.foreground.opacity(0.15)).frame(height: 6)
                            Capsule().fill(p.foreground.opacity(0.15)).frame(width: col * 5 / 6, height: 6)
                            Capsule().fill(p.foreground.opacity(0.15)).frame(width: col * 2 / 3, height: 6)
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6).strokeBorder(active ? p.glow.opacity(0.4) : p.border).frame(height: 16)
                                .shadow(color: active ? p.glowSoft : .clear, radius: 6)
                        }
                        .padding(.top, 12).padding(.bottom, 10)
                        .frame(width: col)
                        .frame(width: g.size.width - side)
                        .offset(x: side)
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: R.lg))
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(info.0).font(.geist(14, .medium))
                        Text(info.1).font(.geist(12)).foregroundStyle(p.mutedFg)
                    }
                    Spacer()
                    if active { Icon("check", 16).foregroundStyle(p.glow) }
                }
                .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
            }
            .foregroundStyle(p.foreground)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(active ? p.glow.opacity(0.5) : (hover ? p.foreground.opacity(0.2) : p.border)))
            .shadow(color: active ? p.glowSoft : .clear, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: R.xxl))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// ChatGPT через официальный codex по подписке ChatGPT: вход в браузере, модели GPT появляются в выборе модели
struct ChatGPTCard: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    var body: some View {
        SettingsCard(title: "Подписка ChatGPT", icon: "message-circle", status: AnyView(status)) {
            VStack(alignment: .leading, spacing: 0) {
                switch app.codex {
                case .checking:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Ищу Codex…").font(.geist(13.5)) }
                case .notInstalled:
                    Text("Lumen говорит с ChatGPT через официальный Codex от OpenAI. Поставь его в терминале и нажми «Проверить»:")
                        .font(.geist(13.5)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                    Text("npm install -g @openai/codex")
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                    LButton(title: "Проверить", icon: "refresh-cw", kind: .outline, small: true) { Task { await app.refreshCodex() } }
                        .padding(.top, 16)
                case .signedOut, .signingIn:
                    Text("Войди аккаунтом ChatGPT — откроется браузер. После входа модели GPT появятся в выборе модели в чате и у агента.")
                        .font(.geist(13.5)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                    LButton(title: "Войти через ChatGPT", kind: .primary, busy: app.codex == .signingIn) { Task { await app.codexSignIn() } }
                        .padding(.top, 16)
                case .signedIn:
                    Text("Вход через Codex на этом Маке. В выборе модели: \(ChatModel.gpt.map(\.name).joined(separator: ", ")).")
                        .font(.geist(13.5)).fixedSize(horizontal: false, vertical: true)
                    Text("Агент на ChatGPT правит файлы только в своей папке и без сети — push сделать не может.")
                        .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
                    LButton(title: "Выйти", icon: "log-out", kind: .ghost, small: true) { Task { await app.codexSignOut() } }
                        .padding(.top, 12)
                }
            }
        }
    }

    private var status: some View {
        switch app.codex {
        case .signedIn: StatusDot(on: true, text: "подключено")
        case .checking: StatusDot(on: false, text: "проверяю")
        default: StatusDot(on: false, text: "не подключено")
        }
    }
}

struct SubscriptionCard: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var confirmSignOut = false

    var body: some View {
        SettingsCard(title: "Подписка Claude Code", icon: "square-terminal", status: AnyView(status)) {
            VStack(alignment: .leading, spacing: 0) {
                switch app.claude {
                case .checking:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Ищу Claude Code…").font(.geist(13.5)) }
                case .notInstalled:
                    Text("Claude Code не найден на этом Маке. Поставь его с claude.com/code, войди и нажми «Проверить».")
                        .font(.geist(13.5)).foregroundStyle(p.mutedFg)
                    buttons(signedIn: false)
                case .tooOld(let v):
                    Text("Claude Code \(v.description) слишком старый, нужен \(ClaudeCLI.minimumVersion.description) или новее. Обнови в терминале: claude update")
                        .font(.geist(13.5)).foregroundStyle(p.mutedFg)
                    buttons(signedIn: false)
                case .signedOut:
                    Text("Войди тем же аккаунтом, что и в Claude Code. Откроется браузер.")
                        .font(.geist(13.5)).foregroundStyle(p.mutedFg)
                    LButton(title: "Войти через браузер", kind: .primary, busy: app.subscriptionBusy) { Task { await app.signIn() } }
                        .padding(.top, 16)
                case .signedIn(let v, let auth):
                    Text("Тариф \(auth.planName ?? "—"), вход через Claude Code на этом Маке").font(.geist(13.5))
                    if let email = auth.email {
                        Text(email).font(.geist(12)).foregroundStyle(p.mutedFg).padding(.top, 2)
                    }
                    meters.padding(.top, 16)
                    if v < AppModel.opus55Version {
                        Text("Opus 5.5 работает с Claude Code \(AppModel.opus55Version.description), у тебя \(v.description). Обнови в терминале: claude update")
                            .font(.geist(12)).foregroundStyle(p.glow).padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let check = app.subscriptionCheck {
                        Text(check).font(.geist(12)).foregroundStyle(check.hasPrefix("Подписка") ? Palette.ok : Palette.destructive)
                            .padding(.top, 12)
                    }
                    buttons(signedIn: true)
                case .failed(let m):
                    Text(m).font(.geist(13)).foregroundStyle(Palette.destructive)
                    buttons(signedIn: false)
                }
            }
        }
        .confirmationDialog("Выйти из Claude Code?", isPresented: $confirmSignOut) {
            Button("Выйти", role: .destructive) { Task { await app.signOut() } }
        } message: {
            Text("Выход общий: Claude Code в терминале тоже выйдет из аккаунта.")
        }
    }

    private var status: some View {
        switch app.claude {
        case .signedIn: StatusDot(on: true, text: "подключено")
        case .failed: StatusDot(on: false, text: "ошибка", bad: true)
        case .checking: StatusDot(on: false, text: "проверяю")
        default: StatusDot(on: false, text: "не подключено")
        }
    }

    @ViewBuilder private var meters: some View {
        if app.usage.isEmpty {
            Text(app.usageError ?? "Узнаю лимиты…").font(.geist(12)).foregroundStyle(p.mutedFg)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(app.usage.enumerated()), id: \.offset) { _, w in
                    Meter(label: label(w.kind), value: w.percent, note: resetNote(w.resetsAt))
                }
            }
        }
    }

    private func buttons(signedIn: Bool) -> some View {
        HStack(spacing: 8) {
            LButton(title: "Проверить", icon: "refresh-cw", kind: .outline, small: true, busy: app.subscriptionBusy) {
                Task { await app.checkSubscription() }
            }
            if signedIn {
                LButton(title: "Выйти", icon: "log-out", kind: .ghost, small: true) { confirmSignOut = true }
            }
        }
        .padding(.top, 20)
    }

    private func label(_ k: UsageWindow.Kind) -> String {
        switch k {
        case .session: "5-часовое окно"
        case .week: "Неделя"
        case .weekModel(let m): "Неделя, \(m)"
        }
    }

    static func resetNote(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = formatter
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: Date()) ? "'сброс в' HH:mm"
            : (Calendar.current.isDateInTomorrow(d) ? "'сброс завтра в' HH:mm" : "'сброс' d MMM 'в' HH:mm")
        return f.string(from: d)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private func resetNote(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = Self.formatter
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: Date()) ? "'сброс в' HH:mm"
            : (Calendar.current.isDateInTomorrow(d) ? "'сброс завтра в' HH:mm" : "'сброс' d MMM 'в' HH:mm")
        return f.string(from: d)
    }
}

/// Ключ Anthropic API: проверка настоящим запросом, хранение в Связке ключей
struct ApiKeyCard: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    @State private var key = ""

    var body: some View {
        SettingsCard(title: "Anthropic API", icon: "key-round", status: AnyView(status)) {
            VStack(alignment: .leading, spacing: 0) {
                if !app.prefs.apiKeys.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(app.prefs.apiKeys) { k in KeyRow(app: app, entry: k) }
                    }
                    .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    .padding(.bottom, 14)
                    Text(app.prefs.apiKeys.count > 1 ? "Выбранный ключ используется для всех разговоров через API. Можно переключать." : "Добавь ещё ключ — сможешь переключаться между ними.")
                        .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.bottom, 10)
                }
                Text(app.prefs.apiKeys.isEmpty ? "Ключ" : "Добавить ключ").font(.geist(12, .medium)).foregroundStyle(p.mutedFg).padding(.bottom, 6)
                KeyField(app: app, key: $key, adding: !app.prefs.apiKeys.isEmpty)
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("В этом месяце").font(.geist(12)).foregroundStyle(p.mutedFg)
                        Text("$\(Money.string(app.apiSpentThisMonth))").font(.geist(24, .semibold)).tracking(-0.48).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Остановиться на").font(.geist(12)).foregroundStyle(p.mutedFg)
                        HStack(spacing: 4) {
                            Text("$")
                            TextField("", value: Binding(get: { app.prefs.monthlyLimit }, set: { v in app.update { $0.monthlyLimit = max(1, v) } }),
                                      format: .number)
                                .textFieldStyle(.plain).frame(width: 48).monospacedDigit()
                            Text("в месяц").foregroundStyle(p.mutedFg)
                        }
                        .font(.geist(14))
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    }
                }
                .padding(.top, 20)

            }
        }
    }

    private var status: some View {
        switch app.keyState {
        case .ok: StatusDot(on: true, text: "ключ работает")
        case .saved: StatusDot(on: true, text: "ключ сохранён")
        case .rejected: StatusDot(on: false, text: "ключ не подошёл", bad: true)
        case .noNetwork: StatusDot(on: false, text: "нет сети", bad: true)
        case .error: StatusDot(on: false, text: "ошибка", bad: true)
        case .checking: StatusDot(on: false, text: "проверяю")
        case .none: StatusDot(on: false, text: "нет ключа")
        }
    }
}


/// Строка ключа: выбрать, переименовать, удалить. Сам ключ не показывается — только последние знаки.
private struct KeyRow: View {
    @Bindable var app: AppModel
    let entry: ApiKeyEntry

    @Environment(\.palette) private var p
    @State private var name = ""
    @State private var hover = false

    private var active: Bool { app.prefs.activeKeyID == entry.id }

    var body: some View {
        HStack(spacing: 12) {
            Button { app.useKey(entry.id) } label: {
                Circle().strokeBorder(active ? p.glow : p.foreground.opacity(0.3), lineWidth: 1.5)
                    .overlay { if active { Circle().fill(p.glow).padding(4) } }
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(active ? "Используется" : "Использовать этот ключ")
            TextField("Название", text: $name).textFieldStyle(.plain).font(.geist(14))
                .frame(maxWidth: 180)
                .onSubmit { app.renameKey(entry.id, name) }
            Text("sk-ant-…\(entry.tail)").font(.system(size: 12, design: .monospaced)).foregroundStyle(p.mutedFg)
            Spacer()
            if active { Text("используется").font(.geist(12)).foregroundStyle(Palette.ok) }
            IconButton(icon: "trash", help: "Удалить ключ") { app.deleteKey(entry.id) }.opacity(hover ? 1 : 0.4)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
        .onHover { hover = $0 }
        .onAppear { name = entry.name }
        .onChange(of: name) { _, n in app.renameKey(entry.id, n) }
    }
}
