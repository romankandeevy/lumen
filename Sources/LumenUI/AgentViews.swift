import LumenCore
import LumenProviders
import SwiftUI

/// Новая задача агента — вариант A «как Claude Code» (mockups/19-agent-new-A…, выбран Ромой 16.10), отполирован 21.10:
/// шар и «Что сделаем в {папка}?» — тем же шрифтом, что «Привет, имя»; имя папки подчёркнуто и открывает выбор папки.
/// Под полем — ветка git (или «Включить git») и «Push — только с твоего OK», ниже недавние задачи этой папки
struct AgentHome: View {
    @Bindable var app: AppModel
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    let backend: Backend

    @Environment(\.palette) private var p
    @State private var git: Git.Info?
    @State private var gitChecked = false
    @State private var gitInitError: String?
    @State private var composerFocused = false

    private var folder: URL? { app.agentFolder }

    /// Задачи агента в выбранной папке, новые сверху
    private var tasks: [Conversation] {
        guard let path = folder?.standardizedFileURL.path else { return [] }
        return app.conversations.filter { $0.kind == .agent && $0.folder.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == path }
    }

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headline
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 46)

                Composer(app: app, draft: $draft, attachments: $attachments, backend: backend, agent: true, big: true,
                         focusedOut: $composerFocused)

                hints.padding(.horizontal, 6).padding(.top, 12)

                if !tasks.isEmpty { recentList.padding(.top, 40) }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, minHeight: geo.size.height)
        }
        .scrollIndicators(.never)
        }
        .foregroundStyle(p.foreground)
        .task(id: folder) { await refreshGit() }
        // имя папки в заголовке — ссылка: открывает выбор папки в поле ввода
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "lumen-folder" { app.folderPickerRequest += 1; return .handled }
            return .systemAction
        })
    }

    private func refreshGit() async {
        git = nil
        gitChecked = false
        if let folder { git = await Git(folder: folder).info() }
        gitChecked = true
    }

    /// Шар и вопрос — как приветствие чата: Literata 60, без свечения сзади. Длинное имя папки — 48, потом 40 в одну строку,
    /// и только потом перенос: две строки по 60 стоят слишком широко
    private var headline: some View {
        let hot = composerFocused || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let orb = LumenMark(state: app.orb, size: 64, hot: hot).skyAnchor()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { orb; text(46).fixedSize() }
            HStack(spacing: 22) { orb; text(40).fixedSize() }
            HStack(spacing: 20) { orb; text(34).fixedSize() }
            HStack(alignment: .top, spacing: 20) { orb; text(34).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func text(_ size: CGFloat) -> some View {
        Text(question)
            .font(.greeting(size)).tracking(-0.02 * size).foregroundStyle(p.textStrong)
            .tint(p.textStrong)
            .lineLimit(size >= 40 ? 1 : 3)
            .accessibilityAddTraits(.isHeader)
    }

    /// «Что сделаем в lumen?»: имя папки тем же цветом, с тонким синим подчёркиванием; щелчок — выбрать папку
    private var question: AttributedString {
        guard let folder else { return AttributedString("Выбери папку проекта") }
        if AppModel.isHome(folder) { return AttributedString("Что сделаем на Маке?") }
        var name = AttributedString(folder.lastPathComponent)
        name.link = URL(string: "lumen-folder://pick")
        name.underlineStyle = Text.LineStyle(pattern: .solid, color: Color(.sRGB, red: 127 / 255, green: 160 / 255, blue: 1, opacity: 0.55))
        name.foregroundColor = p.textStrong
        return AttributedString("Что сделаем в ") + name + AttributedString("?")
    }

    /// Слева — git: ветка и незакоммиченное, или «Папка без git» и «Включить git»; справа — про push
    private var hints: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let git {
                HStack(spacing: 6) {
                    Icon("git-branch", 13)
                    Text(git.branch)
                    Text("·")
                    Text(git.changed > 0 ? "\(git.changed) " + Plural.form(git.changed, "изменённый файл", "изменённых файла", "изменённых файлов") + " не закоммичены"
                         : "Всё закоммичено")
                }
            } else if folder != nil, gitChecked, !(folder.map(AppModel.isHome) ?? false) {
                HStack(spacing: 8) {
                    Text(gitInitError ?? "Папка без git — «Изменения» после хода не покажутся")
                    if gitInitError == nil { InlineTextButton(title: "Включить git") { initGit() } }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) { Icon("lock", 13); Text("Push — только с твоего OK") }
        }
        .font(.geist(12.5)).foregroundStyle(p.faint)
    }

    private func initGit() {
        guard let folder else { return }
        Task {
            do {
                try await Git(folder: folder).initRepo()
                await refreshGit()
            } catch {
                gitInitError = "Не вышло включить git: \(error.localizedDescription)"
            }
        }
    }

    /// «Недавно в этой папке»: только три последние задачи
    private var recentList: some View {
        let shown = Array(tasks.prefix(3))
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Недавно в этой папке").font(.geist(12.5, .medium)).foregroundStyle(p.mutedFg)
                .padding(.leading, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { p.borderBase.opacity(0.055).frame(height: 1) }
                    RecentTaskRow(c: c) { app.openChat(c) }
                }
            }
            .background(p.borderBase.opacity(0.02), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(p.borderBase.opacity(0.07)))
        }
    }
}

