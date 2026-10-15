import LumenCore
import SwiftUI

/// Знакомство при первом запуске (`pages/onboarding.tsx`): имя и обращение → через что думать → тема.
/// Ответы сразу кладутся в память: Lumen с первого чата знает, с кем говорит.
struct OnboardingView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var step = -1 // -1 — приветствие
    @State private var name = ""
    @State private var address: Address = .ty
    @State private var backend: Backend = .subscription
    @State private var key = ""

    /// Шаг «Ключ» есть, только если выбран API
    private var steps: [String] { backend == .api ? ["Знакомство", "Модель", "Ключ", "Тема"] : ["Знакомство", "Модель", "Тема"] }
    private var current: String { steps[step] }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(p.background.opacity(0.8)).ignoresSafeArea()
            VStack(spacing: 0) {
                if step == -1 { hello } else { wizard }
            }
            .padding(40)
            .frame(width: 512)
            .background(LumenLight())
            .background(p.card.opacity(0.8), in: RoundedRectangle(cornerRadius: R.xxxl))
            .clipShape(RoundedRectangle(cornerRadius: R.xxxl))
            .overlay(RoundedRectangle(cornerRadius: R.xxxl).strokeBorder(p.border))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        .onAppear {
            name = app.profile.name
            address = app.profile.address
            backend = app.prefs.backend
        }
    }

    private var hello: some View {
        VStack(spacing: 0) {
            Orb(state: .thinking, size: 96)
            Text("Привет. Я Lumen.")
                .font(.geist(30, .semibold)).tracking(-0.9)
                .padding(.top, 40)
            Text("Я помню тебя и твои проекты между разговорами, понимаю, с кем говорю, и отвечаю так, как ты настроишь. Давай познакомимся — это минута.")
                .font(.geist(14)).foregroundStyle(p.mutedFg)
                .multilineTextAlignment(.center).lineSpacing(4)
                .frame(maxWidth: 360)
                .padding(.top, 12)
            LButton(title: "Познакомиться", kind: .glow) { withAnimation { step = 0 } }
                .padding(.top, 32)
            Button("Пропустить") { app.update { $0.onboarded = true } }
                .buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
                .padding(.top, 12)
        }
        .foregroundStyle(p.foreground)
    }

    private var wizard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Orb(size: 22)
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule().fill(i <= step ? p.glow : p.foreground.opacity(0.1))
                            .frame(height: 4)
                            .shadow(color: i <= step ? p.glowSoft : .clear, radius: 4)
                    }
                }
                Text("\(step + 1) из \(steps.count)").font(.geist(12)).foregroundStyle(p.mutedFg).monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 0) {
                switch current {
                case "Знакомство": nameStep
                case "Модель": backendStep
                case "Ключ": keyStep
                default: themeStep
                }
            }
            .frame(minHeight: 256, alignment: .top)
            .padding(.top, 32)

            HStack {
                LButton(title: "Назад", icon: "arrow.left", kind: .ghost) { withAnimation { step -= 1 } }
                Spacer()
                if step < steps.count - 1 {
                    LButton(title: "Дальше", kind: .primary) { withAnimation { step += 1 } }
                        .disabled(!canContinue)
                } else {
                    LButton(title: "Начать", icon: "checkmark", kind: .glow) {
                        app.finishOnboarding(name: name, address: address, backend: backend, theme: app.prefs.theme)
                    }
                }
            }
            .padding(.top, 24)
        }
        .foregroundStyle(p.foreground)
    }

    private var canContinue: Bool {
        switch current {
        case "Знакомство": !name.trimmingCharacters(in: .whitespaces).isEmpty
        case "Модель": backend == .api || app.claudeReady
        case "Ключ": app.keyState == .ok || app.keyState == .saved
        default: true
        }
    }

    private func heading(_ title: String, _ lead: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.geist(20, .semibold)).tracking(-0.4)
            Text(lead).font(.geist(13.5)).foregroundStyle(p.mutedFg)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Как к тебе обращаться?", "Запомню это первым фактом о тебе.")
            GlowField(placeholder: "Имя", text: $name) {
                if !name.isEmpty { withAnimation { step = 1 } }
            }
            .padding(.top, 24)
            Segmented(value: $address, options: [(.ty, "Можно на «ты»"), (.vy, "Лучше на «вы»")])
                .padding(.top, 16)
        }
    }

    private var backendStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Через что мне думать?", "Можно поменять потом в настройках, «Модели и оплата».")
                .padding(.bottom, 16)
            ChoiceCard(title: "Подписка Claude Code", note: app.claudeOnboardingNote, icon: "terminal",
                       active: backend == .subscription) { backend = .subscription }
            if case .signedOut = app.claude {
                LButton(title: "Войти через браузер", kind: .outline, small: true, busy: app.subscriptionBusy) {
                    Task { await app.signIn() }
                }
            }
            ChoiceCard(title: "Ключ Anthropic API", note: "Вставишь ключ на следующем экране", icon: "key",
                       active: backend == .api) { backend = .api }
        }
        .task { if app.claude == .checking { await app.refreshClaude() } }
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Ключ Anthropic API", "Ключ из console.anthropic.com. Хранится в Связке ключей macOS.")
            KeyField(app: app, key: $key).padding(.top, 24)
        }
    }

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Как мне выглядеть?", "Обе тёмные.")
            HStack(spacing: 12) {
                ThemeCard(app: app, theme: .lumen, name: "Люмен", note: "тёплый свет", compact: true)
                ThemeCard(app: app, theme: .mono, name: "Монохром", note: "как Пульт", compact: true)
            }
            .padding(.top, 24)
        }
    }
}

