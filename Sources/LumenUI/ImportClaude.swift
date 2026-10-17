import Foundation
import LumenCore
import LumenProviders
import SwiftUI

/// Импорт из Claude Code: человек сам отмечает разговоры и проекты, какие забрать
extension AppModel {
    /// Что можно перенести: разговоры, которых ещё нет в Lumen, и проекты-разделы приложения Claude
    struct ClaudeImportList: Sendable {
        var sessions: [ClaudeHistory.Session]
        var groups: [ClaudeHistory.Desktop.Group]
    }

    nonisolated static func claudeImportList(skip: Set<String>, lumenRoot: URL) -> ClaudeImportList {
        let desktop = ClaudeHistory.Desktop.load()
        return ClaudeImportList(sessions: ClaudeHistory.sessions(skip: skip, lumenRoot: lumenRoot, desktop: desktop),
                                groups: desktop?.groups ?? [])
    }

    /// id сессий claude, что уже есть в Lumen — второй раз их не предлагаем
    var knownSessionIDs: Set<String> { Set(conversations.compactMap(\.cliSessionID)) }

    /// Забрать выбранное. Разговор — задача агента в своей папке с той же сессией claude. Проект: тот, где разговор
    /// лежал в приложении Claude (с тем же названием), иначе — по папке. Отмеченные проекты переносятся и пустыми.
    /// Возвращает импортированные разговоры.
    @discardableResult
    func importClaude(_ sessions: [ClaudeHistory.Session], groups: [ClaudeHistory.Desktop.Group] = []) async -> [Conversation] {
        // разбор — в фоне: разговор Claude Code бывает на десятки мегабайт
        let parsed: [(String, ClaudeHistory.Session, ClaudeHistory.Transcript?, String)] = await Task.detached {
            sessions.map { s in
                let id = UUID().uuidString.lowercased()
                return (id, s, try? ClaudeHistory.transcript(s, conversationID: id), ClaudeHistory.truePath(s.cwd))
            }
        }.value
        for g in groups { _ = projectNamed(g.name, folder: nil) }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var done: [Conversation] = []
        for (id, s, t, cwd) in parsed {
            guard let t, !t.messages.isEmpty else {
                log("Импорт: не прочитался \(s.file.lastPathComponent)")
                continue
            }
            let exists = FileManager.default.fileExists(atPath: cwd)
            var c = Conversation(id: id, title: s.title, kind: .agent, folder: exists ? cwd : home, backend: .subscription,
                                 model: t.model.flatMap { $0.isGPT ? nil : $0 } ?? defaultAgentModel,
                                 effort: prefs.agentEffort ?? .high, cliSessionID: s.id,
                                 createdAt: t.createdAt, updatedAt: s.updatedAt)
            c.plan = t.plan
            c.mode = prefs.agentMode
            if let g = s.group {
                c.projectID = projectNamed(g.name, folder: exists ? cwd : nil).id
            } else if exists && cwd != home {
                c.projectID = projectFor(folder: cwd).id
            }
            do {
                try store.importConversation(c, messages: t.messages)
                done.append(c)
            } catch {
                log("Импорт \(s.id): \(error.localizedDescription)")
            }
        }
        reloadProjects()
        reloadConversations()
        return done
    }

    /// Проект Lumen для папки: уже есть — он, нет — новый, с именем папки
    func projectFor(folder: String) -> Project {
        let path = URL(fileURLWithPath: folder).standardizedFileURL.path
        if let p = projects.first(where: { $0.folder.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == path }) { return p }
        let p = Project(name: URL(fileURLWithPath: path).lastPathComponent, folder: path)
        try? store.save(p)
        reloadProjects()
        return p
    }

    /// Проект Lumen с таким названием (как проект в приложении Claude): есть — он (без папки получит эту), нет — новый
    func projectNamed(_ name: String, folder: String?) -> Project {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if var p = projects.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            if p.folder == nil, let folder {
                p.folder = folder
                try? store.save(p)
                reloadProjects()
            }
            return p
        }
        let p = Project(name: name, folder: folder)
        try? store.save(p)
        reloadProjects()
        return p
    }
}

