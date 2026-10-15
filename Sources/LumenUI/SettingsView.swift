import LumenCore
import LumenProviders
import SwiftUI

/// Настройки (`pages/settings-page.tsx`): слева узкое подменю-якоря, справа секции.
/// Здесь только разделы, которые уже работают.
struct SettingsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var current: Section = .look

    enum Section: String, CaseIterable {
        case look = "Внешний вид"
        case models = "Модели и оплата"
        case data = "Данные"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Настройки")
                .font(.geist(26, .semibold)).tracking(-0.5)
                .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 20)
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 40) {
                    nav(proxy)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 48) {
                            section(.look) { look }
                            section(.models, lead: "Через что Lumen думает. Можно держать оба: подписку на каждый день и ключ API про запас.") { models }
                            section(.data) { data }
                        }
                        .padding(.bottom, 200)
                        .frame(maxWidth: 860, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 32)
            }
        }
        .foregroundStyle(p.foreground)
        .task { if app.claude == .checking { await app.refreshClaude() } }
    }

    private func nav(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases, id: \.self) { s in
                Button {
                    current = s
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(s, anchor: .top) }
                } label: {
                    Text(s.rawValue)
                        .font(.geist(13.5))
                        .foregroundStyle(current == s ? p.foreground : p.mutedFg)
                        .padding(.vertical, 6).padding(.leading, 12)
                        .frame(width: 160, alignment: .leading)
                        .background(current == s ? p.foreground.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .leading) {
                            if current == s {
                                Capsule().fill(p.glow).frame(width: 2).padding(.vertical, 6).shadow(color: p.glowSoft, radius: 4)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func section<C: View>(_ s: Section, lead: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.rawValue).font(.geist(18, .semibold)).tracking(-0.2)
            if let lead {
                Text(lead).font(.geist(13.5)).foregroundStyle(p.mutedFg).padding(.top, 4).frame(maxWidth: 520, alignment: .leading)
            }
            content().padding(.top, 16)
        }
        .id(s)
    }

    // MARK: внешний вид

    private var look: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Тема")
                HStack(spacing: 12) {
                    ThemeCard(app: app, theme: .lumen, name: "Люмен", note: "Тёплая темнота и свет")
                    ThemeCard(app: app, theme: .mono, name: "Монохром", note: "Чёрно-белая, как Пульт")
                }
                .frame(maxWidth: 560)
            }
            Toggle(isOn: Binding(get: { app.prefs.reducedMotion }, set: { v in app.update { $0.reducedMotion = v } })) {
                HStack(spacing: 8) {
                    Text("Меньше движения").font(.geist(13.5))
                    Text("сфера не дышит, свет не мерцает").font(.geist(12)).foregroundStyle(p.mutedFg)
                }
            }
            .toggleStyle(.switch).tint(p.glow)
        }
    }

    // MARK: модели и оплата

    private var models: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Через что отвечать по умолчанию")
                HStack(alignment: .top, spacing: 8) {
                    ChoiceCard(title: "Подписка", note: "Входит в тариф Claude. Есть лимит на 5 часов и на неделю.",
                               active: app.prefs.backend == .subscription) { app.update { $0.backend = .subscription } }
                    ChoiceCard(title: "API", note: "Платишь за токены. Без лимитов по времени.",
                               active: app.prefs.backend == .api) { app.update { $0.backend = .api } }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    SubscriptionCard(app: app).frame(minWidth: 340)
                    ApiKeyCard(app: app).frame(minWidth: 340)
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
            Text("Всё хранится на этом Маке").font(.geist(13.5))
            Text(app.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(p.mutedFg)
                .textSelection(.enabled)
            Text("Профиль, настройки и память. Ничего не уходит в облако, кроме самих запросов к модели. Ключ API — в Связке ключей.")
                .font(.geist(12)).foregroundStyle(p.mutedFg)
            HStack(spacing: 8) {
                LButton(title: "Показать в Finder", icon: "folder", kind: .outline, small: true) { app.showDataInFinder() }
                LButton(title: "Пройти знакомство заново", icon: "sparkles", kind: .ghost, small: true) { app.restartOnboarding() }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.border))
    }
}

/// Подписка Claude Code: вход, тариф, лимиты из `/usage`, настоящая проверка ходом
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

    private func resetNote(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
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
