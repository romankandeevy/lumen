import LumenCore
import SwiftUI

/// Раздел «Проекты» в панели — как в Claude: проект раскрывается и показывает свои разговоры
struct ProjectsSection: View {
    @Bindable var app: AppModel
    /// Какие разговоры показывать внутри: чаты или задачи агента
    let kind: ConversationKind

    @Environment(\.palette) private var p
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Проекты").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                Spacer()
                SmallPlus(help: "Новый проект") { app.createProject(folder: kind == .agent ? app.agentFolder : nil) }
            }
            .padding(.leading, 10).padding(.trailing, 4).padding(.bottom, 4)
            ForEach(app.projects) { pr in
                ProjectRow(app: app, project: pr, open: open.contains(pr.id),
                           count: app.conversations(in: pr.id).filter { $0.kind == kind }.count) {
                    if open.contains(pr.id) { open.remove(pr.id) } else { open.insert(pr.id) }
                }
                if open.contains(pr.id) {
                    ForEach(app.conversations(in: pr.id).filter { $0.kind == kind }) { c in
                        ChatRow(app: app, c: c).padding(.leading, 14)
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .onAppear {
            // проект открытого разговора раскрыт
            if let id = app.chat.conversation?.projectID { open.insert(id) }
        }
        .onChange(of: app.chat.conversation?.projectID) { _, id in if let id { open.insert(id) } }
    }
}

/// Строка проекта: стрелка, папка, название; по названию — страница проекта, по стрелке — свернуть
struct ProjectRow: View {
    @Bindable var app: AppModel
    let project: Project
    let open: Bool
    let count: Int
    let toggle: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = ProjectRow.snapHover

    @State private var dotsHover = false
    /// Для снимков экрана: строка нарисуется наведённой
    nonisolated(unsafe) static var snapHover = false

    private var active: Bool { app.page == .project(project.id) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Icon(open ? "chevron-down" : "chevron-right", 14).foregroundStyle(p.mutedFg)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { app.openProject(project) } label: {
                HStack(spacing: 8) {
                    Icon(open ? "folder-open" : "folder", 16).foregroundStyle(active ? p.glow : p.mutedFg)
                    Text(project.name).font(.geist(14)).lineLimit(1)
                        .foregroundStyle(active || hover ? p.foreground : p.foreground.opacity(0.8))
                    Spacer(minLength: 4)
                    if count > 0 && !(hover || dotsHover) { Text("\(count)").font(.geist(11)).foregroundStyle(p.mutedFg) }
                }
                // при наведении название уступает место «+» и «…» — обрезается до них, а не уходит под них
                .padding(.trailing, hover || dotsHover ? 50 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4).padding(.trailing, 10).frame(height: 32)
        .background(active ? p.foreground.opacity(0.07) : (hover ? p.foreground.opacity(0.05) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(alignment: .leading) { if active { GlowBar() } }
        .onHover { hover = $0 }
        .overlay(alignment: .trailing) {
            if hover || dotsHover {
                HStack(spacing: 0) {
                    // «+» — новый разговор прямо в проекте; того же размера, что «…», — стоят ровно в ряд
                    SmallPlus(help: "Новый разговор в «\(project.name)»", side: 26) { app.newChat(in: project, agent: app.tab == .agent) }
                    GeometryReader { g in
                        let f = g.frame(in: .global)
                        DotsButton { app.showProjectMenu(project, at: CGPoint(x: f.minX, y: f.maxY + 4)) }
                    }
                    .frame(width: 26, height: 26)
                }
                .onHover { dotsHover = $0 }.padding(.trailing, 4)
            }
        }
        .onRightClick { point in app.showProjectMenu(project, at: point) }
    }
}

/// Маленький «+» рядом с подписью группы
struct SmallPlus: View {
    let help: String
    /// Размер кнопки: 20 у подписи раздела, 26 рядом с «…»
    var side: CGFloat = 20
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon("plus", 14).foregroundStyle(hover ? p.foreground : p.mutedFg)
                .frame(width: side, height: side)
                .background(hover ? p.foreground.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: side > 20 ? R.md : R.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Страница проекта: разговоры, инструкции, файлы, папка для агента
struct ProjectView: View {
    @Bindable var app: AppModel
    let projectID: String

    @Environment(\.palette) private var p
    @State private var name = ""
    @State private var instructions = ""
    @State private var editingInstructions = false
    @State private var draft = ""
    @State private var agent = false
    @FocusState private var nameFocused: Bool
    @FocusState private var draftFocused: Bool

    private var project: Project? { app.project(projectID) }

    var body: some View {
        if let pr = project {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // как в Claude: «Проекты / Swift», ниже крупное название, справа закрепить и «…»
                    HStack(spacing: 8) {
                        Text("Проекты").foregroundStyle(p.mutedFg)
                        Text("/").foregroundStyle(p.mutedFg.opacity(0.6))
                        Text(pr.name).lineLimit(1)
                    }
                    .tw(14, lh: 20)
                    HStack(alignment: .center, spacing: 8) {
                        // название правится прямо здесь
                        TextField("Название проекта", text: $name)
                            // без .tw: у поля ввода добавочные отступы строки обрезают буквы сверху
                            .textFieldStyle(.plain).font(.geist(30, .semibold)).tracking(-0.6).frame(height: 42)
                            .focused($nameFocused)
                            .onSubmit { save(pr) }
                            .onChange(of: nameFocused) { _, f in if !f { save(pr) } }
                        Spacer(minLength: 0)
                        IconButton(icon: pr.pinned ? "pin-off" : "pin", help: pr.pinned ? "Открепить" : "Закрепить", active: pr.pinned) {
                            app.updateProject(pr) { $0.pinned.toggle() }
                        }
                        GeometryReader { g in
                            let f = g.frame(in: .global)
                            DotsButton { app.showProjectMenu(pr, at: CGPoint(x: f.minX - 160, y: f.maxY + 4)) }
                        }
                        .frame(width: 26, height: 26)
                    }
                    .padding(.top, 24)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            main(pr).frame(minWidth: 420)
                            aside(pr).frame(width: 340)
                        }
                        VStack(alignment: .leading, spacing: 32) { main(pr); aside(pr) }
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 32).padding(.top, 52).padding(.bottom, 40)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.never)
            .foregroundStyle(p.foreground)
            .onAppear { load(pr) }
            .onChange(of: projectID) { if let pr = project { load(pr) } }
            .onChange(of: app.renamingProjectID) { _, id in
                if id == projectID {
                    nameFocused = true
                    app.renamingProjectID = nil
                }
            }
        } else {
            Text("Проект удалён").tw(14, lh: 20).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load(_ pr: Project) {
        name = pr.name
        instructions = pr.instructions
        editingInstructions = false
        // новый проект — сразу дать назвать
        if pr.name == "Новый проект" { nameFocused = true }
    }

    private func save(_ pr: Project) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty && n != pr.name { app.updateProject(pr) { $0.name = n } } else { name = pr.name }
    }

    // MARK: слева — поле и недавние

    private func main(_ pr: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            composer(pr)
            let list = app.conversations(in: pr.id)
            Text("Недавние").tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.top, 28).padding(.bottom, 4)
            if list.isEmpty {
                Text("Здесь пока пусто. Напиши выше — или перенеси сюда разговор, перетащив его на проект в панели слева.")
                    .tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.vertical, 12)
            }
            ForEach(list) { c in ProjectTalkCard(c: c) { app.openChat(c) } }
        }
    }

    /// Поле «начни разговор» прямо на странице: Enter — новый чат (или задача агента) в проекте с этим текстом
    private func composer(_ pr: Project) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(agent ? "Задача для агента в этом проекте…" : "Начни разговор в этом проекте…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.geist(15)).lineLimit(1...8)
                .focused($draftFocused)
                .onSubmit { start(pr) }
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    modeButton("Чат", on: !agent) { agent = false }
                    modeButton("Агент", on: agent) { agent = true }
                }
                .padding(2)
                .background(p.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: R.lg))
                Spacer()
                let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { start(pr) } label: {
                    Icon("arrow-up", 16).foregroundStyle(empty ? p.mutedFg : p.onGlow)
                        .frame(width: 32, height: 32)
                        .background(empty ? p.foreground.opacity(0.08) : p.glow, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(empty)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(draftFocused ? p.glow.opacity(0.35) : p.border))
        .contentShape(Rectangle())
        .onTapGesture { draftFocused = true }
    }

    private func modeButton(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).tw(13, lh: 18)
                .foregroundStyle(on ? p.foreground : p.mutedFg)
                .padding(.horizontal, 12).frame(height: 28)
                .background(on ? p.background : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(on ? p.border : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func start(_ pr: Project) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        app.newChat(in: pr, agent: agent)
        app.chat.send(text)
    }

    // MARK: справа — панель проекта

    private func aside(_ pr: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            block {
                HStack {
                    Text("Инструкции").tw(15, .medium, lh: 20)
                    Spacer()
                    IconButton(icon: editingInstructions ? "check" : "pencil", help: editingInstructions ? "Готово" : "Изменить") {
                        editingInstructions.toggle()
                    }
                }
                if editingInstructions {
                    ZStack(alignment: .topLeading) {
                        if instructions.isEmpty {
                            Text("Например: отвечай как редактор блога; пиши коротко; код — только на Swift")
                                .tw(13, lh: 18).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        TextEditor(text: $instructions)
                            .font(.geist(13)).scrollContentBackground(.hidden)
                            .padding(.horizontal, 5).padding(.vertical, 8)
                            .onChange(of: instructions) { _, v in
                                // сохраняем на лету, без кнопки
                                if v != pr.instructions { app.updateProject(pr) { $0.instructions = v } }
                            }
                    }
                    .frame(minHeight: 140)
                    .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    .padding(.top, 8)
                } else {
                    Text(pr.instructions.isEmpty ? "Расскажи Lumen, как вести разговоры этого проекта: кто ты, что важно, как отвечать." : pr.instructions)
                        .tw(13, lh: 19).foregroundStyle(p.mutedFg).lineLimit(3).padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { editingInstructions = true }
                }
            }
            divider
            block {
                let facts = memoryCount(pr)
                HStack(spacing: 10) {
                    Text("Память").tw(15, .medium, lh: 20)
                    Text(facts == 0 ? "пусто" : Plural.facts(facts)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(p.border))
                    Spacer()
                    Button { app.page = .memory } label: { Text("Посмотреть").tw(13, lh: 18) }.buttonStyle(.plain)
                }
                Text("Что Lumen запомнил из разговоров этого проекта. Видно во всех его чатах и задачах.")
                    .tw(13, lh: 19).foregroundStyle(p.mutedFg).padding(.top, 6)
            }
            divider
            block {
                HStack {
                    Text("Папка для агента").tw(15, .medium, lh: 20)
                    Spacer()
                    Button { app.chooseProjectFolder(pr) } label: { Text(pr.folder == nil ? "Выбрать" : "Сменить").tw(13, lh: 18) }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Icon("folder", 14).foregroundStyle(pr.folder == nil ? p.mutedFg : p.glow)
                    Text(pr.folder?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Не выбрана — задачи работают в папке из поля")
                        .tw(12, lh: 16).foregroundStyle(pr.folder == nil ? p.mutedFg : p.foreground)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.top, 6)
            }
            divider
            block { context(pr) }
        }
        .background(p.card.opacity(0.35), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.border))
    }

    private var divider: some View { p.border.frame(height: 1) }

    private func block<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }.padding(20)
    }

    private func memoryCount(_ pr: Project) -> Int {
        let ids = Set(app.conversations(in: pr.id).map(\.id))
        return app.memories.filter { $0.conversationID.map(ids.contains) == true }.count
    }

    /// «Контекст»: заполненность (сколько текста проекта уходит в каждый разговор) и файлы карточками по две
    private func context(_ pr: Project) -> some View {
        let files = app.files(of: pr)
        let used = files.reduce(0) { $0 + $1.text.count }
        let share = min(1, Double(used) / Double(ProjectFile.maxChars))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Контекст").tw(15, .medium, lh: 20)
                Spacer()
                IconButton(icon: "plus", help: "Добавить файл") { app.addFiles(to: pr) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.foreground.opacity(0.08))
                    Capsule().fill(p.glow).frame(width: max(6, g.size.width * share))
                }
            }
            .frame(height: 6).padding(.top, 10)
            Text("Занято \(Int((share * 100).rounded())) % места проекта").tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.top, 8)
            if files.isEmpty {
                Button { app.addFiles(to: pr) } label: {
                    Text("Добавь заметки, код или документы — их видит каждый разговор проекта.")
                        .tw(13, lh: 18).foregroundStyle(p.mutedFg).multilineTextAlignment(.leading)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(files) { f in FileTile(file: f, size: app.fileSize(f.text)) { app.removeFile(f, from: pr) } }
                }
                .padding(.top, 14)
            }
        }
    }
}