/// Окно «Импорт из Claude Code»: проекты приложения Claude и разговоры по папкам, галочки, поиск
struct ImportClaudeSheet: View {
    typealias Group = ClaudeHistory.Desktop.Group

    @Bindable var app: AppModel
    let close: () -> Void
    /// Готовый список вместо чтения диска (снимки экранов)
    var preset: AppModel.ClaudeImportList?
    var prepicked: Set<String> = []

    @Environment(\.palette) private var p
    @State private var loaded: AppModel.ClaudeImportList?
    @State private var chosen: Set<String>?
    @State private var chosenGroups = Set<String>()
    @State private var query = ""
    @State private var working = false

    private var list: AppModel.ClaudeImportList? { preset ?? loaded }
    private var picked: Set<String> {
        get { chosen ?? prepicked }
        nonmutating set { chosen = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Импорт из Claude Code").font(.geist(18, .semibold)) } icon: { Icon("download", 16).foregroundStyle(p.glow) }
                Text("Отметь разговоры или целые проекты. Проекты из Claude перенесутся с теми же названиями, разговоры станут задачами агента и продолжатся с того же места.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SearchField(text: $query, placeholder: "Поиск по названию, папке, первой фразе")
            SwiftUI.Group {
                if let list {
                    if list.sessions.isEmpty && list.groups.isEmpty {
                        Text("Новых разговоров в Claude Code нет — всё уже здесь или там пусто.")
                            .font(.geist(14)).foregroundStyle(p.mutedFg)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        table
                    }
                } else {
                    HStack(spacing: 8) {
                        LiveDot(color: p.glow, size: 6)
                        Text("Читаю разговоры Claude Code…").font(.geist(14)).foregroundStyle(p.mutedFg)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(height: 420)
            HStack(spacing: 8) {
                if list != nil {
                    let shown = filtered.map(\.id)
                    let all = !shown.isEmpty && shown.allSatisfy(picked.contains)
                    LButton(title: all ? "Снять все" : "Выбрать все", kind: .ghost, small: true) {
                        if all { picked.subtract(shown) } else { picked.formUnion(shown) }
                    }
                    Text(counter).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
                Spacer()
                LButton(title: "Отмена", kind: .ghost, action: close).keyboardShortcut(.cancelAction)
                LButton(title: working ? "Переношу…" : "Импортировать", kind: .primary) { run() }
                    .disabled((picked.isEmpty && chosenGroups.isEmpty) || working)
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(p.popover)
        .foregroundStyle(p.foreground)
        .preferredColorScheme(p.scheme)
        .task {
            guard preset == nil else { return }
            let skip = app.knownSessionIDs, root = app.paths.root
            loaded = await Task.detached { AppModel.claudeImportList(skip: skip, lumenRoot: root) }.value
        }
    }

    private var counter: String {
        var parts: [String] = []
        if !picked.isEmpty { parts.append("\(picked.count) " + Plural.form(picked.count, "разговор", "разговора", "разговоров")) }
        let groups = pickedGroups.count
        if groups > 0 { parts.append("\(groups) " + Plural.form(groups, "проект", "проекта", "проектов")) }
        return parts.isEmpty ? "" : "Выбрано: " + parts.joined(separator: ", ")
    }

    private var filtered: [ClaudeHistory.Session] {
        let all = list?.sessions ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { ($0.title + " " + $0.cwd + " " + $0.firstPrompt + " " + ($0.group?.name ?? "")).lowercased().contains(q) }
    }

    /// Отмеченные проекты: сам проект или все его разговоры
    private var pickedGroups: [Group] {
        (list?.groups ?? []).filter { g in
            let items = (list?.sessions ?? []).filter { $0.group?.id == g.id }.map(\.id)
            return chosenGroups.contains(g.id) || (!items.isEmpty && items.allSatisfy(picked.contains))
        }
    }

    private enum Section: Identifiable {
        case group(Group, [ClaudeHistory.Session])
        case folder(String, [ClaudeHistory.Session])
        var id: String {
            switch self {
            case .group(let g, _): "g:" + g.id
            case .folder(let f, _): "f:" + f
            }
        }
    }

    /// Сверху — проекты приложения Claude (в его порядке, и пустые), ниже — остальные разговоры по папкам
    private var sections: [Section] {
        let items = filtered
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        var out: [Section] = []
        for g in list?.groups ?? [] {
            let mine = items.filter { $0.group?.id == g.id }
            if !mine.isEmpty || (!searching || g.name.lowercased().contains(query.lowercased())) { out.append(.group(g, mine)) }
        }
        var order: [String] = []
        var by: [String: [ClaudeHistory.Session]] = [:]
        for s in items where s.group == nil {
            if by[s.cwd] == nil { order.append(s.cwd) }
            by[s.cwd, default: []].append(s)
        }
        return out + order.map { .folder($0, by[$0] ?? []) }
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        switch section {
                        case .group(let g, let items):
                            groupHeader(g, items)
                            if items.isEmpty {
                                Text("Пустой проект — перенесётся без разговоров").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                                    .padding(.leading, 34).padding(.bottom, 2)
                            }
                            ForEach(items) { s in row(s) }
                        case .folder(let cwd, let items):
                            HStack(spacing: 6) {
                                Icon("folder", 14)
                                Text(URL(fileURLWithPath: cwd).lastPathComponent).tw(12, .medium, lh: 16)
                                Text(Self.short(cwd)).tw(12, lh: 16).lineLimit(1).truncationMode(.middle)
                            }
                            .foregroundStyle(p.mutedFg)
                            .padding(.horizontal, 8).padding(.bottom, 4)
                            ForEach(items) { s in row(s) }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .background(p.input.opacity(0.15), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }

    /// Заголовок проекта Claude: галочка — весь проект с разговорами
    private func groupHeader(_ g: Group, _ items: [ClaudeHistory.Session]) -> some View {
        let ids = items.map(\.id)
        let on = pickedGroups.contains(g)
        return Button {
            if on {
                chosenGroups.remove(g.id)
                picked.subtract(ids)
            } else {
                chosenGroups.insert(g.id)
                picked.formUnion(ids)
            }
        } label: {
            HStack(spacing: 10) {
                Icon(on ? "circle-check" : "square", 16).foregroundStyle(on ? p.glow : p.mutedFg)
                Icon("layout-grid", 14).foregroundStyle(p.mutedFg)
                Text(g.name).tw(14, .semibold, lh: 20).lineLimit(1)
                Text("проект Claude").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                Spacer(minLength: 8)
                if !items.isEmpty {
                    Text("\(items.count) " + Plural.form(items.count, "разговор", "разговора", "разговоров"))
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ s: ClaudeHistory.Session) -> some View {
        let on = picked.contains(s.id)
        return Button {
            if on {
                picked.remove(s.id)
                if let g = s.group { chosenGroups.remove(g.id) }
            } else { picked.insert(s.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Icon(on ? "circle-check" : "square", 16)
                    .foregroundStyle(on ? p.glow : p.mutedFg)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.title).tw(14, .medium, lh: 20).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Self.when(s.updatedAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    }
                    if s.firstPrompt != s.title {
                        Text(s.firstPrompt).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .padding(.leading, s.group == nil ? 0 : 24)
            .background(on ? p.foreground.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run() {
        let selected = (list?.sessions ?? []).filter { picked.contains($0.id) }
        let groups = pickedGroups
        working = true
        Task {
            let done = await app.importClaude(selected, groups: groups)
            working = false
            close()
            if let first = done.first { app.openChat(first) }
            else if let g = groups.first, let pr = app.projects.first(where: { $0.name == g.name }) { app.openProject(pr) }
        }
    }

    static func short(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM, HH:mm" : "d MMM yyyy"
        return f.string(from: d)
    }
}
