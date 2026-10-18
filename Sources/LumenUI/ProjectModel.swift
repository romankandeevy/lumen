import AppKit
import Foundation
import LumenCore
import LumenStorage

/// Проекты в приложении (Project.swift): список, правки, файлы, перенос разговоров
extension AppModel {
    func reloadProjects() {
        projects = (try? store.projects()) ?? []
    }

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func conversations(in projectID: String) -> [Conversation] {
        conversations.filter { $0.projectID == projectID }
    }

    /// Проекты одной вкладки: у чата, агента и ботов они свои и между собой не связаны
    func projects(of kind: ConversationKind) -> [Project] {
        let k = Self.projectKind(kind)
        return projects.filter { $0.kind == k }
    }

    /// Разговор группы ботов живёт в проектах ботов
    static func projectKind(_ k: ConversationKind) -> ConversationKind { k == .group ? .bot : k }

    /// До 1.5 проект был общим для чата, агента и ботов: удалил в чате — пропал и у агента.
    /// Теперь у каждой вкладки свой. Проект с разговорами разных видов делится один раз: копия на каждый вид
    /// (инструкции, файлы, контекст — те же), разговоры переезжают в свою. Пустой — к агенту, если у него папка, иначе к чату
    func splitProjectsByKind() {
        guard (try? store.value("projectsSplitByKind", as: Bool.self)) != true else { return }
        var moved = false
        for p in projects {
            let mine = conversations.filter { $0.projectID == p.id }
            let kinds = Set(mine.map { Self.projectKind($0.kind) })
            var order = [ConversationKind.chat, .agent, .bot].filter { kinds.contains($0) }
            if order.isEmpty { order = [p.folder == nil ? .chat : .agent] }
            if p.kind != order[0] {
                var main = p
                main.kind = order[0]
                try? store.save(main)
            }
            for k in order.dropFirst() {
                let copy = Project(name: p.name, instructions: p.instructions, folder: p.folder, pinned: p.pinned, kind: k)
                try? store.save(copy)
                for var f in files(of: p) {
                    f.id = nil
                    f.projectID = copy.id
                    _ = try? store.save(f)
                }
                // контекст без своей папки лежит в папке Lumen — у копии свой, с тем же текстом
                if p.ownFolder == nil {
                    let from = contextURL(p), to = contextURL(copy)
                    try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.copyItem(at: from, to: to)
                }
                for var c in mine where Self.projectKind(c.kind) == k {
                    c.projectID = copy.id
                    try? store.save(c)
                }
                moved = true
                log("Проекты: «\(p.name)» был общим — у вкладки «\(k.rawValue)» теперь свой")
            }
        }
        try? store.set("projectsSplitByKind", true)
        reloadProjects()
        if moved { reloadConversations() }
    }

    /// Новый проект: сразу открывается его страница, название можно поменять там же
    @discardableResult
    func createProject(folder: URL? = nil, kind: ConversationKind = .chat) -> Project {
        let kind = Self.projectKind(kind)
        // у этой папки на этой вкладке уже есть проект — открыть его, второй такой же не нужен
        if let folder, let same = projects(of: kind).first(where: { $0.folder.map { URL(fileURLWithPath: $0).standardizedFileURL.path.lowercased() }
                                                            == folder.standardizedFileURL.path.lowercased() }) {
            page = .project(same.id)
            return same
        }
        let p = Project(name: freeProjectName(folder?.lastPathComponent ?? "Новый проект", kind: kind), folder: folder?.path, kind: kind)
        try? store.save(p)
        ensureContextFile(p)
        reloadProjects()
        page = .project(p.id)
        return p
    }

    /// Два проекта с одним названием на одной вкладке не бывает: занято — «Название 2», «Название 3»…
    func freeProjectName(_ name: String, except id: String? = nil, kind: ConversationKind) -> String {
        let taken = Set(projects(of: kind).filter { $0.id != id }.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)".lowercased()) { n += 1 }
        return "\(name) \(n)"
    }

    /// Одинаковые проекты (то же название, та же папка или её нет) — в один: разговоры и файлы переезжают в первый
    func mergeDuplicateProjects() {
        var seen: [String: Project] = [:]
        for p in projects {
            let key = p.kind.rawValue + "|" + p.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let keep = seen[key] else { seen[key] = p; continue }
            let a = keep.folder.map { $0.lowercased() }, b = p.folder.map { $0.lowercased() }
            guard a == b || a == nil || b == nil else { continue }
            for var c in conversations where c.projectID == p.id {
                c.projectID = keep.id
                try? store.save(c)
            }
            for var f in (try? store.files(in: p.id)) ?? [] {
                f.projectID = keep.id
                _ = try? store.save(f)
            }
            if keep.folder == nil, let f = p.folder { var k = keep; k.folder = f; try? store.save(k); seen[key] = k }
            try? store.deleteProject(p.id)
            log("Проекты: «\(p.name)» был дважды — слил в один")
        }
        reloadProjects()
        reloadConversations()
    }

