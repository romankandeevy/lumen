import AppKit
import LumenCore
import LumenProviders
import SwiftUI

// Навыки (`pages/tools-page.tsx`, вкладка навыков): свои и установленные, каталог Anthropic, установка по ссылке,
// создание с Lumen. Модель видит список включённых навыков и сама берёт нужный.

struct SkillsView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var link = ""
    @State private var installing: String?
    @State private var note: String?

    enum Mode: Hashable { case mine, catalog }

    var body: some View {
        PageFrame(title: "Кастомизация",
                  lead: "Навыки, коннекторы и хуки — как в Claude Code, в одной папке. Lumen, агент и боты берут их сами.") {
            HStack(spacing: 8) {
                LButton(title: "Папка", icon: "folder-open", kind: .outline) { app.revealCustomize() }
                    .help("customize/: skills, mcp.json, hooks.json — в формате Claude Code")
                if app.customizeTab == .skills {
                    LButton(title: "Создать навык", icon: "plus", kind: .primary) {
                        app.skillDraft = nil
                        app.page = .skillEditor(nil)
                    }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                Segmented(value: $app.customizeTab, options: [
                    (.skills, "Навыки · \(app.skills.count)"),
                    (.connectors, "Коннекторы · \(app.connectors.mcpServers.count)"),
                    (.hooks, "Хуки · \(app.hooks.count)"),
                ])
                .frame(maxWidth: 480)
                switch app.customizeTab {
                case .skills: skillsTab
                case .connectors: ConnectorsTab(app: app)
                case .hooks: HooksTab(app: app)
                }
            }
        }
        .onAppear { app.reloadSkills(); app.reloadCustomize() }
    }

    @ViewBuilder private var skillsTab: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MiniSegmented(value: $app.skillsMode, options: [(.mine, "Мои, \(app.skills.count)"), (.catalog, "Каталог skills.sh")])
                    GlowField(placeholder: "Ссылка на навык на GitHub", text: $link, icon: "link", compact: true) { install(link) }
                    LButton(title: "Поставить", icon: "download", kind: .ghost, small: true, busy: installing == link && !link.isEmpty) { install(link) }
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || installing != nil)
                }
                if let note {
                    IconLabel(text: note, icon: "circle-check", size: 14).tw(13, lh: 18).foregroundStyle(p.mutedFg)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if app.skillsMode == .mine { mine } else { SkillsCatalog(app: app) }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
            }
    }

    @ViewBuilder private var mine: some View {
        if app.skills.isEmpty {
            VStack(spacing: 8) {
                Text("Навыков пока нет").tw(14, .medium, lh: 20)
                Text("Создай свой с Lumen, поставь из каталога Anthropic или по ссылке. Ещё боты и агент сами предлагают навык после большой задачи.")
                    .tw(13, lh: 18).foregroundStyle(p.mutedFg).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 48)
            .background(p.card.opacity(0.85), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        }
        // две карточки в ряд (Рома, 21.10)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
                  alignment: .leading, spacing: 12) {
            ForEach(app.skills) { s in SkillRow(app: app, skill: s) }
        }
    }

    private func install(_ l: String, origin: SkillInfo.Origin = .github) {
        let link = l.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty, installing == nil else { return }
        installing = link
        note = nil
        Task {
            note = await app.installSkill(link, origin: origin)
            installing = nil
            if origin == .github { self.link = "" }
        }
    }

}

/// Карточка своего навыка (Рома, 21.10): две в ряд, значок в плашке, название и откуда навык, пояснение в две строки,
/// внизу — сколько раз брали и кнопка «Включить» / «Выключить» вместо переключателя. Щелчок по карточке — открыть
private struct SkillRow: View {
    @Bindable var app: AppModel
    let skill: Skill

    @Environment(\.palette) private var p
    @State private var hover = false

    private var on: Bool { skill.info.enabled }