/// Текстовая кнопка внутри строки: синяя (или своего цвета), под курсором — цвета текста
struct InlineTextButton: View {
    let title: String
    var color: Color?
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(hover ? p.foreground : (color ?? p.accentSoft))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Строка «Недавно в этой папке»: название и когда; вся строка — кнопка
struct RecentTaskRow: View {
    let c: Conversation
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(c.title).font(.geist(15)).foregroundStyle(p.textSoft).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(hover ? p.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(c.title)
    }
}

/// Плитка папки: rounded-xl border px-3 py-2.5 text-sm, выбранная светится
struct FolderTile: View {
    let name: String
    let active: Bool
    var muted = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(muted ? "folder-plus" : "folder", 16)
                    .foregroundStyle(active ? p.glow : p.mutedFg)
                Text(name).font(.geist(14)).lineLimit(1).foregroundStyle(muted ? p.mutedFg : p.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(active ? p.glow.opacity(0.06) : (hover ? p.card : p.card.opacity(0.85)), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(active ? p.glow.opacity(0.5) : p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Шаги агента между абзацами, как в Claude: «Выполнено 5 команд ›» серым, по нажатию — история шагов лентой.
/// Пока шаг идёт — это одна кнопка: в ней что агент делает сейчас (с таймером), раскрыл — видна вся история
struct StepsView: View {
    let steps: [AgentStep]
    /// Идущий шаг: с какого времени и цвет точки (у бота — его цвет)
    var live: (since: Date, tint: Color?)?
    /// Для снимков: показать раскрытым
    var initiallyOpen = false
    /// Снимки экрана, сделанные на этих шагах: превью справа на строке (три и «+N»)
    var shots: [Attachment] = []
    var app: AppModel?

    @Environment(\.palette) private var p
    @State private var open = false
    @State private var hover = false
    /// Какой шаг раскрыт: что он делал (путь, команда, правка)
    @State private var detailRow: Int?
    @State private var historyHeight: CGFloat = 0
    /// Сказать переписке, что шаги раскрыты: пока человек их читает, она не уезжает вниз за новым текстом
    @Environment(\.stepsOpened) private var stepsOpened

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: { header.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 }
                    .help(open ? "Свернуть" : "Показать, что делал")
                Spacer(minLength: 8)
                if !shots.isEmpty { ShotStrip(shots: shots, app: app) }
            }
            if open { history.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .onAppear { if initiallyOpen { open = true } }
        .onChange(of: open) { _, now in stepsOpened(now) }
        .onDisappear { if open { stepsOpened(false) } }
    }

    @ViewBuilder private var header: some View {
        if let live, let now = steps.last {
            // как в Claude: бегущие точки · что делает сейчас · сколько идёт · ›
            HStack(spacing: 10) {
                DotsSpinner(color: live.tint ?? p.glow, mood: .writing)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 8) {
                        Text(now.text).tw(14, lh: 20).foregroundStyle(p.foreground.opacity(0.85)).lineLimit(1).shimmer(p.foreground)
                        Text(LiveStepLine.elapsed(ctx.date.timeIntervalSince(live.since))).tw(13, lh: 20)
                            .foregroundStyle(p.mutedFg).monospacedDigit()
                    }
                }
                Icon(open ? "chevron-down" : "chevron-right", 12).foregroundStyle(hover ? p.foreground : p.mutedFg)
            }
        } else {
            HStack(spacing: 4) {
                Text(summary).tw(14, lh: 20).lineLimit(1)
                Icon(open ? "chevron-down" : "chevron-right", 12)
            }
            .foregroundStyle(hover ? p.foreground.opacity(0.8) : p.mutedFg)
        }
    }

    /// История лентой: значок рода шага на вертикальной линии, глагол серым, предмет — ярче; идущий — с точкой
    private var history: some View {
        let rows = Array(steps.enumerated())
        let list = VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.offset) { i, s in
                let current = live != nil && i == steps.count - 1
                // строка шага хендоффа (1.7.4): значок 16 без кружка, текст 14/20, между строками линия
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        if current {
                            LiveDot(color: live?.tint ?? p.glow, size: 7)
                        } else {
                            Icon(Self.icon(s.kind), 16).foregroundStyle(p.faint)
                        }
                    }
                    .frame(width: 16, height: 20)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Self.styled(s.text, p: p, current: current).lineLimit(2).textSelection(.enabled)
                            if s.detail != nil {
                                Icon(detailRow == i ? "chevron-down" : "chevron-right", 11).foregroundStyle(p.mutedFg)
                            }
                        }
                        if detailRow == i, let d = s.detail {
                            Text(d).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(p.mutedFg)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8).background(p.foreground.opacity(0.04), in: RoundedRectangle(cornerRadius: R.md))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard s.detail != nil else { return }
                        withAnimation(.easeOut(duration: 0.15)) { detailRow = detailRow == i ? nil : i }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minHeight: 36, alignment: .leading)
                .overlay(alignment: .top) { if i > 0 { p.border.frame(height: 1) } }
            }
        }
        // своя область прокрутки не выше 300 pt (Рома, 19.10): листаешь шаги — листаются они, а не вся переписка.
        // «Резинка» внутри всегда — так прокрутка у края не перескакивает на переписку
        return ScrollView {
            list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { historyHeight = $0 }
        }
        .scrollBounceBehavior(.always)
        .scrollIndicators(.never)
        .frame(height: min(max(historyHeight, 1), 300))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border))
    }

    /// «Читает 07 Проверь себя.png»: глагол — серым, что именно — ярче; пути и шаблоны — моноширинным
    static func styled(_ text: String, p: Palette, current: Bool) -> Text {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].first?.isUppercase == true else {
            return Text(text).font(.geist(14)).foregroundColor(current ? p.foreground : p.textSoft)
        }
        let object = parts[1]
        let code = object.contains("/") || object.contains("*") || object.contains("«") == false && object.contains("_")
        let tail = code ? Text(object).font(.system(size: 12.5, design: .monospaced)) : Text(object).font(.geist(14))
        return Text(parts[0] + " ").font(.geist(14)).foregroundColor(p.mutedFg)
            + tail.foregroundColor(current ? p.foreground : p.textSoft)
    }

    /// Как в Claude Code: один шаг — его строкой, несколько — «Выполнено 5 команд, прочитано 2 файла»
    private var summary: String { Self.summary(steps) }

    static func summary(_ steps: [AgentStep]) -> String {
        if steps.count == 1, let s = steps.first { return s.text }
        func count(_ kinds: Set<AgentStep.Kind>) -> Int { steps.filter { kinds.contains($0.kind) }.count }
        func part(_ n: Int, _ verb: (String, String), _ noun: (String, String, String)) -> String? {
            guard n > 0 else { return nil }
            return "\(Plural.form(n, verb.0, verb.1, verb.1)) \(n) \(Plural.form(n, noun.0, noun.1, noun.2))"
        }
        let parts = [
            part(count([.run]), ("выполнена", "выполнено"), ("команда", "команды", "команд")),
            part(count([.edit]), ("изменён", "изменено"), ("файл", "файла", "файлов")),
            part(count([.read]), ("прочитан", "прочитано"), ("файл", "файла", "файлов")),
            part(count([.search]), ("сделан", "сделано"), ("поиск", "поиска", "поисков")),
            part(count([.web]), ("открыт", "открыто"), ("сайт", "сайта", "сайтов")),
            part(count([.file]), ("создан", "создано"), ("файл", "файла", "файлов")),
            part(count([.think, .other]), ("сделан", "сделано"), ("шаг", "шага", "шагов")),
        ].compactMap { $0 }
        let line = parts.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    static func icon(_ k: AgentStep.Kind) -> String {
        switch k {
        case .read: "file"
        case .edit: "pencil"
        case .run: "terminal"
        case .search: "search"
        case .web: "globe"
        case .file: "file-text"
        case .think: "brain"
        case .other: "wrench"
        }
    }
}

