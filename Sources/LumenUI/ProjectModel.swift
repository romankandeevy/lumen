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

    /// Новый проект: сразу открывается его страница, название можно поменять там же
    @discardableResult
    func createProject(folder: URL? = nil) -> Project {
        let p = Project(name: folder?.lastPathComponent ?? "Новый проект", folder: folder?.path)
        try? store.save(p)
        reloadProjects()
        page = .project(p.id)
        return p
    }

    func updateProject(_ p: Project, _ change: (inout Project) -> Void) {
        var updated = project(p.id) ?? p
        change(&updated)
        try? store.save(updated)
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

    /// Новый чат (или задача агента) сразу в проекте
    func newChat(in p: Project, agent: Bool = false) {
        tab = agent ? .agent : .chat
        if agent, let f = p.folder { agentFolder = URL(fileURLWithPath: f) }
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
        var items = projects.filter { $0.id != c.projectID }.map { p in
            MenuItem(title: p.name, key: nil) { [weak self] in self?.move(c, to: p.id) }
        }
        if c.projectID != nil {
            items.append(MenuItem(title: "Убрать из проекта", key: nil, separated: !items.isEmpty) { [weak self] in self?.move(c, to: nil) })
        }
        items.append(MenuItem(title: "Новый проект…", key: "n", separated: true) { [weak self] in
            guard let self else { return }
            let p = self.createProject()
            self.move(c, to: p.id)
        })
        menu = MenuState(items: items, anchor: point)
    }
}
