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
    @Binding var draft: String
    @Binding var attachments: [Attachment]

    @Environment(\.palette) private var p
    @State private var open = false
    @State private var page: Page = .main
    @State private var hover = false

    enum Page { case main, skills, connectors, bots, artifacts }

    private var skills: [Skill] { app.skills.filter(\.info.enabled) }
    private var botsHere: Bool { !agent && app.chat.conversation?.kind != .bot && !app.bots.isEmpty }

    var body: some View {
        Button { page = .main; open.toggle() } label: {
            Icon("plus", 14).foregroundStyle(hover || open ? p.foreground : p.mutedFg)
                .frame(width: 26, height: 26)
                .background(hover || open ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Добавить")
        .background {
            // ⌘U — сразу файлы, без меню
            Button("") { addFiles() }.keyboardShortcut("u", modifiers: .command).opacity(0).allowsHitTesting(false)
        }
        // меню открывается сбоку от «+», а не над ним по центру
        .popover(isPresented: $open, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 2) {
                switch page {
                case .main: main
                case .skills: skillsPage
                case .connectors: connectorsPage
                case .bots: botsPage
                case .artifacts: artifactsPage
                }
            }
            .padding(4)
            .frame(width: 232)
            .background(p.popover)
            .environment(\.palette, p)
            .preferredColorScheme(p.scheme)
            .animation(.easeOut(duration: 0.12), value: page)
        }
    }

    @ViewBuilder private var main: some View {
        Row(icon: "paperclip", title: "Добавить файлы или фото", trailing: "⌘U") { addFiles() }
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
    }

    /// Файлы, что уже сделали Lumen и боты: выбрал — прикрепился к сообщению (тот же файл, без копии)
    @ViewBuilder private var artifactsPage: some View {
        Back(title: "Артефакты") { page = .main }
        let items = ((try? app.store.artifacts(limit: 200)) ?? []).flatMap { row in row.message.attachments.map { ($0, row.title) } }
        if items.isEmpty {
            Text("Пока ни одного: файлы, что делают Lumen и боты, появятся здесь.")
                .font(.geist(12)).foregroundStyle(p.mutedFg).padding(.horizontal, 10).padding(.vertical, 6)
        }
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
        .frame(maxHeight: 340)
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
        .frame(maxHeight: 320)
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
        let action: () -> Void

        @Environment(\.palette) private var p

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Icon(icon, 14).foregroundStyle(p.foreground.opacity(0.85)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.geist(12.5)).lineLimit(1)
                        if let note { Text(note).font(.geist(11)).foregroundStyle(p.mutedFg).lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    if let trailing { Text(trailing).font(.geist(12)).foregroundStyle(p.mutedFg) }
                    if chevron { Icon("chevron-right", 13).foregroundStyle(p.mutedFg) }
                }
                .padding(.horizontal, 8).frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle())
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
                    Text(title).font(.geist(12, .medium)).foregroundStyle(p.mutedFg)
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