/// Карточка «Изменения» (`ChangeCard`): файлы с +/−, «Откатить», «Разница», «Закоммитить».
/// Push здесь нет: его делает человек.
struct ChangeCard: View {
    let message: ChatMessage
    let changes: ChangeSet
    let chat: ChatController

    @Environment(\.palette) private var p
    @State private var diffOpen = false
    @State private var diffText = ""
    @State private var busy = false

    private var added: Int { changes.files.reduce(0) { $0 + $1.added } }
    private var removed: Int { changes.files.reduce(0) { $0 + $1.removed } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon("git-commit-horizontal", 16).foregroundStyle(p.mutedFg)
                Text("Изменения").font(.geist(14, .medium))
                Text("\(changes.files.count) " + Plural.form(changes.files.count, "файл", "файла", "файлов") + ", +\(added) −\(removed)")
                    .font(.geist(12)).foregroundStyle(p.mutedFg)
                Spacer()
                // бейдж хендоффа: пилюля 20, 11 вес 540, рамка
                Text(stateName).font(.geist(11, .semibold)).foregroundStyle(p.mutedFg)
                    .padding(.horizontal, 7).frame(height: 20)
                    .overlay(Capsule().strokeBorder(p.border))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }

            VStack(spacing: 4) {
                ForEach(changes.files, id: \.path) { f in
                    HStack(spacing: 8) {
                        Text(f.status).foregroundStyle(p.mutedFg)
                        Text(f.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("+\(f.added)").foregroundStyle(Color(hex: 0x6EE7B7).opacity(0.9))
                        Text("−\(f.removed)").foregroundStyle(Palette.destructive.opacity(0.9))
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let id = message.id, let err = chat.changeError[id] {
                Text(err).font(.geist(12)).foregroundStyle(Palette.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
            }

            HStack(spacing: 8) {
                LButton(title: "Откатить", icon: "undo-2", kind: .ghost, size: .sm) { act { await chat.revert(message) } }
                    .disabled(changes.state != .applied || busy)
                    .help("Вернуть файлы как были до этого хода. Новые файлы уйдут в Корзину.")
                Spacer()
                LButton(title: "Разница", icon: "git-compare", kind: .outline, size: .sm) {
                    Task {
                        diffText = await chat.diff(message)
                        diffOpen = true
                    }
                }
                LButton(title: "Закоммитить", icon: "check", kind: .primary, size: .sm) { act { await chat.commit(message) } }
                    .disabled(changes.state != .applied || busy)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .top) { p.border.frame(height: 1) }
        }
        .background(p.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.border))
        .sheet(isPresented: $diffOpen) {
            DiffSheet(text: diffText) { diffOpen = false }.environment(\.palette, p)
        }
    }

    private var stateName: String {
        switch changes.state {
        case .applied: "применено"
        case .committed: "закоммичено"
        case .reverted: "откачено"
        }
    }

    private func act(_ f: @escaping () async -> Void) {
        busy = true
        Task {
            await f()
            busy = false
        }
    }
}

/// Разница до и после: строки с + зелёные, с − красные
struct DiffSheet: View {
    let text: String
    let close: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Разница").font(.geist(16, .semibold))
                Spacer()
                LButton(title: "Готово", kind: .primary, size: .sm, action: close).keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4000).enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : String(line))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(color(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(bg(line))
                    }
                }
                .textSelection(.enabled)
                .padding(16)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(p.popover)
        .foregroundStyle(p.foreground)
        .preferredColorScheme(p.scheme)
    }

    private func color(_ l: Substring) -> Color {
        // «Маркеры различий: +/−» — без цвета, только знаки
        if p.diffSigns { return l.hasPrefix("@@") ? p.mutedFg : p.foreground.opacity(0.85) }
        if l.hasPrefix("+++") || l.hasPrefix("---") || l.hasPrefix("diff ") || l.hasPrefix("index ") { return p.mutedFg }
        if l.hasPrefix("+") { return Color(hex: 0x6EE7B7) }
        if l.hasPrefix("-") { return Palette.destructive }
        if l.hasPrefix("@@") { return p.glow }
        return p.foreground.opacity(0.8)
    }

    private func bg(_ l: Substring) -> Color {
        if p.diffSigns { return .clear }
        if l.hasPrefix("+") && !l.hasPrefix("+++") { return Color(hex: 0x6EE7B7).opacity(0.06) }
        if l.hasPrefix("-") && !l.hasPrefix("---") { return Palette.destructive.opacity(0.06) }
        return .clear
    }
}