extension AppModel {
    /// Подписку можно выбрать, только если claude найден и вход есть
    var claudeReady: Bool {
        if case .signedIn = claude { return true }
        return false
    }

    var claudeOnboardingNote: String {
        switch claude {
        case .checking: "Ищу Claude Code на этом Маке…"
        case .notInstalled: "Claude Code не найден. Поставь его с claude.com/code и вернись"
        case .tooOld(let v): "Claude Code \(v) слишком старый. Обнови: claude update"
        case .signedOut: "Нашёл Claude Code — войди тем же аккаунтом через браузер"
        case .signedIn(_, let a): "Нашёл Claude Code на этом Маке — вход уже есть" + (a.planName.map { ", тариф \($0)" } ?? "")
        case .failed(let m): m
        }
    }
}

/// Свет Люмена падает на окно сверху слева — от сферы (`.lumen-light::before`):
/// эллипс 900×520 в 6%/−8% и 600×300 в 50%/120%, оба glow-faint → прозрачно на 70%.
/// Когда Lumen думает, свет сильнее (`--light-level` 1.9).
struct LumenLight: View {
    var level: Double = 1

    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                spot(rx: 900, ry: 520).position(x: g.size.width * 0.06, y: g.size.height * -0.08)
                spot(rx: 600, ry: 300).position(x: g.size.width * 0.5, y: g.size.height * 1.2)
            }
        }
        .opacity(level)
        .animation(.easeInOut(duration: 1.2), value: level)
        .allowsHitTesting(false)
    }

    private func spot(rx: CGFloat, ry: CGFloat) -> some View {
        Rectangle()
            .fill(EllipticalGradient(stops: [.init(color: p.glowFaint, location: 0), .init(color: .clear, location: 0.7)],
                                     center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: rx * 2, height: ry * 2)
    }
}

/// Карточка темы. В настройках (`ThemeCard`): p-2 rounded-2xl, миниатюра окна h-24 в цветах темы.
/// В знакомстве: rounded-2xl border p-4 на фоне самой темы, сфера 28 и подпись.
struct ThemeCard: View {
    @Bindable var app: AppModel
    let theme: Theme
    let name: String
    let note: String
    var compact = false

    @Environment(\.palette) private var current
    @State private var hover = false

