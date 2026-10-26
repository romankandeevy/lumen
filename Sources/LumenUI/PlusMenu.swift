import AppKit
import LumenCore
import SwiftUI

/// «+» в поле ввода — как в Claude: файлы и фото (⌘U), папка агента, навыки, коннекторы (вкл/выкл прямо тут), боты.
/// Подменю открываются на месте, со строкой «назад». Только то, что работает.
struct PlusMenu: View {
    @Bindable var app: AppModel
    let agent: Bool
    /// Новая задача агента — папку ещё можно выбрать
    var canPickFolder = false
    /// Разговор, в который это поле пишет (у разделённого экрана — свой)
    var chat: ChatController
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    /// «Ресерч» на это сообщение: включён в меню или таблеткой у поля
    @Binding var research: Bool
    /// Что добавлено из GitHub в это сообщение (таблетка у «+»)
    @Binding var github: [GitHubAdded]
    /// Поиск в сети, память и ресерч — не у ботов и групп: у них права из паспорта
    var showsTools = true
    /// Для снимков: показать эту страницу меню сразу, без всплывающего окна
    var previewPage: Page?

    @Environment(\.palette) private var p
    @State private var open = false
    @State private var page: Page = .main
    @State private var hover = false
    @State private var repoText = ""
    @State var repos: [(slug: String, note: String)] = []
    @State private var working = false
    @State private var note: String?
    /// «Новый проект» в подменю: поле названия раскрыто
    @State private var naming = false
    @State private var projectName = ""

    enum Page { case main, skills, connectors, bots, artifacts, github, project }

    private var skills: [Skill] { app.skills.filter(\.info.enabled) }
    private var botsHere: Bool { !agent && app.chat.conversation?.kind != .bot && !app.bots.isEmpty }

    var body: some View {
        if let previewPage {
            panel.onAppear { page = previewPage }
        } else {
            button
        }
    }