/// План работы (`PlanList`): сделано — галочка, сейчас — крутится, дальше — пунктир; сверху «N из M»
struct PlanList: View {
    let items: [PlanItem]

    @Environment(\.palette) private var p

    var body: some View {
        let done = items.filter { $0.state == .done }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.foreground.opacity(0.1))
                        Capsule().fill(p.glow).frame(width: g.size.width * CGFloat(done) / CGFloat(max(items.count, 1)))
                            .animation(.easeOut(duration: 0.5), value: done)
                    }
                }
                .frame(height: 4)
                Text("\(done) из \(items.count)").font(.geist(11)).foregroundStyle(p.mutedFg).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .top, spacing: 10) {
                        PlanMark(state: it.state).padding(.top, 1)
                        Text(it.text)
                            .font(.geist(13, it.state == .doing ? .medium : .regular))
                            .foregroundStyle(it.state == .done ? p.mutedFg : (it.state == .doing ? p.foreground : p.foreground.opacity(0.75)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct PlanMark: View {
    let state: PlanItem.State

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        switch state {
        case .done:
            Icon("check", 12).foregroundStyle(p.background)
                .frame(width: 17, height: 17).background(p.foreground.opacity(0.7), in: Circle())
        case .doing:
            // крутится по часам, а не анимацией из onAppear: в прокрутке та срывается и дуга стоит
            TimelineView(.animation(minimumInterval: 1 / 30, paused: lessMotion)) { ctx in
                Circle().stroke(p.foreground.opacity(0.15), lineWidth: 2)
                    .overlay(Circle().trim(from: 0, to: 0.25).stroke(p.glow, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360)))
                    .frame(width: 15, height: 15).padding(1)
            }
        case .todo:
            Circle().strokeBorder(p.foreground.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                .frame(width: 17, height: 17)
        }
    }
}

/// Карточка «что дальше» (`NextStep`): итог, вопрос, главная кнопка с ⌘↵, вторая — альтернатива, крестик — убрать
struct NextStepCard: View {
    let next: NextStep
    let answer: (NextStep.Choice) -> Void
    let close: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(next.recap).font(.geist(13)).lineSpacing(3).foregroundStyle(p.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true).padding(.trailing, 22)
            if let ask = next.ask, !ask.isEmpty {
                Text(ask).font(.geist(13, .medium)).fixedSize(horizontal: false, vertical: true)
            }
            if next.primary != nil || next.secondary != nil {
                HStack(spacing: 8) {
                    if let primary = next.primary {
                        Button { answer(primary) } label: {
                            HStack(spacing: 6) {
                                Text(primary.label).font(.geist(13, .medium))
                                HStack(spacing: 2) { Kbd("⌘"); Kbd("↵") }
                            }
                            .foregroundStyle(p.background)
                            .padding(.leading, 12).padding(.trailing, 5).frame(height: 30)
                            .background(p.foreground, in: RoundedRectangle(cornerRadius: R.xl))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    if let secondary = next.secondary {
                        Button { answer(secondary) } label: {
                            Text(secondary.label).font(.geist(13, .medium))
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(p.secondary, in: RoundedRectangle(cornerRadius: R.xl))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(1), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Icon("x", 14).foregroundStyle(p.mutedFg) }
                .buttonStyle(.plain).help("Убрать").padding(10)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private struct Kbd: View {
        let s: String
        init(_ s: String) { self.s = s }
        @Environment(\.palette) private var p
        var body: some View {
            Text(s).font(.geist(12)).frame(width: 24, height: 24)
                .background(p.background.opacity(0.1), in: RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.background.opacity(0.2)))
        }
    }
}

/// Агент спрашивает «можно?» — как запрос разрешения в Claude Code. Для готового плана — свой вид.
struct PermissionCard: View {
    let chat: ChatController
    let ask: ClaudeEvent.PermissionRequest

    @Environment(\.palette) private var p
    @State private var note = ""
    @State private var revising = false

    var body: some View {
        if ask.tool == "ExitPlanMode" { plan } else { permission }
    }

    // MARK: разрешение

    private var permission: some View {
        let step = ask.step
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Icon("hand", 15).foregroundStyle(p.glow)
                Text("Можно?").tw(13, .medium, lh: 18)
                Text(step.text).tw(13, lh: 18).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            if let detail {
                ScrollView {
                    Text(detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            }
            HStack(spacing: 8) {
                LButton(title: "Разрешить", icon: "check", kind: .primary, small: true) { chat.answerPermission(allow: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                LButton(title: "Разрешать до конца разговора", kind: .outline, small: true) { chat.answerPermission(allow: true, always: true) }
                LButton(title: "Отклонить", kind: .ghost, small: true) { chat.answerPermission(allow: false) }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer(minLength: 0)
                Text("⌘↵ — разрешить · Esc — отклонить").tw(11, lh: 14).foregroundStyle(p.mutedFg)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.3)))
    }

    /// Что именно: команда, файл и правка
    private var detail: String? {
        let i = ask.input
        switch ask.tool {
        case "Bash": return i["command"] as? String
        case "Write":
            let text = (i["content"] as? String ?? "").prefix(1200)
            return "\(i["file_path"] as? String ?? "")\n\n\(text)"
        case "Edit":
            let old = (i["old_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "- " + $0 }
            let new = (i["new_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "+ " + $0 }
            return "\(i["file_path"] as? String ?? "")\n\n" + (old + new).joined(separator: "\n")
        case "WebFetch": return i["url"] as? String
        default:
            let json = ask.inputJSON
            return json == "{}" ? nil : String(json.prefix(800))
        }
    }

    // MARK: план готов

    private var plan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Icon("list-checks", 15).foregroundStyle(p.glow)
                Text("План готов — выполнить?").tw(13, .medium, lh: 18)
            }
            RichText(text: ask.input["plan"] as? String ?? "")
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            if revising {
                HStack(spacing: 8) {
                    GlowField(placeholder: "Что поменять в плане", text: $note) { chat.answerPlan(run: nil, note: note) }
                    LButton(title: "Отправить", kind: .outline, small: true) { chat.answerPlan(run: nil, note: note) }
                }
            }
            HStack(spacing: 8) {
                LButton(title: "Выполнить · принимать правки", icon: "check", kind: .primary, small: true) { chat.answerPlan(run: .acceptEdits) }
                    .keyboardShortcut(.return, modifiers: .command)
                LButton(title: "Авто", kind: .outline, small: true) { chat.answerPlan(run: .auto) }
                LButton(title: "Спрашивать каждый шаг", kind: .outline, small: true) { chat.answerPlan(run: .manual) }
                LButton(title: "Доработать", kind: .ghost, small: true) { revising = true }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.3)))
    }
}

/// План под перепиской, как в Claude: рамка, пункты — сделано (галочка), идёт (точки), впереди (пунктир)
struct PlanCard: View {
    let items: [PlanItem]
    /// План составлен до последнего сообщения человека — так и подписан
    var earlier = false

    @Environment(\.palette) private var p

    var body: some View {
        let done = items.filter { $0.state == .done }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(earlier ? "План до твоего последнего сообщения" : "План").tw(12, lh: 16)
                Text("\(done) из \(items.count)").tw(12, lh: 16).monospacedDigit()
                Spacer(minLength: 0)
            }
            .foregroundStyle(p.mutedFg)
            VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        HStack(alignment: .top, spacing: 10) {
                            PlanMark(state: it.state).padding(.top, 2)
                            Text(it.text).tw(14, lh: 20)
                                .foregroundStyle(it.state == .todo ? p.foreground.opacity(0.75) : p.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.background.opacity(0.92), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }
}

/// Разговор сейчас идёт в приложении Claude: «Claude Code · Читает файл · 12 с ›». Щелчок раскрывает последние шаги этого хода.
struct ClaudeLiveLine: View {
    let text: String
    let since: Date
    let steps: [AgentStep]
    var tint: Color?

    @Environment(\.palette) private var p
    @State private var open = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    DotsSpinner(color: tint ?? p.glow, mood: .writing).frame(width: 22)
                    Text("Claude Code").tw(13, .medium, lh: 20).foregroundStyle(p.foreground.opacity(0.75))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 8) {
                            Text(text).tw(14, lh: 20).foregroundStyle(p.mutedFg).lineLimit(1).shimmer(p.foreground)
                            Text(LiveStepLine.elapsed(ctx.date.timeIntervalSince(since))).tw(13, lh: 20)
                                .foregroundStyle(p.mutedFg.opacity(0.8)).monospacedDigit()
                        }
                    }
                    if !steps.isEmpty {
                        Icon(open ? "chevron-down" : "chevron-right", 13).foregroundStyle(hover ? p.foreground : p.mutedFg)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(steps.isEmpty)
            .onHover { hover = $0 }
            .help(steps.isEmpty ? "" : (open ? "Свернуть" : "Что он делал в этом ходе"))
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.suffix(12).enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 8) {
                            Icon(StepsView.icon(s.kind), 13).foregroundStyle(p.mutedFg)
                            Text(s.text).tw(13, lh: 18).foregroundStyle(p.foreground.opacity(0.75)).lineLimit(1)
                        }
                    }
                    if steps.count > 12 { Text("и ещё \(steps.count - 12) раньше").tw(12, lh: 16).foregroundStyle(p.mutedFg) }
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
    }
}

/// Знак «работает», как в Claude: четыре точки ромбом, по очереди гаснут и загораются.
/// Если включён питомец «вместо точек» — вместо них питомец, у бота — его капля (WorkMark)
struct DotsSpinner: View {
    var color: Color
    var size: CGFloat = 4
    var bot: Bot?
    var mood: PetMood = .thinking
    /// Только точки, без питомца
    var plain = false

    @Environment(\.lessMotion) private var lessMotion
    @Environment(\.petMark) private var pet

    var body: some View {
        if !plain && pet != nil {
            WorkMark(color: color, bot: bot, mood: mood)
        } else {
            dots
        }
    }

    private var dots: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: lessMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let gap = size * 1.6
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    // сверху, справа, снизу, слева — волна по кругу
                    let pos = [CGPoint(x: 0, y: -gap), CGPoint(x: gap, y: 0), CGPoint(x: 0, y: gap), CGPoint(x: -gap, y: 0)][i]
                    let phase = (t * 1.6 - Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                    let k = lessMotion ? 1 : 0.35 + 0.65 * (0.5 + 0.5 * cos(phase * 2 * .pi))
                    Circle().fill(color.opacity(k)).frame(width: size, height: size).offset(x: pos.x, y: pos.y)
                }
            }
            .frame(width: gap * 2 + size, height: gap * 2 + size)
        }
    }
}

/// Живая строка под планом, пока идёт ход: что агент делает сейчас и сколько уже (как в Claude: «… 5 мин 54 с ›»)
struct LiveStepLine: View {
    let text: String
    let since: Date
    var tint: Color?
    var bot: Bot?

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            DotsSpinner(color: tint ?? p.glow, bot: bot, mood: .writing).frame(width: 22)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 8) {
                    Text(text).tw(14, lh: 20).foregroundStyle(p.mutedFg).lineLimit(1).shimmer(p.foreground)
                    Text(Self.elapsed(ctx.date.timeIntervalSince(since))).tw(13, lh: 20).foregroundStyle(p.mutedFg.opacity(0.8)).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }

    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 60 { return "\(s) с" }
        if s < 3600 { return "\(s / 60) мин \(s % 60) с" }
        return "\(s / 3600) ч \(s % 3600 / 60) мин"
    }
}

