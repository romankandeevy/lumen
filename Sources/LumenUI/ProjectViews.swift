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
    @State private var hover = false

    @State private var dotsHover = false

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
                    if count > 0 && !hover { Text("\(count)").font(.geist(11)).foregroundStyle(p.mutedFg) }
                }
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
                GeometryReader { g in
                    let f = g.frame(in: .global)
                    DotsButton { app.showProjectMenu(project, at: CGPoint(x: f.minX, y: f.maxY + 4)) }
                }
                .frame(width: 26, height: 26).onHover { dotsHover = $0 }.padding(.trailing, 4)
            }
        }
        .onRightClick { point in app.showProjectMenu(project, at: point) }
    }
}

/// Маленький «+» рядом с подписью группы
struct SmallPlus: View {
    let help: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon("plus", 14).foregroundStyle(hover ? p.foreground : p.mutedFg)
                .frame(width: 20, height: 20)
                .background(hover ? p.foreground.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: R.sm))
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
    @FocusState private var nameFocused: Bool

    private var project: Project? { app.project(projectID) }

    var body: some View {
        if let pr = project {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        // название правится прямо здесь
                        TextField("Название проекта", text: $name)
                            .textFieldStyle(.plain).tw(26.4, .semibold, lh: 33).tracking(-0.53)
                            .focused($nameFocused)
                            .onSubmit { save(pr) }
                            .onChange(of: nameFocused) { _, f in if !f { save(pr) } }
                        Text("Инструкции и файлы проекта видят все его чаты и задачи агента.")
                            .tw(14, lh: 20).foregroundStyle(p.mutedFg)
                    }
                    Spacer(minLength: 0)
                    LButton(title: "Новая задача", icon: "square-terminal", kind: .outline) { app.newChat(in: pr, agent: true) }
                        .disabled(pr.folder == nil && app.agentFolder == nil)
                    LButton(title: "Новый чат", icon: "plus", kind: .primary) { app.newChat(in: pr) }
                }
                .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 20)

                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            talks(pr).frame(minWidth: 400)
                            aside(pr).frame(width: 300)
                        }
                        VStack(alignment: .leading, spacing: 32) { aside(pr); talks(pr) }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 40)
                }
                .scrollIndicators(.never)
            }
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
        // новый проект — сразу дать назвать
        if pr.name == "Новый проект" { nameFocused = true }
    }

    private func save(_ pr: Project) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty && n != pr.name { app.updateProject(pr) { $0.name = n } } else { name = pr.name }
    }

    private func talks(_ pr: Project) -> some View {
        let list = app.conversations(in: pr.id)
        return VStack(alignment: .leading, spacing: 0) {
            GroupTitle(text: "Разговоры", aside: list.isEmpty ? nil : "\(list.count)")
            if list.isEmpty {
                Text("Здесь пока пусто. Начни новый чат или задачу — или перенеси сюда разговор через «…» → «Переместить в проект».")
                    .tw(14, lh: 20).foregroundStyle(p.mutedFg)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
                    .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
            }
            VStack(spacing: 8) {
                ForEach(list) { c in ProjectTalkCard(c: c) { app.openChat(c) } }
            }
        }
    }

    private func aside(_ pr: Project) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Инструкции")
                ZStack(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text("Например: отвечай как редактор блога; пиши коротко; код — только на Swift")
                            .tw(14, lh: 20).foregroundStyle(p.mutedFg).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    TextEditor(text: $instructions)
                        .font(.geist(14)).scrollContentBackground(.hidden)
                        .padding(.horizontal, 7).padding(.vertical, 8)
                        .onChange(of: instructions) { _, v in
                            // сохраняем на лету, без кнопки
                            if v != pr.instructions { app.updateProject(pr) { $0.instructions = v } }
                        }
                }
                .frame(minHeight: 120)
                .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Файлы", aside: "видны в каждом разговоре")
                VStack(spacing: 6) {
                    ForEach(app.files(of: pr)) { f in
                        HStack(spacing: 10) {
                            Icon("file-text", 16).foregroundStyle(p.mutedFg)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(f.name).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                Text(app.fileSize(f.text)).tw(11, lh: 14).foregroundStyle(p.mutedFg)
                            }
                            Spacer()
                            IconButton(icon: "x", help: "Убрать из проекта") { app.removeFile(f, from: pr) }
                        }
                        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    }
                    LButton(title: "Добавить файл", icon: "plus", kind: .outline, small: true) { app.addFiles(to: pr) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Папка для агента")
                HStack(spacing: 10) {
                    Icon("folder", 16).foregroundStyle(pr.folder == nil ? p.mutedFg : p.glow)
                    Text(pr.folder?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Не выбрана — задачи работают в выбранной в поле папке")
                        .tw(12, lh: 16).foregroundStyle(pr.folder == nil ? p.mutedFg : p.foreground)
                        .lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                LButton(title: pr.folder == nil ? "Выбрать папку…" : "Другая папка…", kind: .outline, small: true) { app.chooseProjectFolder(pr) }
                    .padding(.top, 8)
            }
        }
    }
}

/// Разговор на странице проекта
struct ProjectTalkCard: View {
    let c: Conversation
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(c.kind == .agent ? "square-terminal" : "message-square", 16).foregroundStyle(p.mutedFg)
                Text(c.title).tw(14, lh: 20).lineLimit(1)
                Spacer()
                Text(RelativeWhen.string(c.updatedAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(hover ? p.card : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(hover ? p.glow.opacity(0.3) : p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