    var body: some View {
        let t = Palette.of(theme)
        let active = app.prefs.theme == theme
        Button { app.update { $0.theme = theme } } label: {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 0) {
                        Orb(size: 28).environment(\.palette, t)
                        Text(name).font(.geist(14, .medium)).foregroundStyle(t.foreground).padding(.top, 24)
                        Text(note).font(.geist(12)).foregroundStyle(t.mutedFg)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.background, in: RoundedRectangle(cornerRadius: R.xxl))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        preview(t)
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(name).font(.geist(14, .medium))
                                Text(note).font(.geist(12)).foregroundStyle(current.mutedFg)
                            }
                            Spacer()
                            if active { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(current.glow) }
                        }
                        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
                    }
                    .foregroundStyle(current.foreground)
                    .padding(8)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(active ? current.glow.opacity(compact ? 0.6 : 0.5) : (hover ? current.foreground.opacity(0.2) : current.border)))
            .shadow(color: active ? current.glowSoft : .clear, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: R.xxl))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    /// Миниатюра окна: панель 1/4 со сферой 10, строки переписки, поле ввода со свечением
    private func preview(_ t: Palette) -> some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                t.background
                t.sidebar.frame(width: g.size.width / 4)
                    .overlay(alignment: .topLeading) { Orb(size: 10, animated: false).environment(\.palette, t).padding(8) }
                    .overlay(alignment: .trailing) { t.border.frame(width: 1) }
                let left = g.size.width * 0.32, right: CGFloat = 16
                let w = g.size.width - left - right
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(t.secondary).frame(width: w / 2, height: 10).frame(maxWidth: .infinity, alignment: .trailing)
                    Capsule().fill(t.muted).frame(width: w * 5 / 6, height: 8)
                    Capsule().fill(t.muted).frame(width: w * 2 / 3, height: 8)
                }
                .frame(width: w)
                .offset(x: left, y: 16)
                RoundedRectangle(cornerRadius: R.md).strokeBorder(t.border).frame(width: w, height: 16)
                    .shadow(color: t.glowSoft, radius: 7)
                    .offset(x: left, y: g.size.height - 12 - 16)
            }
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: R.xl))
    }
}

/// Поле ключа API с «показать», «Проверить» и понятными ошибками — общее для знакомства и настроек
struct KeyField: View {
    @Bindable var app: AppModel
    @Binding var key: String

    @Environment(\.palette) private var p
    @State private var show = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlowField(placeholder: app.savedKeyTail.map { "sk-ant-…  (сохранён, ••••\($0))" } ?? "sk-ant-…",
                          text: $key, secure: !show, mono: true, onSubmit: check) {
                    Button { show.toggle() } label: {
                        Image(systemName: show ? "eye.slash" : "eye").font(.system(size: 13)).foregroundStyle(p.mutedFg)
                    }
                    .buttonStyle(.plain)
                    .help(show ? "Скрыть ключ" : "Показать ключ")
                }
                LButton(title: "Проверить", kind: .outline, busy: app.keyState == .checking, action: check)
                    .disabled(key.isEmpty && app.savedKeyTail == nil)
            }
            if let error = keyError {
                Text(error).font(.geist(12)).foregroundStyle(Palette.destructive)
            } else if app.keyState == .ok {
                Text("Ключ работает и сохранён").font(.geist(12)).foregroundStyle(Palette.ok)
            }
            Text("Ключ хранится в Связке ключей macOS и никуда не уходит, кроме Anthropic.")
                .font(.geist(12)).foregroundStyle(p.mutedFg)
        }
    }

    private func check() {
        Task {
            await app.checkKey(key)
            if app.keyState == .ok { key = "" }
        }
    }

    private var keyError: String? {
        switch app.keyState {
        case .rejected: "Ключ не подошёл. Он начинается с sk-ant- — скопируй его заново в console.anthropic.com."
        case .noNetwork: "Нет связи с Anthropic. Проверь интернет и нажми «Проверить» ещё раз."
        case .error(let m): m
        default: nil
        }
    }
}