    func updateProject(_ p: Project, _ change: (inout Project) -> Void) {
        var updated = project(p.id) ?? p
        change(&updated)
        updated.name = freeProjectName(updated.name, except: updated.id, kind: updated.kind)
        try? store.save(updated)
        ensureContextFile(updated)
        reloadProjects()
        // инструкции и файлы — в системном промпте: следующий ход возьмёт новые
        chat.promptChanged(projectID: p.id)
    }

    func deleteProject(_ p: Project) {
        try? store.deleteProject(p.id)
        if page == .project(p.id) { page = .chat }
        reloadProjects()
        reloadConversations()
    }

    func openProject(_ p: Project) {
        page = .project(p.id)
    }

    /// Новый чат (или задача агента — у проекта агента) сразу в проекте
    func newChat(in p: Project) {
        let agent = p.kind == .agent
        tab = agent ? .agent : .chat
        if agent, let f = p.folder { agentFolder = URL(fileURLWithPath: f) }
        // контекст проекта заводится заранее: первое сообщение уже уйдёт с ним
        ensureContextFile(p)
        chat.startNew(projectID: p.id)
        page = .chat
    }

    func move(_ c: Conversation, to projectID: String?) {
        var updated = (try? store.conversations().first { $0.id == c.id }) ?? c
        updated.projectID = projectID
        try? store.save(updated)
        chat.moved(c.id, projectID)
        reloadConversations()
    }

    // MARK: файлы

    func files(of p: Project) -> [ProjectFile] {
        (try? store.files(in: p.id)) ?? []
    }

    /// Добавить текстовые файлы (код, заметки, markdown). Не текст и слишком большое — пропускаем.
    func addFiles(to p: Project) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Текстовые файлы для проекта «\(p.name)»: Lumen будет видеть их в каждом разговоре проекта"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFile(url, to: p) }
        updateProject(p) { _ in }
    }

    @discardableResult
    func addFile(_ url: URL, to p: Project) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.count <= ProjectFile.maxChars else { return false }
        return (try? store.save(ProjectFile(projectID: p.id, name: url.lastPathComponent, text: text))) != nil
    }

    func removeFile(_ f: ProjectFile, from p: Project) {
        if let id = f.id { try? store.deleteFile(id) }
        updateProject(p) { _ in }
    }

    func chooseProjectFolder(_ p: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Выбрать"
        panel.message = "Папка, в которой агент работает над задачами проекта «\(p.name)»"
        if panel.runModal() == .OK, let url = panel.url {
            updateProject(p) { $0.folder = url.path }
            rememberFolder(url)
        }
    }

    // MARK: меню

    func showProjectMenu(_ p: Project, at point: CGPoint) {
        menu = MenuState(items: [
            MenuItem(title: "Открыть проект", key: "o") { [weak self] in self?.openProject(p) },
            MenuItem(title: p.pinned ? "Открепить" : "Закрепить", key: "p") { [weak self] in self?.updateProject(p) { $0.pinned.toggle() } },
            MenuItem(title: "Переименовать", key: "r") { [weak self] in
                self?.page = .project(p.id)
                self?.renamingProjectID = p.id
            },
            MenuItem(title: "Удалить проект", key: "d", destructive: true, separated: true) { [weak self] in self?.deleteProject(p) },
        ], anchor: point)
    }

    /// «Переместить в проект» — второе меню на том же месте
    func showMoveMenu(_ c: Conversation, at point: CGPoint) {
        var items = projects(of: c.kind).filter { $0.id != c.projectID }.map { p in
            MenuItem(title: p.name, key: nil) { [weak self] in self?.move(c, to: p.id) }
        }
        if c.projectID != nil {
            items.append(MenuItem(title: "Убрать из проекта", key: nil, separated: !items.isEmpty) { [weak self] in self?.move(c, to: nil) })
        }
        items.append(MenuItem(title: "Новый проект…", key: "n", separated: true) { [weak self] in
            guard let self else { return }
            let p = self.createProject(kind: c.kind)
            self.move(c, to: p.id)
        })
        menu = MenuState(items: items, anchor: point)
    }
}