    /// Меню: строки текущей страницы на подложке всплывающего окна
    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch page {
            case .main: main
            case .skills: skillsPage
            case .connectors: connectorsPage
            case .bots: botsPage
            case .artifacts: artifactsPage
            case .github: githubPage
            case .project: projectPage
            }
        }
        .padding(6)
        // шире, чем было (232): названия пунктов, поле ссылки и репозитории не режутся (Рома, 26.10)
        .frame(width: page == .github ? 360 : 300)
        .background(p.popover)
        .environment(\.palette, p)
        .preferredColorScheme(p.scheme)
        .animation(.easeOut(duration: 0.12), value: page)
    }

    private var button: some View {
        Button { page = .main; open.toggle() } label: {
            // «+» 36, скругление 11; цвет чуть светлее подписей (#A3A9B8 у «Люмена»)
            Icon("plus", 18).foregroundStyle(hover || open ? p.foreground : p.mutedFg.mixed(with: p.foreground, 0.2))
                .frame(width: 36, height: 36)
                .background(hover || open ? p.hover : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Добавить")
        .accessibilityLabel("Добавить файлы, навыки, коннекторы")
        .background {
            // ⌘U — сразу файлы, без меню
            Button("") { addFiles() }.keyboardShortcut("u", modifiers: .command).opacity(0).allowsHitTesting(false)
        }
        // меню открывается сбоку от «+», а не над ним по центру
        .popover(isPresented: $open, arrowEdge: .trailing) { panel }
    }

    @ViewBuilder private var main: some View {
        Row(icon: "paperclip", title: "Добавить файлы или фото", trailing: "⌘U") { addFiles() }
        Row(icon: "github", title: "Добавить из GitHub…", chevron: true) {
            note = nil
            page = .github
            Task { repos = await app.githubRepos() }
        }
        Row(icon: "folder-plus", title: "Добавить в проект…", chevron: true) { note = nil; page = .project }
        Row(icon: "layout-grid", title: "Из артефактов", chevron: true) { page = .artifacts }
        if agent && canPickFolder {
            Row(icon: "folder", title: "Выбрать папку") { open = false; app.chooseFolder() }
        }
        if !skills.isEmpty {
            Row(icon: "book-open", title: "Навыки", chevron: true) { page = .skills }
        }
        Row(icon: "waypoints", title: "Коннекторы", chevron: true) { page = .connectors }
        if botsHere {
            Row(icon: "bot", title: "Позвать бота", chevron: true) { page = .bots }
        }
        if showsTools {
            p.border.frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4)
            ToggleRow(icon: "globe", title: "Поиск в сети", isOn: webBinding)
            ToggleRow(icon: "brain", title: "Память о тебе", isOn: memoryBinding)
            ToggleRow(icon: "flask-conical", title: "Ресерч", isOn: researchBinding)
        }
    }

    // MARK: переключатели (те же, что таблетки у поля)

    private var webBinding: Binding<Bool> {
        Binding(get: { app.prefs.webSearch }, set: { v in
            app.update { $0.webSearch = v }
            if !v { research = false }
        })
    }

    private var memoryBinding: Binding<Bool> {
        Binding(get: { app.prefs.useMemory }, set: { v in app.update { $0.useMemory = v } })
    }

    private var researchBinding: Binding<Bool> {
        Binding(get: { research }, set: { v in
            research = v
            // ресерчу нужна сеть
            if v { app.update { $0.webSearch = true } }
        })
    }

    // MARK: GitHub

    @ViewBuilder private var githubPage: some View {
        Back(title: "Из GitHub") { page = .main }
        HStack(spacing: 6) {
            TextField("owner/repo или ссылка", text: $repoText)
                .textFieldStyle(.plain).font(.geist(13))
                .padding(.horizontal, 10).frame(height: 32)
                .background(p.input.opacity(0.5), in: RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
                .onSubmit { importRepo(repoText) }
                .disabled(working)
            Button { importRepo(repoText) } label: {
                Text("Взять").font(.geist(12.5, .medium)).foregroundStyle(p.onGlow)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(p.accent.opacity(repoText.isEmpty || working ? 0.4 : 1), in: RoundedRectangle(cornerRadius: R.md))
            }
            .buttonStyle(.plain).disabled(repoText.isEmpty || working)
        }
        .padding(.horizontal, 4).padding(.top, 2)
        Text(agent ? "Склонируется в папку Lumen и станет доступна агенту. Приватный — если вошёл в gh."
                   : "Склонируется в папку Lumen; в разговор попадут README и список файлов.")
            .font(.geist(11.5)).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.top, 2).fixedSize(horizontal: false, vertical: true)
        if working {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Забираю репозиторий…").font(.geist(12)).foregroundStyle(p.mutedFg) }
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        if let note {
            Text(note).font(.geist(12)).foregroundStyle(Palette.destructive).padding(.horizontal, 8).fixedSize(horizontal: false, vertical: true)
        }
        if !repos.isEmpty {
            Section(title: "Твои репозитории")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(repos, id: \.slug) { r in
                        // владелец у своих один и тот же — в названии только имя, владелец в подсказке
                        Row(icon: "git-branch", title: String(r.slug.split(separator: "/").last ?? Substring(r.slug)),
                            note: r.note.isEmpty ? nil : r.note) { repoText = r.slug; importRepo(r.slug) }
                            .help(r.slug)
                    }
                }
            }
            .frame(height: min(CGFloat(repos.count) * 42, 252))
        }
    }

    private func importRepo(_ text: String) {
        guard !working else { return }
        working = true
        note = nil
        Task {
            defer { working = false }
            do {
                let r = try await app.importGitHub(text)
                // в поле — одна карточка репозитория (как в Claude): у агента это папка с доступом, у чата — README и список файлов
                var card: Attachment?
                if agent {
                    _ = chat.addPaths([r.folder])
                    card = Attachment(name: r.repo.name, kind: .file, mime: "inode/directory", path: r.folder.path, size: 0)
                } else if let summary = r.summary {
                    card = app.importAttachment(summary)
                }
                guard var card else { throw AppModel.GitHubError.failed("В «\(r.repo.slug)» нечего показать чату: нет README и файлов") }
                card.name = r.repo.name
                card.repo = r.repo.slug
                attachments.removeAll { $0.repo == r.repo.slug }
                attachments.append(card)
                github.removeAll { $0.slug == r.repo.slug }
                github.append(GitHubAdded(slug: r.repo.slug, folder: r.folder, attachmentIDs: [card.id]))
                repoText = ""
                open = false
            } catch {
                note = error.localizedDescription
            }
        }
    }

    // MARK: в проект

    @ViewBuilder private var projectPage: some View {
        Back(title: "Добавить в проект") { page = .main }
        let list = app.projects(of: agent ? .agent : .chat)
        let current = app.project(chat.conversation?.projectID ?? chat.newProjectID)
        let texts = attachments.filter { $0.kind == .text }
        Text(texts.isEmpty ? "Выбери проект и файлы — Lumen будет видеть их в каждом разговоре проекта."
                           : "Прикреплённые текстовые файлы (\(texts.count)) уйдут в выбранный проект.")
            .font(.geist(11.5)).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.bottom, 4).fixedSize(horizontal: false, vertical: true)
        // новый проект — прямо здесь, не уходя из разговора (Рома, 26.10: «почему нет кнопки создать проект»)
        if naming {
            HStack(spacing: 6) {
                TextField("Название проекта", text: $projectName)
                    .textFieldStyle(.plain).font(.geist(13))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(p.input.opacity(0.5), in: RoundedRectangle(cornerRadius: R.md))
                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.glow.opacity(0.4)))
                    .onSubmit { createProject(texts) }
                Button { createProject(texts) } label: {
                    Text("Создать").font(.geist(12.5, .medium)).foregroundStyle(p.onGlow)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(p.accent, in: RoundedRectangle(cornerRadius: R.md))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        } else {
            Row(icon: "plus", title: "Новый проект", accent: true) { projectName = ""; naming = true }
        }
        if !list.isEmpty {
            Section(title: "Твои проекты")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { pr in
                        Row(icon: "folder", title: pr.name, note: pr.id == current?.id ? "проект этого разговора" : nil) { addToProject(pr, texts) }
                    }
                }
            }
            .frame(height: min(CGFloat(list.count) * 38, 260))
        }
    }

    private func createProject(_ texts: [Attachment]) {
        let pr = app.makeProject(name: projectName, kind: agent ? .agent : .chat)
        naming = false
        // новый разговор сразу в этом проекте
        chat.assignNewProject(pr.id)
        addToProject(pr, texts)
    }

    private func addToProject(_ pr: Project, _ texts: [Attachment]) {
        open = false
        if texts.isEmpty {
            DispatchQueue.main.async { app.addFiles(to: pr) }
        } else {
            var added = 0
            for a in texts where app.addFile(a.url, to: pr) { added += 1 }
            // что ушло в проект — из поля убираем: оно теперь там
            if added > 0 { attachments.removeAll { a in texts.contains { $0.id == a.id } } }
            app.updateProject(pr) { _ in }
        }
    }

    /// Файлы, что уже сделали Lumen и боты: выбрал — прикрепился к сообщению (тот же файл, без копии)
    @ViewBuilder private var artifactsPage: some View {
        Back(title: "Артефакты") { page = .main }
        let items = ((try? app.store.artifacts(limit: 200)) ?? []).flatMap { row in row.message.attachments.map { ($0, row.title) } }
        if items.isEmpty {
            Text("Пока ни одного: файлы, что делают Lumen и боты, появятся здесь.")
                .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.vertical, 6)
        }
        if !items.isEmpty {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.prefix(60).enumerated()), id: \.offset) { _, it in
                    let (a, title) = it
                    let on = attachments.contains { $0.path == a.path }
                    Row(icon: a.kind == .image ? "image" : "file-text", title: a.name, note: "из «\(title)» · \(a.sizeText)") {
                        if on { attachments.removeAll { $0.path == a.path } } else { attachments.append(a) }
                    }
                    .overlay(alignment: .trailing) { if on { Icon("check", 14).foregroundStyle(p.glow).padding(.trailing, 10) } }
                }
            }
        }
        .frame(height: min(CGFloat(min(items.count, 60)) * 42, 340))
        }
    }

    @ViewBuilder private var skillsPage: some View {
        Back(title: "Навыки") { page = .main }
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(skills) { s in
                    Row(icon: "book-open", title: s.name, note: s.description) {
                        draft = "Возьми навык «\(s.name)»: " + draft
                        open = false
                    }
                }
            }
        }
        .frame(height: min(CGFloat(skills.count) * 42, 320))
    }

    @ViewBuilder private var connectorsPage: some View {
        Back(title: "Коннекторы") { page = .main }
        if app.connectors.mcpServers.isEmpty {
            Text("Пока ни одного. Подключи сайт или программу — Lumen сможет ими пользоваться.")
                .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.vertical, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(app.connectors.mcpServers.keys.sorted(), id: \.self) { name in
            let s = app.connectors.mcpServers[name]!
            HStack(spacing: 10) {
                Icon(s.isRemote ? "globe" : "terminal", 15).foregroundStyle(p.mutedFg).frame(width: 18)
                Text(name).font(.geist(13.5)).lineLimit(1)
                Spacer()
                LSwitch(isOn: Binding(get: { !s.disabled }, set: { app.setConnector(name, enabled: $0) }))
            }
            .padding(.horizontal, 10).frame(height: 36)
        }
        p.border.frame(height: 1).padding(.vertical, 4)
        Row(icon: "settings", title: "Управлять коннекторами") {
            open = false
            app.customizeTab = .connectors
            app.page = .skills
        }
    }

    @ViewBuilder private var botsPage: some View {
        Back(title: "Позвать бота") { page = .main }
        ForEach(app.bots) { b in
            Button {
                draft = "@\(b.id) " + draft
                open = false
            } label: {
                HStack(spacing: 10) {
                    BotAvatar(bot: b, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.name).font(.geist(13.5))
                        Text("@\(b.id)").font(.geist(11)).foregroundStyle(BotColor.accent(b.hue))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle())
        }
    }

    private func addFiles() {
        open = false
        attachments += app.chooseAttachments()
    }

    // MARK: строки

    private struct Row: View {
        let icon: String
        let title: String
        var note: String? = nil
        var trailing: String? = nil
        var chevron = false
        /// Действие «создать»: значок и название в цвете акцента
        var accent = false
        let action: () -> Void

        @Environment(\.palette) private var p

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Icon(icon, 15).foregroundStyle(accent ? p.glow : p.foreground.opacity(0.85)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.geist(13, accent ? .medium : .regular)).foregroundStyle(accent ? p.glow : p.foreground)
                            .lineLimit(1).truncationMode(.middle)
                        if let note { Text(note).font(.geist(11.5)).foregroundStyle(p.mutedFg).lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    if let trailing { Text(trailing).font(.geist(12)).foregroundStyle(p.mutedFg) }
                    if chevron { Icon("chevron-right", 13).foregroundStyle(p.mutedFg) }
                }
                .padding(.horizontal, 8).padding(.vertical, note == nil ? 0 : 4).frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle())
        }
    }

    /// Подпись над списком в подменю
    private struct Section: View {
        let title: String
        @Environment(\.palette) private var p
        var body: some View {
            Text(title).font(.geist(11.5, .medium)).foregroundStyle(p.mutedFg)
                .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
        }
    }

    private struct ToggleRow: View {
        let icon: String
        let title: String
        @Binding var isOn: Bool
        @Environment(\.palette) private var p

        var body: some View {
            HStack(spacing: 10) {
                Icon(icon, 14).foregroundStyle(isOn ? p.glow : p.mutedFg).frame(width: 16)
                Text(title).font(.geist(12.5))
                Spacer(minLength: 8)
                LSwitch(isOn: $isOn)
            }
            .padding(.horizontal, 8).frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private struct Back: View {
        let title: String
        let action: () -> Void
        @Environment(\.palette) private var p

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Icon("chevron-right", 13).rotationEffect(.degrees(180)).foregroundStyle(p.mutedFg)
                    Text(title).font(.geist(13.5, .semibold)).foregroundStyle(p.foreground)
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Строка меню: подсветка при наведении
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    private struct MenuRowBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            configuration.label
                .foregroundStyle(p.foreground)
                .background(hover || configuration.isPressed ? p.muted.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .onHover { hover = $0 }
        }
    }
}

/// Что добавлено в это сообщение из GitHub: репозиторий, папка (агенту) и вложения (чату)
struct GitHubAdded: Identifiable, Equatable {
    let slug: String
    let folder: URL
    let attachmentIDs: [String]
    var id: String { slug }
}

/// Таблетки у «+»: только то, что включено в это сообщение (Рома, 22.10) — «Ресерч». Репозиторий GitHub — карточкой
/// среди вложений, не таблеткой (26.10). Поиск в сети и память по умолчанию включены и живут только в меню «+»
struct ToolPills: View {
    @Binding var research: Bool

    var body: some View {
        HStack(spacing: 6) {
            if research {
                ToolPill(icon: "flask-conical", title: "Ресерч", on: true, help: "Глубокое исследование на это сообщение — нажми, чтобы убрать") {
                    research = false
                }
            }
        }
    }
}

private struct ToolPill: View {
    let icon: String
    let title: String
    let on: Bool
    let help: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(icon, 13)
                Text(title).font(.geist(12.5))
            }
            .foregroundStyle(on ? p.accentSoft : (hover ? p.foreground : p.mutedFg))
            .padding(.horizontal, 10).frame(height: 28)
            .background(on ? p.accentTint : (hover ? p.hover : p.borderBase.opacity(0.04)), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? p.glow.opacity(0.28) : p.borderBase.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "включено" : "выключено")
        .accessibilityAddTraits(.isButton)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}