/// Время хода всегда на виду — и пока пишется текст, когда шага уже нет (Рома, 19.10): сколько прошло с начала хода
struct TurnClockLine: View {
    let text: String
    let since: Date
    var tint: Color?

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            LiveDot(color: tint ?? p.glow, size: 7).frame(width: 22)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 8) {
                    Text(text).tw(14, lh: 20).foregroundStyle(p.mutedFg).lineLimit(1)
                    Text(LiveStepLine.elapsed(ctx.date.timeIntervalSince(since))).tw(13, lh: 20)
                        .foregroundStyle(p.mutedFg.opacity(0.8)).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }
}


/// Раскрыли или свернули шаги: переписка, пока они раскрыты, не уезжает вниз за ответом (StepsView → ChatView)
private struct StepsOpenedKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var stepsOpened: @MainActor @Sendable (Bool) -> Void {
        get { self[StepsOpenedKey.self] }
        set { self[StepsOpenedKey.self] = newValue }
    }
}

/// Без «резинки» (Рома, 19.10): переписка не тянется дальше начала и конца. SwiftUI так не умеет — настраиваем NSScrollView
struct NoBounce: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Probe)?.apply() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                scroll.verticalScrollElasticity = .none
                scroll.horizontalScrollElasticity = .none
            }
        }
    }
}

