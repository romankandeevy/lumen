import AppKit
import LumenCore
import SwiftUI

/// «Характер» (макет 10-persona): слева — как Lumen говорит, думает и действует; справа — живое превью: тот же вопрос,
/// ответ пишет настоящая модель (Haiku) с этими инструкциями; внизу — сами инструкции, которые получает модель.
/// Сохранённое действует со следующего ответа во всех чатах и задачах агента.
struct PersonaView: View {
    @Bindable var app: AppModel
    /// Внутри настроек: шапка меньше, без своих полей вокруг, превью уже
    var embedded = false

    @Environment(\.palette) private var p
    @State private var draft = Persona()
    @State private var loaded = false
    @State private var showSoul = false
    @State private var saved = false

    private var dirty: Bool { loaded && draft != app.persona }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: embedded ? 4 : 6) {
                    Text("Характер").font(.geist(embedded ? 20 : 28, .semibold))
                    Text("Как Lumen думает вслух и отвечает. Меняй слева — справа видно, как он ответит.")
                        .font(.geist(14)).foregroundStyle(p.mutedFg)
                }
                Spacer()
                HStack(spacing: 8) {
                    if saved && !dirty { Text("Сохранено — со следующего ответа").tw(12, lh: 16).foregroundStyle(p.mutedFg) }
                    LButton(title: "Сбросить", icon: "rotate-ccw", kind: .ghost) { draft = Persona() }
                        .disabled(draft == Persona())
                    LButton(title: "Сохранить", kind: .primary) {
                        app.savePersona(draft)
                        saved = true
                    }
                    .disabled(!dirty)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .padding(.bottom, 24)

            HStack(alignment: .top, spacing: 32) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        who
                        speech
                        thinking
                        rules
                        soulBlock
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity)

                PersonaPreview(app: app, persona: draft)
                    .frame(width: embedded ? 340 : 400)
            }
        }
        .padding(.horizontal, embedded ? 0 : 40).padding(.top, embedded ? 0 : 48)
        .frame(maxWidth: 1200, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(p.foreground)
        .onAppear {
            if !loaded { draft = app.persona; loaded = true }
        }
        .onChange(of: draft) { saved = false }
    }

    // MARK: разделы

    private var who: some View {
        section("Кто он") {
            HStack(alignment: .top, spacing: 16) {
                field("Имя") {
                    TextField("", text: $draft.name).textFieldStyle(.plain).font(.geist(14))
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                }
                .frame(width: 170)
                field("Кто он — своими словами") {
                    TextField("", text: $draft.about, axis: .vertical).textFieldStyle(.plain).font(.geist(14))
                        .lineLimit(2...5)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                }
            }
        }
    }

    private var speech: some View {
        section("Как говорит") {
            VStack(alignment: .leading, spacing: 18) {
                grid {
                    field("Тон") { Segmented(value: $draft.warmth, options: [(.warm, "Тёплый"), (.plain, "Ровный"), (.dry, "Сухой")]) }
                    field("Длина ответов") { Segmented(value: $draft.length, options: [(.short, "Коротко"), (.medium, "Средне"), (.long, "Подробно")]) }
                }
                grid {
                    field("Язык") { Segmented(value: $draft.language, options: [(.ru, "Всегда русский"), (.match, "Как пишешь ты")]) }
                    field("Юмор") { Segmented(value: $draft.humor, options: [(.none, "Без шуток"), (.light, "Чуть-чуть"), (.more, "Почаще")]) }
                }
                grid {
                    field("Оформление") { Segmented(value: $draft.format, options: [(.prose, "Текстом"), (.lists, "Списками"), (.mixed, "Смешанно")]) }
                    field("Эмодзи") {
                        HStack(spacing: 10) {
                            LSwitch(isOn: $draft.emoji)
                            Text(draft.emoji ? "Иногда можно" : "Без эмодзи").font(.geist(14))
                        }
                        .frame(height: 44)
                    }
                }
                field("Запрещённые слова — он их не скажет") { WordChips(items: $draft.bannedWords, placeholder: "добавить слово") }
            }
        }
    }

    private var thinking: some View {
        section("Как думает и действует") {
            VStack(alignment: .leading, spacing: 18) {
                grid {
                    field("Самостоятельность", hint: ["ask": "Всё спрашивает перед делом", "suggest": "Предлагает шаг и ждёт OK",
                                                      "act": "Делает сам, потом рассказывает"][draft.initiative.rawValue]) {
                        Segmented(value: $draft.initiative, options: [(.ask, "Спрашивать"), (.suggest, "Предлагать"), (.act, "Делать сам")])
                    }
                    field("Честность", hint: draft.honesty == .plain ? "Говорит как есть, даже если неприятно" : "Смягчает, но суть не прячет") {
                        Segmented(value: $draft.honesty, options: [(.plain, "Прямо"), (.soft, "Мягко")])
                    }
                }
                grid {
                    field("Рассуждения", hint: ["result": "Только ответ", "brief": "Ответ и пара слов почему", "full": "Показывает ход мыслей"][draft.reasoning.rawValue]) {
                        Segmented(value: $draft.reasoning, options: [(.result, "Только итог"), (.brief, "Коротко"), (.full, "Подробно")])
                    }
                    field("Подсказывать о висящем") {
                        HStack(spacing: 10) {
                            LSwitch(isOn: $draft.nudges)
                            Text(draft.nudges ? "Напоминает о неотправленном и забытом" : "Только по делу").font(.geist(14))
                        }
                        .frame(height: 44)
                    }
                }
            }
        }
    }

    private var rules: some View {
        section("Правила") {
            grid {
                field("Всегда") { RuleEditor(items: $draft.always, placeholder: "Например: называть файл и строку", negative: false) }
                field("Никогда") { RuleEditor(items: $draft.never, placeholder: "Например: извиняться", negative: true) }
            }
        }
    }

    private var soulBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { showSoul.toggle() } } label: {
                IconLabel(text: (showSoul ? "Скрыть" : "Показать") + " инструкции, которые получает модель", icon: "code-xml", size: 14)
                    .font(.geist(13)).foregroundStyle(p.mutedFg)
            }
            .buttonStyle(.plain)
            if showSoul {
                Text(draft.soul(userName: app.profile.name, ty: app.profile.address == .ty))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(p.foreground.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.xl))
                    .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
            }
        }
    }

    // MARK: раскладка

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.geist(16, .semibold))
            content()
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { p.border.frame(height: 1) }
    }

    private func grid<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 24) { content() }
    }

    private func field<C: View>(_ label: String, hint: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            content()
            if let hint { Text(hint).tw(12, lh: 16).foregroundStyle(p.mutedFg.opacity(0.8)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Превью: тот же вопрос, ответ пишет настоящая модель с текущими настройками — только по «Проверить»,
/// чтобы правки не тратили лимиты (Рома, 17.10). Поменял после — прошлый ответ бледнеет с пометкой
struct PersonaPreview: View {
    @Bindable var app: AppModel
    let persona: Persona

    @Environment(\.palette) private var p
    @State private var question = PersonaPreview.questions[0]
    @State private var answers: [String: String] = [:]
    /// Последний ответ на каждый вопрос (с какими бы настройками ни был) — пока не нажали «Проверить» снова
    @State private var last: [String: String] = [:]
    @State private var loading = false

    static let questions = ["Что поделаем сегодня?", "Почему падает Shelf?", "Напиши коммит для правки"]

    private var soul: String { persona.soul(userName: app.profile.name, ty: app.profile.address == .ty) }
    private var key: String { question + "\u{1}" + soul }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Как он ответит").tw(14, .medium, lh: 20)
                Spacer()
                if !app.profile.name.isEmpty { Text("говорит с: \(app.profile.name)").tw(12, lh: 16).foregroundStyle(p.mutedFg) }
            }
            VStack(alignment: .leading, spacing: 16) {
                FlowWrap(spacing: 6) {
                    ForEach(Self.questions, id: \.self) { q in
                        Button { question = q } label: {
                            Text(q).tw(12, lh: 16)
                                .foregroundStyle(q == question ? p.foreground : p.mutedFg)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(q == question ? p.glow.opacity(0.1) : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(q == question ? p.glow.opacity(0.4) : p.border))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Spacer(minLength: 40)
                    Text(question).tw(14, lh: 20)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(p.secondary, in: UnevenRoundedRectangle(topLeadingRadius: R.xxl, bottomLeadingRadius: R.xxl,
                                                                            bottomTrailingRadius: R.md, topTrailingRadius: R.xxl))
                }
                HStack(alignment: .top, spacing: 12) {
                    Orb(state: loading ? .thinking : .idle, size: 20, animated: loading).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 8) {
                        if loading {
                            Text("Пишет…").tw(14, lh: 20).foregroundStyle(p.mutedFg).shimmer(p.foreground)
                        } else if let a = answers[key] {
                            RichText(text: a, caret: false).transition(.opacity)
                        } else if let old = last[question] {
                            RichText(text: old, caret: false).opacity(0.45)
                            Text("Это ответ со старыми настройками — нажми «Проверить»").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        } else if app.cli == nil {
                            Text("Нужен Claude Code — без него превью не написать.").tw(13, lh: 18).foregroundStyle(p.mutedFg)
                        } else {
                            Text("Нажми «Проверить» — модель ответит с этими настройками.").tw(13, lh: 18).foregroundStyle(p.mutedFg)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .animation(.easeOut(duration: 0.25), value: answers[key])
                HStack {
                    Spacer()
                    LButton(title: "Проверить", icon: "sparkles", kind: answers[key] == nil ? .primary : .outline, small: true) { check() }
                        .disabled(loading || app.cli == nil || answers[key] != nil)
                        .help(answers[key] != nil ? "С этими настройками уже проверено" : "Один короткий ответ модели — тратит немного лимита")
                }
            }
            .padding(16)
            .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.xxl))
            .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.border))
            Text("Отвечает настоящая модель (Haiku) с этими инструкциями — только когда нажмёшь «Проверить». В разговоре ответит та модель, что выбрана в поле.")
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
        }
    }

    /// Один ответ модели с текущими настройками; тот же вопрос с теми же настройками второй раз не спрашиваем
    private func check() {
        let k = key, q = question, system = soul
        guard answers[k] == nil, !loading else { return }
        loading = true
        Task {
            let text = await app.quickAsk(q, system: system + "\n\nЭто превью характера: ответь так, как ответил бы в настоящем разговоре, без оговорок, что это пример. Если для ответа нужны данные (файлы, проекты), придумай правдоподобные коротко.")
            loading = false
            if let text, !text.isEmpty {
                let a = text.trimmingCharacters(in: .whitespacesAndNewlines)
                answers[k] = a
                last[q] = a
            }
        }
    }
}