    var body: some View {
        // карточка хендоффа (1.7.3): r12, значок 20 в рамке 36 r8, название 14 полужирным, откуда — 12
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Icon(skill.info.origin == .learned ? "lightbulb" : "book-open-check", 20)
                    .foregroundStyle(on ? p.glow : p.mutedFg)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.borderBase.opacity(0.1)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(skill.name).font(.geist(14, .semibold)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(on ? p.foreground : p.textSoft)
                    Text(on ? origin : origin + " · выключен").font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(skill.description.isEmpty ? "Без описания" : skill.description)
                .tw(13, lh: 19).foregroundStyle(p.textSoft).lineLimit(2)
                // всегда место под две строки: карточки в ряду одной высоты
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                .padding(.top, 10)
            if !skill.info.warnings.isEmpty {
                IconLabel(text: skill.info.warnings.joined(separator: ", "), icon: "triangle-alert", size: 11)
                    .tw(11.5, lh: 15).foregroundStyle(Palette.destructive).lineLimit(1).padding(.top, 6)
            }
            HStack(spacing: 6) {
                let n = app.skillUses[skill.name] ?? 0
                chip(n == 0 ? "ещё не брали" : "брали \(n) " + Plural.form(n, "раз", "раза", "раз"))
                if !skill.files.isEmpty { chip("\(skill.files.count) " + Plural.form(skill.files.count, "файл", "файла", "файлов")) }
                Spacer(minLength: 8)
                ToggleButton(on: on) { app.setSkill(skill, enabled: !on) }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .background(shape.fill(p.borderBase.opacity(hover ? 0.05 : 0.025)))
        .overlay(shape.strokeBorder(p.borderBase.opacity(hover ? 0.18 : 0.12)))
        .contentShape(shape)
        .onTapGesture { app.page = .skillEditor(skill.name) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
        .help("Открыть навык")
        .onRightClick { point in
            app.menu = MenuState(items: [
                MenuItem(title: "Открыть", key: "o") { app.page = .skillEditor(skill.name) },
                MenuItem(title: on ? "Выключить" : "Включить", key: "e") { app.setSkill(skill, enabled: !on) },
                MenuItem(title: "Показать в Finder", key: "f") { NSWorkspace.shared.activateFileViewerSelecting([skill.folder]) },
                MenuItem(title: "Удалить", key: "d", destructive: true, separated: true) { app.removeSkill(skill) },
            ], anchor: point)
        }
    }

    private var origin: String {
        switch skill.info.origin {
        case .created: "Свой"
        case .learned: "Сам научился"
        case .github: "С GitHub"
        case .catalog: "Из skills.sh"
        }
    }

    /// Бейдж хендоффа: пилюля 20, 11 полужирным, тонкая рамка
    private func chip(_ t: String) -> some View {
        Text(t).font(.geist(11, .semibold)).foregroundStyle(p.mutedFg)
            .padding(.horizontal, 7).frame(height: 20)
            .overlay(Capsule().strokeBorder(p.borderBase.opacity(0.14)))
    }
}

/// «Включить» — синяя, «Выключить» — тихая с тонким кольцом (вместо переключателя)
private struct ToggleButton: View {
    let on: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Text(on ? "Выключить" : "Включить")
                .font(.geist(14, .medium))
                .foregroundStyle(on ? (hover ? p.foreground : p.textControl) : .white)
                .padding(.horizontal, 10).frame(height: 28)
                .background {
                    if on {
                        shape.fill(hover ? p.hover : .clear).overlay(shape.strokeBorder(p.borderBase.opacity(hover ? 0.16 : 0.1)))
                    } else {
                        shape.fill(p.accent.opacity(hover ? 0.88 : 1))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(on ? "Выключить — модель перестанет видеть навык" : "Включить — модель снова видит навык")
    }
}

// MARK: редактор навыка

struct SkillEditor: View {
    @Bindable var app: AppModel
    let name: String?

    @Environment(\.palette) private var p
    @State private var request = ""
    @State private var draft = SkillDraft(name: "", description: "", body: "")
    @State private var writing = false
    @State private var problems: [String] = []
    @State private var loaded = false
    @State private var saved: String?
    @State private var context: String?

    private var existing: Skill? { name.flatMap { n in app.skills.first { $0.name == n } } }
    /// Чужой навык (каталог, GitHub) правим осторожно: следующее обновление его перезапишет
    private var readOnlyNote: String? {
        guard let s = existing, s.info.origin == .github || s.info.origin == .catalog else { return nil }
        return "Навык поставлен из \(s.info.source ?? "GitHub"). Правки можно сохранить, но обновление из источника их заменит."
    }

    var body: some View {
        PageFrame(title: existing.map { "Навык «\($0.name)»" } ?? "Новый навык",
                  lead: "Хороший навык: описание точно говорит, когда его брать, а инструкции — шаги с причинами, формат результата и пример.") {
            HStack(spacing: 8) {
                LButton(title: "Отмена", kind: .ghost) { app.page = .skills }
                LButton(title: "Сохранить", icon: "check", kind: .primary) { save() }.disabled(!draft.problems.isEmpty || writing)
            }
        } content: {
            ScrollView {
                HStack(alignment: .top, spacing: 40) {
                    form.frame(maxWidth: 680, alignment: .leading)
                    aside.frame(width: 260)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
        .onAppear(perform: load)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            if existing == nil {
                VStack(alignment: .leading, spacing: 0) {
                    GroupTitle(text: "Что должен уметь навык", aside: "Lumen напишет и проверит")
                    SkillTextEditor(text: $request, placeholder: "Например: готовить заметки к релизу из git log — коротко, по-русски, по разделам «Новое», «Исправлено»", minHeight: 70, mono: false)
                    HStack(spacing: 10) {
                        LButton(title: writing ? "Пишу и перечитываю…" : "Написать с Lumen", icon: "sparkles", kind: .outline, small: true, busy: writing) { write() }
                            .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || writing || app.cli == nil)
                        if app.cli == nil {
                            Text("нужен Claude Code — Настройки → Модели и оплата").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            if let readOnlyNote {
                IconLabel(text: readOnlyNote, icon: "triangle-alert", size: 14).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Имя", aside: "латиница, цифры, дефис")
                GlowField(placeholder: "release-notes", text: $draft.name, mono: true).disabled(existing != nil)
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Когда брать", aside: "\(draft.description.count) / 1024")
                SkillTextEditor(text: $draft.description, placeholder: "Что делает и в каких ситуациях: «Используй, когда просят…, даже если не сказано прямо»", minHeight: 70, mono: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Инструкции", aside: "markdown · \(draft.body.split(separator: "\n", omittingEmptySubsequences: false).count) строк")
                SkillTextEditor(text: $draft.body, placeholder: "## Шаги\n1. …\n\n## Формат результата\n…\n\n## Пример\n…", minHeight: 320, mono: true)
            }
            if !draft.problems.isEmpty && !(draft.name.isEmpty && draft.body.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.problems, id: \.self) { IconLabel(text: $0, icon: "triangle-alert", size: 13).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
                }
            }
            if let saved { IconLabel(text: saved, icon: "circle-check", size: 14).tw(13, lh: 18).foregroundStyle(Palette.ok) }
        }
    }

    private var aside: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !draft.tests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Попробовать").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
                    ForEach(draft.tests, id: \.self) { t in
                        Button { tryIt(t) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Icon("message-square", 13).padding(.top, 2)
                                Text(t).tw(12, lh: 16).multilineTextAlignment(.leading)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
                            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!draft.problems.isEmpty)
                    }
                    Text("Сохранит навык и задаст эту просьбу в новом чате — увидишь, берёт ли его Lumen и как отвечает.")
                        .tw(11, lh: 15).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let s = existing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Папка").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
                    ForEach(["SKILL.md"] + s.files, id: \.self) { f in
                        IconLabel(text: f, icon: "file-text", size: 12).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                    LButton(title: "Показать в Finder", icon: "folder", kind: .ghost, small: true) { NSWorkspace.shared.activateFileViewerSelecting([s.folder]) }
                }
                LButton(title: "Удалить навык", icon: "trash", kind: .ghost, small: true) {
                    app.removeSkill(s)
                    app.page = .skills
                }
                .foregroundStyle(Palette.destructive)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let s = existing {
            draft = SkillDraft(name: s.name, description: s.description, body: s.body)
        } else if let d = app.skillDraft {
            draft = d
            app.skillDraft = nil
        } else if let ctx = app.skillContext {
            // из разговора: Lumen сразу соберёт навык из его шагов и поправок
            request = "Собери навык из разговора «\(ctx.title)»: повторяемый приём, который в нём получился"
            context = ctx.text
            app.skillContext = nil
            write()
        }
    }

    private func write() {
        writing = true
        saved = nil
        Task {
            switch await app.draftSkill(request, context: context) {
            case .success(let d): draft = d
            case .failure(.invalid(_, let d)): draft = d
            case .failure(.noAnswer): saved = nil; problems = ["Lumen не ответил — попробуй ещё раз"]
            }
            writing = false
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let origin: SkillInfo.Origin = existing?.info.origin ?? .created
            _ = try app.saveSkill(draft, origin: origin)
            saved = "Сохранён. Lumen, агент и боты с этим навыком увидят его в следующем ответе."
            return true
        } catch {
            saved = nil
            problems = [error.localizedDescription]
            return false
        }
    }

    private func tryIt(_ text: String) {
        guard save() else { return }
        app.tab = .chat
        app.newChat()
        app.chat.send(text)
    }
}

/// Многострочное поле (инструкции навыка — моноширинным)
private struct SkillTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat
    var mono: Bool

    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(mono ? .system(size: 12, design: .monospaced) : .geist(14)).foregroundStyle(p.mutedFg)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            TextEditor(text: $text)
                .font(mono ? .system(size: 12, design: .monospaced) : .geist(14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7).padding(.vertical, 8)
        }
        .frame(minHeight: minHeight)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
}

/// «Сам научился»: под ответом агента или бота — предложенный навык
struct SkillProposalCard: View {
    let app: AppModel
    let message: ChatMessage
    let draft: SkillDraft

    @Environment(\.palette) private var p
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Icon("lightbulb", 14).foregroundStyle(p.glow)
                Text("Сам научился: предлагаю навык «\(draft.name)»").tw(13, .medium, lh: 18)
            }
            Text(draft.description).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(3)
            if let done {
                Text(done).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            } else {
                HStack(spacing: 8) {
                    LButton(title: "Сохранить навык", icon: "check", kind: .outline, small: true) {
                        if (try? app.saveSkill(draft, origin: .learned)) != nil {
                            done = "Сохранён — в следующий раз возьму его сам."
                            dismiss()
                        }
                    }
                    LButton(title: "Посмотреть", kind: .ghost, small: true) {
                        app.skillDraft = draft
                        app.page = .skillEditor(nil)
                        dismiss()
                    }
                    LButton(title: "Не нужно", kind: .ghost, small: true) { dismiss() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.25)))
    }

    private func dismiss() {
        if let id = message.id { app.chat.attachSkillDraft(nil, to: id, conversationID: message.conversationID) }
    }
}


// MARK: каталог skills.sh

/// Каталог как на skills.sh: рейтинг «за всё время / тренды / горячее» страницами по 100, поиск по всему каталогу,
/// линия активности за 8 недель, установки; можно отметить несколько и поставить разом. Описание — по-русски.
struct SkillsCatalog: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var view: SkillsDirectory.View = .allTime
    @State private var boards: [SkillsDirectory.View: SkillsDirectory.Board] = [:]
    @State private var query = ""
    @State private var found: [SkillsDirectory.Entry]?
    @State private var error: String?
    @State private var loading = false
    @State private var open: String?
    @State private var installing: Set<String> = []
    @State private var selected: [String: SkillsDirectory.Entry] = [:]
    @State private var note: String?
    @State private var page = 0
    @FocusState private var searchFocused: Bool

    static let perPage = 100

    private var all: [SkillsDirectory.Entry] { found ?? boards[view]?.entries ?? [] }
    private var pages: Int { max(1, (all.count + Self.perPage - 1) / Self.perPage) }
    private var rows: ArraySlice<SkillsDirectory.Entry> {
        let start = min(page * Self.perPage, all.count)
        return all[start..<min(start + Self.perPage, all.count)]
    }
    /// У трендов и «горячего» skills.sh не даёт недель — там свои цифры
    private var countTitle: String {
        guard found == nil else { return "УСТАНОВКИ" }
        switch view {
        case .allTime: return "УСТАНОВКИ"
        case .trending: return "ЗА 24 Ч"
        case .hot: return "ЗА ЧАС"
        }
    }
    private var showActivity: Bool { found == nil && view == .allTime }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Icon("search", 14).foregroundStyle(p.mutedFg)
                TextField("Найти навык по всему каталогу…", text: $query).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .focused($searchFocused)
                    .onChange(of: query) { _, q in search(q) }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(searchFocused ? p.foreground.opacity(0.25) : p.border))

            if found == nil {
                HStack(spacing: 18) {
                    tab(.allTime, "За всё время" + (boards[.allTime]?.allTimeTotal.map { " (\(Self.number($0)))" } ?? ""))
                    tab(.trending, "Тренды (24 ч)")
                    tab(.hot, "Горячее")
                    Spacer()
                    if let t = boards[.allTime]?.totalSkills { Text("\(Self.number(t)) навыков в каталоге").font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg) }
                }
            }
            if let note { IconLabel(text: note, icon: "circle-check", size: 13).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true) }
            if !selected.isEmpty { selectionBar }

            // ленивый список: рисуются только видимые строки — прокрутка не дёргается
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if loading && all.isEmpty {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Открываю skills.sh…").tw(13, lh: 18) }.padding(.vertical, 28)
                    }
                    if let error {
                        VStack(spacing: 8) {
                            IconLabel(text: error, icon: "triangle-alert", size: 14).tw(13, lh: 18).foregroundStyle(Palette.destructive)
                            LButton(title: "Ещё раз", icon: "rotate-cw", kind: .outline, small: true) { load(view, force: true) }
                        }
                        .padding(.vertical, 24)
                    }
                    if found?.isEmpty == true {
                        Text("Ничего не нашлось").tw(13, lh: 18).foregroundStyle(p.mutedFg).padding(.vertical, 28)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, e in
                        CatalogRow(app: app, rank: page * Self.perPage + i + 1, entry: e, open: open == e.id, installing: installing.contains(e.id),
                                   selected: selected[e.id] != nil, showRank: found == nil, showActivity: showActivity) {
                            open = open == e.id ? nil : e.id
                        } install: {
                            install([e])
                        } select: {
                            if selected[e.id] != nil { selected[e.id] = nil } else { selected[e.id] = e }
                        }
                        p.border.frame(height: 1)
                    }
                } header: { header }
            }
            if pages > 1 { pager }
            Text("Источник — skills.sh: каталог открытых навыков для агентов (тот же, что у npx skills). Без ключа Vercel сайт открывает первые 300 навыков каждой вкладки; остальные находятся поиском. Уже стоящая версия не скачивается заново.")
                .tw(11, lh: 15).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { load(view) }
        .onChange(of: view) { page = 0; load(view) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 18)
            Text("#").frame(width: 34, alignment: .leading)
            Text("НАВЫК")
            Spacer()
            if showActivity { Text("8 НЕД.").frame(width: 96, alignment: .leading) }
            Text(countTitle).frame(width: 88, alignment: .trailing)
            Color.clear.frame(width: 96)
        }
        .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(p.background)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }

    /// Отмечено несколько — поставить разом
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Icon("check", 14).foregroundStyle(p.glow)
            Text("Выбрано \(selected.count)").tw(13, .medium, lh: 18)
            Text(selected.values.map(\.name).sorted().joined(separator: ", ")).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
            Spacer()
            LButton(title: "Снять", kind: .ghost, small: true) { selected = [:] }
            LButton(title: installing.isEmpty ? "Поставить \(selected.count)" : "Ставлю…", icon: "download", kind: .primary, small: true,
                    busy: !installing.isEmpty) { install(Array(selected.values)) }
                .disabled(!installing.isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(p.glow.opacity(0.06), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.glow.opacity(0.3)))
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Button { page = max(0, page - 1) } label: { Icon("chevron-right", 14).rotationEffect(.degrees(180)) }
                .buttonStyle(.plain).disabled(page == 0).foregroundStyle(page == 0 ? p.mutedFg.opacity(0.4) : p.foreground)
            ForEach(0..<pages, id: \.self) { i in
                Button { page = i } label: {
                    Text("\(i * Self.perPage + 1)–\(min((i + 1) * Self.perPage, all.count))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(page == i ? p.foreground : p.mutedFg)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(page == i ? p.foreground.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                }
                .buttonStyle(.plain)
            }
            Button { page = min(pages - 1, page + 1) } label: { Icon("chevron-right", 14) }
                .buttonStyle(.plain).disabled(page == pages - 1).foregroundStyle(page == pages - 1 ? p.mutedFg.opacity(0.4) : p.foreground)
        }
        .frame(maxWidth: .infinity)
    }

    private func tab(_ v: SkillsDirectory.View, _ title: String) -> some View {
        Button { view = v } label: {
            Text(title).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(view == v ? p.foreground : p.mutedFg)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { if view == v { p.foreground.frame(height: 1) } }
        }
        .buttonStyle(.plain)
    }

    private func load(_ v: SkillsDirectory.View, force: Bool = false) {
        guard force || boards[v] == nil else { return }
        loading = true
        error = nil
        Task {
            do { boards[v] = try await SkillsDirectory(session: app.urlSession).board(v) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private func search(_ q: String) {
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { found = nil; page = 0; return }
        Task {
            try? await Task.sleep(for: .milliseconds(250)) // пока печатают — не дёргать сайт на каждую букву
            guard text == query.trimmingCharacters(in: .whitespaces) else { return }
            found = (try? await SkillsDirectory(session: app.urlSession).search(text)) ?? []
            page = 0
        }
    }

    /// Поставить один или несколько: по очереди, итог одной строкой
    private func install(_ entries: [SkillsDirectory.Entry]) {
        let todo = entries.filter { !installing.contains($0.id) }
        guard !todo.isEmpty else { return }
        installing.formUnion(todo.map(\.id))
        note = nil
        Task {
            var lines: [String] = []
            for e in todo {
                lines.append(await app.installFromDirectory(e))
                installing.remove(e.id)
                selected[e.id] = nil
            }
            note = lines.count == 1 ? lines[0] : "Готово: " + lines.joined(separator: " ")
        }
    }

    /// 3 881 956 → «3,9 млн», 155 405 → «155 тыс.», 812 → «812»
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f млн", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 10_000 { return "\(n / 1000) тыс." }
        if n >= 1000 { return String(format: "%.1f тыс.", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") }
        return "\(n)"
    }

    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct CatalogRow: View {
    @Bindable var app: AppModel
    let rank: Int
    let entry: SkillsDirectory.Entry
    let open: Bool
    let installing: Bool
    let selected: Bool
    let showRank: Bool
    let showActivity: Bool
    let toggle: () -> Void
    let install: () -> Void
    let select: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var description: String?
    @State private var translated = false

    private var installed: Bool { app.skills.contains { $0.info.source == entry.lockSource || $0.name == entry.skillID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // отметить, чтобы поставить несколько разом
                Button(action: select) {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(selected ? p.glow : p.foreground.opacity(installed ? 0.1 : 0.3), lineWidth: 1.2)
                        .background(selected ? p.glow : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .overlay { if selected { Icon("check", 11).foregroundStyle(p.onGlow) } }
                        .frame(width: 16, height: 16)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .disabled(installed)
                .opacity(installed ? 0.3 : 1)
                Text(showRank ? "\(rank)" : "·").frame(width: 34, alignment: .leading).foregroundStyle(p.mutedFg)
                HStack(spacing: 8) {
                    Text(entry.name).fontWeight(.medium).lineLimit(1)
                    Text(entry.source).foregroundStyle(p.mutedFg).lineLimit(1).truncationMode(.middle)
                    if entry.official { Icon("circle-check", 12).foregroundStyle(p.mutedFg).help("Официальный навык") }
                }
                Spacer(minLength: 8)
                if showActivity {
                    Sparkline(values: entry.weekly).stroke(p.mutedFg.opacity(0.8), lineWidth: 1.2).frame(width: 80, height: 16)
                        .frame(width: 96, alignment: .leading)
                }
                Text(SkillsCatalog.short(entry.installs)).frame(width: 88, alignment: .trailing)
                Group {
                    if installed {
                        IconLabel(text: "Стоит", icon: "check", size: 12).foregroundStyle(p.mutedFg)
                    } else {
                        LButton(title: installing ? "Ставлю…" : "Поставить", kind: .outline, small: true, busy: installing, action: install)
                            .opacity(hover || installing || open ? 1 : 0)
                    }
                }
                .frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 13, design: .monospaced))
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    if let description {
                        Text(description).tw(13, lh: 19).fixedSize(horizontal: false, vertical: true)
                        if translated { Text("перевод с английского").tw(11, lh: 14).foregroundStyle(p.mutedFg) }
                    } else {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Читаю описание…").tw(12, lh: 16).foregroundStyle(p.mutedFg) }
                    }
                    Link("Открыть на skills.sh →", destination: entry.page).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.glow)
                }
                .padding(.leading, 76).padding(.bottom, 4)
                .task { await loadDescription() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(selected ? p.glow.opacity(0.05) : (hover || open ? p.foreground.opacity(0.03) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hover = $0 }
    }

    /// Описание из SKILL.md; английское — переводим на русский (Haiku, запоминается)
    private func loadDescription() async {
        guard description == nil else { return }
        guard let text = try? await SkillsDirectory(session: app.urlSession).skillText(entry),
              let d = SkillFormat.parse(text)?.fields["description"], !d.isEmpty else { description = "Описания нет."; return }
        if let ru = await app.translateToRussian(d) {
            description = ru
            translated = ru != d
        } else {
            description = d
        }
    }
}

/// Линия активности за 8 недель
struct Sparkline: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else {
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
        let span = Double(max(hi - lo, 1))
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: rect.height * (1 - CGFloat(Double(v - lo) / span)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}