/// Фоновые задачи агента под перепиской (Рома, 19.10): субагенты, исследования, команды в терминале.
/// Строка «Фоновые задачи · работают 2», по нажатию — список: что делает каждая, сколько идёт, вывод команды вживую.
/// Список — своя область прокрутки, пока раскрыт — переписка не уезжает вниз.
struct BackgroundTasksBar: View {
    let tasks: [BackgroundJob]
    /// Для снимков: показать раскрытым
    var initiallyOpen = false

    @Environment(\.palette) private var p
    @Environment(\.stepsOpened) private var stepsOpened
    @State private var open = false
    @State private var hover = false
    @State private var listHeight: CGFloat = 0

    var body: some View {
        let running = tasks.filter { $0.status == .running }.count
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    if running > 0 { LiveDot(color: p.glow, size: 7).frame(width: 14) } else { Icon("layers", 14) }
                    Text(Self.summary(tasks)).tw(13, lh: 18)
                    Icon(open ? "chevron-down" : "chevron-right", 12)
                }
                .foregroundStyle(hover ? p.foreground : p.mutedFg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(open ? "Свернуть" : "Субагенты, исследования и команды, которые агент запустил")
            if open {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(tasks.reversed().enumerated()), id: \.element.id) { i, t in
                            if i > 0 { p.border.frame(height: 1) }
                            BackgroundTaskRow(task: t)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollBounceBehavior(.always)
                .frame(height: min(max(listHeight, 1), 320))
                .background(p.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                .transition(.opacity)
            }
        }
        .onAppear { if initiallyOpen { open = true } }
        .onChange(of: open) { _, now in stepsOpened(now) }
        .onDisappear { if open { stepsOpened(false) } }
    }

