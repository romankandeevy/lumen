import LumenCore
import LumenProviders
import SwiftUI

/// Настройки (`pages/settings-page.tsx`): шапка страницы, слева узкое подменю, справа выбранный раздел.
/// Разделы — вкладками (Рома попросил, 16.10). Только то, что работает: без «Голоса», «Горячих клавиш»,
/// «Своих тем», «Других моделей».
struct SettingsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p

    enum Section: String, CaseIterable {
        case look = "Внешний вид"
        case models = "Модели и оплата"
        case data = "Данные"
    }

    /// Вкладка живёт в `app.page`: карточка профиля открывает сразу «Модели и оплата»
    private var current: Section {
        if case .settings(let s) = app.page { return s }
        return .look
    }

    var body: some View {
        PageFrame(title: "Настройки") {
            HStack(alignment: .top, spacing: 40) {
                nav
                ScrollView {
                    Group {
                        switch current {
                        case .look: section(.look) { look }
                        case .models: section(.models, lead: "Через что Lumen думает. Можно держать оба: подписку на каждый день и ключ API про запас.") { models }
                        case .data: section(.data) { data }
                        }
                    }
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
                .scrollIndicators(.never)
                .id(current) // новая вкладка открывается с начала
            }
        }
        .task { if app.claude == .checking { await app.refreshClaude() } }
    }

    /// w-40, пункт py-1.5 pr-2 pl-3 text-sm rounded-md, текущий — bg-foreground/[0.05] и световая черта
    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases, id: \.self) { s in
                NavLink(title: s.rawValue, active: current == s) {
                    withAnimation(.easeOut(duration: 0.18)) { app.page = .settings(s) }
                }
            }
        }
        .frame(width: 160)
        .padding(.top, 4)
    }

    private func section<C: View>(_ s: Section, lead: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.rawValue).font(.geist(18, .semibold)).tracking(-0.18)
            if let lead {
                Text(lead).font(.geist(14)).foregroundStyle(p.mutedFg).padding(.top, 4).frame(maxWidth: 560, alignment: .leading)
            }
            content().padding(.top, 16)
        }
    }

    // MARK: внешний вид

    private var look: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle(text: "Тема")
            ThreeColumns {
                ThemeCard(app: app, theme: .lumen, name: "Люмен", note: "Тёплая темнота и свет")
                ThemeCard(app: app, theme: .mono, name: "Монохром", note: "Чёрно-белая, как Пульт")
            }
            GroupTitle(text: "Ширина переписки", aside: "чат и агент").padding(.top, 32)
            ThreeColumns(empty: 0) {
                ForEach(ChatWidth.allCases, id: \.self) { w in WidthCard(app: app, width: w) }
            }
            HStack(spacing: 12) {
                LSwitch(isOn: Binding(get: { app.prefs.reducedMotion }, set: { v in app.update { $0.reducedMotion = v } }))
                Text("Меньше движения").font(.geist(14))
                Text("сфера не дышит, свет не мерцает").font(.geist(12)).foregroundStyle(p.mutedFg)
            }
            .padding(.top, 24)
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
        }
    }

    // MARK: данные

    private var data: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Всё хранится на этом Маке").font(.geist(14))
            Text(app.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(p.mutedFg)
                .textSelection(.enabled)
            Text("Память, история чатов, настройки. Ничего не уходит в облако, кроме самих запросов к модели. Ключ API — в Связке ключей.")
                .font(.geist(12)).foregroundStyle(p.mutedFg)
            HStack(spacing: 8) {
                LButton(title: "Показать в Finder", icon: "folder", kind: .outline, small: true) { app.showDataInFinder() }
                LButton(title: "Пройти знакомство заново", icon: "sparkles", kind: .ghost, small: true) { app.restartOnboarding() }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
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
                    Text(title).font(.geist(26.4, .semibold)).tracking(-0.53)
                    if let lead {
                        Text(lead).font(.geist(14)).foregroundStyle(p.mutedFg).frame(maxWidth: 560, alignment: .leading)
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
                .font(.geist(14))
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
                    if active { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.glow) }
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

struct SubscriptionCard: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var confirmSignOut = false

    var body: some View {
        SettingsCard(title: "Подписка Claude Code", icon: "terminal", status: AnyView(status)) {
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
            LButton(title: "Проверить", icon: "arrow.clockwise", kind: .outline, small: true, busy: app.subscriptionBusy) {
                Task { await app.checkSubscription() }
            }
            if signedIn {
                LButton(title: "Выйти", icon: "rectangle.portrait.and.arrow.right", kind: .ghost, small: true) { confirmSignOut = true }
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

    @State private var key = ""

    var body: some View {
        SettingsCard(title: "Anthropic API", icon: "key", status: AnyView(status)) {
            VStack(alignment: .leading, spacing: 0) {
                KeyField(app: app, key: $key)
                if app.savedKeyTail != nil {
                    LButton(title: "Удалить ключ", icon: "trash", kind: .ghost, small: true) { app.forgetKey() }
                        .padding(.top, 12)
                }
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