/// Слова-плашки с крестиком и полем «добавить слово»
struct WordChips: View {
    @Binding var items: [String]
    let placeholder: String

    @Environment(\.palette) private var p
    @State private var new = ""

    var body: some View {
        FlowWrap(spacing: 6) {
            ForEach(items, id: \.self) { w in
                HStack(spacing: 6) {
                    Text(w).tw(13, lh: 18)
                    Button { items.removeAll { $0 == w } } label: { Icon("x", 11).foregroundStyle(p.mutedFg) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(p.foreground.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(p.border))
            }
            HStack(spacing: 6) {
                Icon("plus", 11).foregroundStyle(p.mutedFg)
                TextField(placeholder, text: $new).textFieldStyle(.plain).font(.geist(13)).frame(width: 140)
                    .onSubmit(add)
            }
            .padding(.horizontal, 10).frame(height: 28)
        }
    }

    private func add() {
        let w = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if !w.isEmpty, !items.contains(w) { items.append(w) }
        new = ""
    }
}

/// Список правил «Всегда» / «Никогда»: строки с крестиком и поле для нового
struct RuleEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let negative: Bool

    @Environment(\.palette) private var p
    @State private var new = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: negative ? "xmark.circle" : "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(negative ? Palette.destructive.opacity(0.8) : p.glow)
                    Text(r).tw(13, lh: 18).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { items.remove(at: i) } label: { Icon("x", 11).foregroundStyle(p.mutedFg) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.md))
            }
            HStack(spacing: 8) {
                Icon("plus", 12).foregroundStyle(p.mutedFg)
                TextField(placeholder, text: $new).textFieldStyle(.plain).font(.geist(13)).onSubmit(add)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private func add() {
        let r = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { items.append(r) }
        new = ""
    }
}