    /// «Фоновые задачи · работают 2, готово 1»
    static func summary(_ tasks: [BackgroundJob]) -> String {
        let running = tasks.filter { $0.status == .running }.count
        let failed = tasks.filter { $0.status == .failed }.count
        let done = tasks.count - running - failed
        let parts = [running > 0 ? "работают \(running)" : nil, done > 0 ? "готово \(done)" : nil, failed > 0 ? "с ошибкой \(failed)" : nil]
        return "Фоновые задачи · " + parts.compactMap { $0 }.joined(separator: ", ")
    }
}

struct BackgroundTaskRow: View {
    let task: BackgroundJob

    @Environment(\.palette) private var p

    private var icon: String {
        switch task.kind {
        case .agent: "bot"
        case .research: "search"
        case .shell: "terminal"
        }
    }

    private var kindName: String {
        switch task.kind {
        case .agent: "субагент"
        case .research: "исследование"
        case .shell: task.background ? "команда в фоне" : "команда"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: task.status == .running ? 1 : 3600)) { ctx in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Icon(icon, 13).foregroundStyle(p.mutedFg).frame(width: 16)
                    Text(task.title).tw(13, lh: 18).foregroundStyle(p.foreground.opacity(0.85)).lineLimit(1)
                    Text(kindName).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    Spacer(minLength: 8)
                    status(now: ctx.date)
                }
                if let line = task.status == .running ? task.activity : task.summary, !line.isEmpty {
                    Text(line).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(2).padding(.leading, 24)
                }
                if task.kind == .shell, let out = task.tail() {
                    Text(out).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg)
                        .textSelection(.enabled).lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8).background(p.foreground.opacity(0.04), in: RoundedRectangle(cornerRadius: R.md))
                        .padding(.leading, 24)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    @ViewBuilder private func status(now: Date) -> some View {
        let took = LiveStepLine.elapsed((task.ended ?? now).timeIntervalSince(task.started))
        switch task.status {
        case .running:
            HStack(spacing: 6) {
                LiveDot(color: p.glow, size: 6)
                Text(took).monospacedDigit()
            }
            .tw(12, lh: 16).foregroundStyle(p.mutedFg)
        case .completed:
            HStack(spacing: 4) { Icon("check", 12); Text(took).monospacedDigit() }.tw(12, lh: 16).foregroundStyle(p.mutedFg)
        case .failed:
            Text("ошибка · \(took)").tw(12, lh: 16).foregroundStyle(Palette.destructive)
        case .stopped:
            Text("остановлена").tw(12, lh: 16).foregroundStyle(p.mutedFg)
        }
    }
}


/// Превью снимков экрана на строке шагов, как в Claude Code: до трёх штук, дальше «+1», «+2»… Нажатие открывает снимок сбоку
struct ShotStrip: View {
    let shots: [Attachment]
    var app: AppModel?

    @Environment(\.palette) private var p
    static let visible = 3
    static let size = CGSize(width: 76, height: 48)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(shots.prefix(Self.visible)) { a in
                Button { if let app { app.preview(a) } else { NSWorkspace.shared.open(a.url) } } label: {
                    Group {
                        if let img = ThumbCache.image(a.url) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            p.card
                        }
                    }
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: R.md))
                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
                }
                .buttonStyle(.plain)
                .help(a.name)
            }
            if shots.count > Self.visible {
                Text("+\(shots.count - Self.visible)").tw(13, .medium, lh: 16).foregroundStyle(p.mutedFg)
                    .frame(width: Self.size.width * 0.6, height: Self.size.height)
                    .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.md))
                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
            }
        }
    }
}