/// Файл проекта карточкой: имя, размер, внизу тип
private struct FileTile: View {
    let file: ProjectFile
    let size: String
    let remove: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name.uppercased()).tw(12, .medium, lh: 16).lineLimit(3)
            Text(size).tw(11, lh: 14).foregroundStyle(p.mutedFg)
            Spacer(minLength: 10)
            Text((file.name.split(separator: ".").last.map(String.init) ?? "text").uppercased())
                .tw(10, .medium, lh: 12).foregroundStyle(p.mutedFg)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: R.sm).strokeBorder(p.border))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(p.background.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(hover ? p.foreground.opacity(0.2) : p.border))
        .overlay(alignment: .topTrailing) {
            if hover { IconButton(icon: "x", help: "Убрать из проекта", action: remove).padding(4) }
        }
        .onHover { hover = $0 }
    }
}

/// Разговор на странице проекта: строкой с линией снизу, дата справа (как «Недавние» в Claude)
struct ProjectTalkCard: View {
    let c: Conversation
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(c.kind == .agent ? "square-terminal" : "message-square", 15).foregroundStyle(p.mutedFg)
                Text(c.title).tw(15, lh: 22).lineLimit(1)
                Spacer()
                Text(RelativeWhen.string(c.updatedAt)).tw(13, lh: 18).foregroundStyle(p.mutedFg)
            }
            .foregroundStyle(hover ? p.foreground : p.foreground.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 14)
            .background(hover ? p.foreground.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
