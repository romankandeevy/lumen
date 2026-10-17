import Foundation
import LumenCore
import LumenProviders
import SwiftUI

/// Импорт разговоров из Claude Code: человек сам отмечает, какие забрать
extension AppModel {
    /// Разговоры Claude Code, которых ещё нет в Lumen (служебные и самого Lumen — не показываем)
    nonisolated static func claudeSessions(skip: Set<String>, lumenRoot: URL) -> [ClaudeHistory.Session] {
        ClaudeHistory.sessions(skip: skip, lumenRoot: lumenRoot)
    }

    /// id сессий claude, что уже есть в Lumen — второй раз их не предлагаем
    var knownSessionIDs: Set<String> { Set(conversations.compactMap(\.cliSessionID)) }

    /// Забрать выбранные разговоры. Каждый — задача агента в своей папке с той же сессией claude;
    /// папка становится проектом Lumen (если его ещё нет), чтобы у разговоров была общая память проекта.
    /// Возвращает импортированные разговоры.
    @discardableResult
    func importClaude(_ sessions: [ClaudeHistory.Session]) async -> [Conversation] {
        // разбор — в фоне: разговор Claude Code бывает на десятки мегабайт
        let parsed: [(String, ClaudeHistory.Session, ClaudeHistory.Transcript?)] = await Task.detached {
            sessions.map { s in
                let id = UUID().uuidString.lowercased()
                return (id, s, try? ClaudeHistory.transcript(s, conversationID: id))
            }
        }.value
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var done: [Conversation] = []
        for (id, s, t) in parsed {
            guard let t, !t.messages.isEmpty else {
                log("Импорт: не прочитался \(s.file.lastPathComponent)")
                continue
            }
            let cwd = URL(fileURLWithPath: s.cwd).standardizedFileURL.path
            let exists = FileManager.default.fileExists(atPath: cwd)
            var c = Conversation(id: id, title: s.title, kind: .agent, folder: exists ? cwd : home, backend: .subscription,
                                 model: t.model.flatMap { $0.isGPT ? nil : $0 } ?? defaultAgentModel,
                                 effort: prefs.agentEffort ?? .high, cliSessionID: s.id,
                                 createdAt: t.createdAt, updatedAt: s.updatedAt)
            c.plan = t.plan
            c.mode = prefs.agentMode
            if exists && cwd != home { c.projectID = projectFor(folder: cwd).id }
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
}

/// Окно «Импорт из Claude Code»: список разговоров по папкам, галочки, поиск
struct ImportClaudeSheet: View {
    @Bindable var app: AppModel
    let close: () -> Void
    /// Готовый список вместо чтения диска (снимки экранов)
    var preset: [ClaudeHistory.Session]?
    var prepicked: Set<String> = []

    @Environment(\.palette) private var p
    @State private var loaded: [ClaudeHistory.Session]?
    @State private var chosen: Set<String>?
    private var sessions: [ClaudeHistory.Session]? { preset ?? loaded }
    private var picked: Set<String> {
        get { chosen ?? prepicked }
        nonmutating set { chosen = newValue }
    }
    @State private var query = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Импорт из Claude Code").font(.geist(18, .semibold)) } icon: { Icon("download", 16).foregroundStyle(p.glow) }
                Text("Отметь разговоры, которые хочешь перенести. Каждый станет задачей агента в той же папке и продолжится с того же места; папка станет проектом Lumen.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SearchField(text: $query, placeholder: "Поиск по названию, папке, первой фразе")
            Group {
                if let sessions {
                    if sessions.isEmpty {
                        Text("Новых разговоров в Claude Code нет — всё уже здесь или там пусто.")
                            .font(.geist(14)).foregroundStyle(p.mutedFg)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        list
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
                if let sessions, !sessions.isEmpty {
                    let shown = filtered.map(\.id)
                    let all = !shown.isEmpty && shown.allSatisfy(picked.contains)
                    LButton(title: all ? "Снять все" : "Выбрать все", kind: .ghost, small: true) {
                        if all { picked.subtract(shown) } else { picked.formUnion(shown) }
                    }
                    Text(picked.isEmpty ? "" : "Выбрано: \(picked.count)").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
                Spacer()
                LButton(title: "Отмена", kind: .ghost, action: close).keyboardShortcut(.cancelAction)
                LButton(title: working ? "Переношу…" : "Импортировать", kind: .primary) { run() }
                    .disabled(picked.isEmpty || working)
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
            loaded = await Task.detached { AppModel.claudeSessions(skip: skip, lumenRoot: root) }.value
        }
    }

    private var filtered: [ClaudeHistory.Session] {
        let all = sessions ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { ($0.title + " " + $0.cwd + " " + $0.firstPrompt).lowercased().contains(q) }
    }

    /// По папкам; папки — по свежести последнего разговора
    private var grouped: [(String, [ClaudeHistory.Session])] {
        var order: [String] = []
        var by: [String: [ClaudeHistory.Session]] = [:]
        for s in filtered {
            if by[s.cwd] == nil { order.append(s.cwd) }
            by[s.cwd, default: []].append(s)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(grouped, id: \.0) { cwd, items in
                    VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .background(p.input.opacity(0.15), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }

    private func row(_ s: ClaudeHistory.Session) -> some View {
        let on = picked.contains(s.id)
        return Button {
            if on { picked.remove(s.id) } else { picked.insert(s.id) }
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
            .background(on ? p.foreground.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: R.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run() {
        let selected = (sessions ?? []).filter { picked.contains($0.id) }
        working = true
        Task {
            let done = await app.importClaude(selected)
            working = false
            close()
            if let first = done.first { app.openChat(first) }
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
