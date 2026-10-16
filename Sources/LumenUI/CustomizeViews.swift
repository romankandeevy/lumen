import AppKit
import LumenCore
import LumenProviders
import SwiftUI

// Кастомизация → «Коннекторы» и «Хуки» (навыки — SkillViews.swift). Как в Claude Code, только удобнее:
// коннектор можно вставить чем угодно (JSON из README, `claude mcp add …`, адрес, команда), поставить готовый
// или найти в реестре MCP; хук — выбрать из готовых, а свой проверить кнопкой до сохранения.

// MARK: коннекторы

struct ConnectorsTab: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var paste = ""
    @State private var pasteNote: String?
    @State private var editing: ConnectorEdit?
    @State private var open: String?
    @State private var query = ""
    @State private var found: [MCPRegistry.Entry] = []
    @State private var searching = false
    @State private var searchNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pasteBox
                if !app.connectors.mcpServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        GroupTitle(text: "Подключены")
                        ForEach(app.connectors.mcpServers.keys.sorted(), id: \.self) { name in
                            ConnectorRow(app: app, name: name, open: $open) { editing = ConnectorEdit(name: name, server: app.connectors.mcpServers[name]!) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    GroupTitle(text: "Готовые")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                        ForEach(ConnectorPreset.popular) { preset in
                            PresetCard(app: app, preset: preset) { open = $0 }
                        }
                    }
                }
                registry
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { e in
            ConnectorEditor(app: app, edit: e) { editing = nil }
        }
    }

    /// Вставить что угодно — Lumen поймёт сам
    private var pasteBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField(text: $paste, axis: .vertical) {
                    Text("Вставь, что дали: JSON из README, «claude mcp add …», адрес сайта или команду «npx …»")
                        .foregroundStyle(p.mutedFg.opacity(0.7))
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...8)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                .onSubmit(addPasted)
                LButton(title: "Добавить", icon: "plus", kind: .primary, small: true) { addPasted() }
                    .disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 4)
                LButton(title: "Вручную", kind: .outline, small: true) {
                    editing = ConnectorEdit(name: "", server: MCPServer())
                }
                .padding(.top, 4)
            }
            if let pasteNote {
                Text(pasteNote).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
        }
    }

    private func addPasted() {
        let found = ConnectorImport.parse(paste)
        guard !found.isEmpty else {
            pasteNote = "Не понял, что это. Подходит JSON с «mcpServers», команда «claude mcp add …», адрес https://… или команда запуска."
            return
        }
        if found.count == 1 {
            // один — сразу в редактор: проверить имя и вписать токены
            editing = ConnectorEdit(name: app.freeConnectorName(found[0].name), server: found[0].server)
            pasteNote = nil
        } else {
            var names: [String] = []
            for f in found {
                let n = app.saveConnector(f.server, name: app.freeConnectorName(f.name))
                names.append(n)
                app.checkConnector(n)
            }
            pasteNote = "Добавлены: " + names.joined(separator: ", ")
        }
        paste = ""
    }

    private var registry: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupTitle(text: "Найти в реестре MCP")
            HStack(spacing: 8) {
                GlowField(placeholder: "Например: notion, postgres, figma, telegram", text: $query, mono: true) { search() }
                LButton(title: "Найти", icon: "search", kind: .outline, small: true, busy: searching) { search() }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            if let searchNote { Text(searchNote).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
            ForEach(found) { e in
                RegistryRow(entry: e, installed: app.connectors.mcpServers.values.contains { $0.summary == e.server.summary }) {
                    editing = ConnectorEdit(name: app.freeConnectorName(e.shortName), server: e.server,
                                            asks: e.asks.map { ($0.key, $0.hint) })
                }
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        searchNote = nil
        Task {
            do {
                let uvx = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/uvx")
                    || FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/.local/bin/uvx")
                found = try await MCPRegistry.search(q, session: app.urlSession, uvx: uvx)
                if found.isEmpty { searchNote = "Ничего не нашлось. Попробуй по-английски или другим словом." }
            } catch {
                found = []
                searchNote = "Реестр MCP не ответил. Проверь интернет и попробуй ещё раз."
            }
            searching = false
        }
    }
}

/// Что сейчас правим в редакторе
struct ConnectorEdit: Identifiable {
    let id = UUID()
    var name: String
    var server: MCPServer
    /// Подсказки для секретов: ИМЯ → где взять
    var asks: [(String, String)] = []
    /// Было это имя (переименование)
    var original: String?

    init(name: String, server: MCPServer, asks: [(String, String)] = []) {
        self.name = name
        self.server = server
        self.asks = asks
        self.original = name.isEmpty ? nil : name
    }
}

private struct ConnectorRow: View {
    @Bindable var app: AppModel
    let name: String
    @Binding var open: String?
    let edit: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        let s = app.connectors.mcpServers[name] ?? MCPServer()
        let missing = app.missingSecrets(s)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Icon(s.isRemote ? "globe" : "terminal", 16)
                    .foregroundStyle(s.disabled ? p.mutedFg : p.glow).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name).tw(14, .medium, lh: 20)
                        status(s, missing: missing)
                    }
                    Text(s.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg)
                        .lineLimit(1).truncationMode(.middle)
                    if !s.note.isEmpty {
                        Text(s.note).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                LSwitch(isOn: Binding(get: { !s.disabled }, set: { app.setConnector(name, enabled: $0) }))
                    .help(s.disabled ? "Выключен — модели его не видят" : "Lumen и агент его видят; ботам — по выбору в боте")
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                open = open == name ? nil : name
                if open == name, app.connectorStatus[name] == nil { app.checkConnector(name) }
            }
            if open == name { details(s, missing: missing) }
        }
        .background(hover ? p.card.opacity(0.7) : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .onHover { hover = $0 }
        .onRightClick { point in
            app.menu = MenuState(items: [
                MenuItem(title: "Проверить", key: "c") { open = name; app.checkConnector(name) },
                MenuItem(title: "Изменить", key: "e") { edit() },
                MenuItem(title: s.disabled ? "Включить" : "Выключить", key: "t") { app.setConnector(name, enabled: s.disabled) },
                MenuItem(title: "Удалить", key: "d", destructive: true, separated: true) { app.removeConnector(name) },
            ], anchor: point)
        }
    }

    @ViewBuilder private func status(_ s: MCPServer, missing: [String]) -> some View {
        if !missing.isEmpty {
            chip("нужен \(missing.joined(separator: ", "))", color: Palette.destructive)
        } else {
            switch app.connectorStatus[name] {
            case .checking: chip("проверяю…", color: p.mutedFg)
            case .ok(let tools): chip("\(tools.count) " + Plural.form(tools.count, "инструмент", "инструмента", "инструментов"), color: p.glow)
            case .failed: chip("не отвечает", color: Palette.destructive)
            case .needsLogin: chip("нужно войти", color: p.glow)
            case nil: EmptyView()
            }
        }
    }

    private func chip(_ t: String, color: Color) -> some View {
        Text(t).tw(11, lh: 14).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: R.md))
    }

    @ViewBuilder private func details(_ s: MCPServer, missing: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(p.border).frame(height: 1)
            switch app.connectorStatus[name] {
            case .checking:
                IconLabel(text: s.isRemote ? "Подключаюсь к сайту…" : "Запускаю — первый раз npx скачивает пакет, бывает до минуты…", icon: "loader-circle", size: 13)
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            case .ok(let tools):
                Text("Что умеет").tw(11, .medium, lh: 14).foregroundStyle(p.mutedFg)
                FlowWrap(spacing: 6) {
                    ForEach(tools, id: \.name) { t in
                        Text(t.name).font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.md))
                            .help(t.description)
                    }
                }
            case .failed(let why):
                IconLabel(text: why, icon: "triangle-alert", size: 13).tw(12, lh: 16).foregroundStyle(Palette.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsLogin:
                HStack(spacing: 10) {
                    Text("Сайт просит войти. Откроется браузер — войди и разреши доступ, Lumen запомнит.")
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    LButton(title: "Войти через браузер", icon: "globe", kind: .primary, small: true) {
                        Task { await app.loginSaved(name) }
                    }
                    .fixedSize()
                }
            case nil:
                EmptyView()
            }
            if !missing.isEmpty {
                Text("Впиши \(missing.joined(separator: ", ")) в «Изменить» — значение уйдёт в Связку ключей.")
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            let bots = app.bots.filter { $0.connectors.contains(name) }
            Text(bots.isEmpty ? "Видят: Lumen и агент. Ботам — включи в настройках бота."
                 : "Видят: Lumen, агент и " + bots.map { "@\($0.id)" }.joined(separator: ", "))
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            HStack(spacing: 8) {
                LButton(title: "Проверить", icon: "refresh-cw", kind: .outline, small: true, busy: app.connectorStatus[name] == .checking) {
                    app.checkConnector(name)
                }
                LButton(title: "Изменить", icon: "pencil", kind: .outline, small: true, action: edit)
                Spacer()
                LButton(title: "Удалить", icon: "trash", kind: .ghost, small: true) { app.removeConnector(name) }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
    }
}

private struct PresetCard: View {
    @Bindable var app: AppModel
    let preset: ConnectorPreset
    let opened: (String) -> Void

    @Environment(\.palette) private var p
    @State private var values: [String: String] = [:]
    @State private var asking = false

    var body: some View {
        let installed = app.connectors.mcpServers[preset.name] != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Icon(preset.icon, 16).foregroundStyle(p.glow)
                    .frame(width: 32, height: 32)
                    .background(p.glow.opacity(0.08), in: RoundedRectangle(cornerRadius: R.md))
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.title).tw(13, .medium, lh: 18)
                    Text(preset.server.isRemote ? "сайт" : "программа").tw(11, lh: 14).foregroundStyle(p.mutedFg)
                }
                Spacer(minLength: 0)
                if installed {
                    IconLabel(text: "подключён", icon: "check", size: 12).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                } else {
                    LButton(title: "Подключить", kind: .outline, small: true) { start() }.fixedSize()
                }
            }
            Text(preset.note).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if asking {
                ForEach(preset.asks, id: \.key) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        GlowField(placeholder: a.key, text: Binding(get: { values[a.key] ?? "" }, set: { values[a.key] = $0 }),
                                  secure: true, mono: true) { finish() }
                        Text(a.hint).tw(11, lh: 14).foregroundStyle(p.mutedFg)
                    }
                }
                HStack {
                    LButton(title: "Сохранить", kind: .primary, small: true) { finish() }
                        .disabled(preset.asks.contains { (values[$0.key] ?? "").isEmpty })
                    LButton(title: "Отмена", kind: .ghost, small: true) { asking = false }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }

    private func start() {
        if !preset.asks.isEmpty, preset.asks.contains(where: { app.secret($0.key) == nil }) { asking = true; return }
        finish()
    }

    private func finish() {
        var s = preset.server
        s.note = preset.note
        if preset.needsFolder {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "Дать доступ"
            panel.message = "Папка, с которой будет работать коннектор"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            s.args = s.args.map { $0 == "{folder}" ? url.path : $0 }
        }
        for (k, v) in values where !v.isEmpty { app.setSecret(k, v) }
        let name = app.saveConnector(s, name: app.freeConnectorName(preset.name))
        asking = false
        app.checkConnector(name)
        opened(name)
    }
}

private struct RegistryRow: View {
    let entry: MCPRegistry.Entry
    let installed: Bool
    let add: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(entry.server.isRemote ? "globe" : "terminal", 16).foregroundStyle(p.mutedFg).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).tw(13, .medium, lh: 18)
                Text(entry.name).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg).lineLimit(1)
                if !entry.description.isEmpty {
                    Text(entry.description).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(2)
                }
                if !entry.asks.isEmpty {
                    Text("Нужно: " + entry.asks.map(\.key).joined(separator: ", ")).tw(11, lh: 14).foregroundStyle(p.mutedFg.opacity(0.8))
                }
            }
            Spacer(minLength: 12)
            if installed {
                IconLabel(text: "подключён", icon: "check", size: 12).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            } else {
                LButton(title: "Подключить", kind: .outline, small: true, action: add).opacity(hover ? 1 : 0.85)
            }
        }
        .padding(12)
        .background(hover ? p.card.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
        .onHover { hover = $0 }
    }
}

/// Редактор коннектора: имя, команда или адрес, переменные и заголовки, проверка до сохранения
struct ConnectorEditor: View {
    @Bindable var app: AppModel
    let edit: ConnectorEdit
    let close: () -> Void

    @Environment(\.palette) private var p
    @State private var name = ""
    @State private var remote = false
    @State private var command = ""
    @State private var url = ""
    @State private var envText = ""
    @State private var headerText = ""
    @State private var secrets: [String: String] = [:]
    @State private var probing = false
    @State private var probe: ConnectorStatus?
    @State private var oauth = false
    @State private var loggingIn = false
    /// Под каким именем сохранится (для нового — свободное); токен входа хранится под ним
    @State private var finalName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(edit.original == nil ? "Новый коннектор" : "Коннектор «\(edit.original!)»").tw(18, .semibold, lh: 24)
            field("Имя", aside: "так его видит модель: mcp__\(MCPServer.cleanName(name).isEmpty ? "имя" : MCPServer.cleanName(name))__…") {
                GlowField(placeholder: "github", text: $name, mono: true)
            }
            field("Что это") {
                Segmented(value: $remote, options: [(false, "Программа на Маке"), (true, "Сайт (адрес MCP)")])
            }
            if remote {
                field("Адрес") { GlowField(placeholder: "https://example.com/mcp", text: $url, mono: true) }
                field("Заголовки", aside: "по строке «Имя: значение»; значения уходят в Связку ключей") {
                    box($headerText, placeholder: "Authorization: Bearer …")
                }
            } else {
                field("Команда", aside: "как в терминале") { GlowField(placeholder: "npx -y @modelcontextprotocol/server-memory", text: $command, mono: true) }
                field("Переменные", aside: "по строке ИМЯ=значение; токены и ключи уходят в Связку ключей") {
                    box($envText, placeholder: "API_KEY=…")
                }
            }
            let need = pending.placeholders.filter { app.secret($0) == nil }
            if !need.isEmpty {
                field("Секреты", aside: "хранятся в Связке ключей, в файл не попадают") {
                    VStack(spacing: 6) {
                        ForEach(need, id: \.self) { k in
                            GlowField(placeholder: k, text: Binding(get: { secrets[k] ?? "" }, set: { secrets[k] = $0 }), secure: true, mono: true)
                            if let hint = edit.asks.first(where: { $0.0 == k })?.1, !hint.isEmpty {
                                Text(hint).tw(11, lh: 14).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            switch probe {
            case .checking:
                IconLabel(text: "Проверяю…", icon: "loader-circle", size: 13).tw(12, lh: 16).foregroundStyle(p.mutedFg)
            case .ok(let tools):
                IconLabel(text: "Работает: " + tools.prefix(8).map(\.name).joined(separator: ", ") + (tools.count > 8 ? " и ещё \(tools.count - 8)" : ""),
                          icon: "circle-check", size: 13).tw(12, lh: 16).foregroundStyle(p.glow)
            case .failed(let why):
                IconLabel(text: why, icon: "triangle-alert", size: 13).tw(12, lh: 16).foregroundStyle(Palette.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsLogin:
                HStack(spacing: 10) {
                    Text(loggingIn ? "Жду вход в браузере…" : "Сайт просит войти. Откроется браузер — войди и разреши доступ.")
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    LButton(title: "Войти через браузер", icon: "globe", kind: .primary, small: true, busy: loggingIn) { login() }
                        .fixedSize()
                        .disabled(loggingIn)
                }
            case nil: EmptyView()
            }
            HStack(spacing: 8) {
                LButton(title: "Проверить", icon: "refresh-cw", kind: .outline, small: true, busy: probing) { check() }
                    .disabled(!valid || probing)
                Spacer()
                LButton(title: "Отмена", kind: .ghost, small: true, action: close)
                LButton(title: "Сохранить", kind: .primary, small: true) { save() }.disabled(!valid)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(p.background)
        .onAppear(perform: load)
    }

    private var valid: Bool {
        !MCPServer.cleanName(name).isEmpty && MCPServer.cleanName(name) != "lumen"
            && (remote ? URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
                       : !command.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Что получится из полей
    private var pending: MCPServer {
        var s = edit.server
        s.type = remote ? (edit.server.type == .sse ? .sse : .http) : .stdio
        if remote {
            s.url = url.trimmingCharacters(in: .whitespaces)
            s.headers = Self.pairs(headerText, sep: ":")
            s.oauth = oauth
            s.command = ""; s.args = []; s.env = [:]
        } else {
            let words = ConnectorImport.shellWords(command)
            s.command = words.first ?? ""
            s.args = Array(words.dropFirst())
            s.env = Self.pairs(envText, sep: "=")
            s.url = ""; s.headers = [:]
        }
        return s
    }

    private func load() {
        name = edit.name
        let s = edit.server
        remote = s.isRemote
        url = s.url
        command = s.command.isEmpty ? "" : s.summary
        envText = s.env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        headerText = s.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        oauth = s.oauth
        // из реестра или вставки — сразу проверить: сайт сам скажет, нужен ли вход
        if edit.original == nil || app.connectorStatus[edit.name] == nil, valid { check() }
    }

    private var targetName: String {
        let clean = MCPServer.cleanName(name)
        return edit.original == clean ? clean : app.freeConnectorName(clean)
    }

    private func login() {
        loggingIn = true
        finalName = targetName
        Task {
            do {
                let s = try await app.loginConnector(finalName, server: pending)
                oauth = true
                headerText = s.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                loggingIn = false
                check()
            } catch {
                loggingIn = false
                probe = .failed((error as? MCPClient.Failure)?.message ?? error.localizedDescription)
            }
        }
    }

    private func check() {
        probing = true
        probe = .checking
        var values = app.secretValues(for: [pending])
        for (k, v) in secrets where !v.isEmpty { values[k] = v }
        let server = pending.resolved(values)
        let session = app.urlSession
        Task {
            switch await MCPClient.probe(server, session: session) {
            case .success(let tools): probe = .ok(tools)
            case .failure(let f) where f.needsAuth: probe = .needsLogin
            case .failure(let f): probe = .failed(f.message)
            }
            probing = false
        }
    }

    private func save() {
        for (k, v) in secrets where !v.isEmpty { app.setSecret(k, v) }
        // вошли через браузер — имя то же, под которым лежит токен
        let n = app.saveConnector(pending, name: oauth && !finalName.isEmpty ? finalName : targetName, replacing: edit.original)
        if case .ok = probe { app.connectorStatus[n] = probe } else { app.checkConnector(n) }
        close()
    }

    static func pairs(_ text: String, sep: Character) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: sep, maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if let k = kv.first, !k.isEmpty { out[k] = kv.count > 1 ? kv[1] : "" }
        }
        return out
    }

    private func field<C: View>(_ title: String, aside: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).tw(12, .medium, lh: 16)
                if let aside { Text(aside).tw(11, lh: 14).foregroundStyle(p.mutedFg) }
            }
            content()
        }
    }

    private func box(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(text: text, axis: .vertical) { Text(placeholder).foregroundStyle(p.mutedFg.opacity(0.7)) }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(2...6)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
}

// MARK: хуки

struct HooksTab: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var editing: HookRule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Text("Хук — команда, которую Claude Code запускает сам в нужный момент: перед инструментом, после ответа, при уведомлении. Работает в чате по подписке, у агента и у ботов.")
                        .tw(13, lh: 18).foregroundStyle(p.mutedFg).frame(maxWidth: 640, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    LButton(title: "Новый хук", icon: "plus", kind: .primary, small: true) { editing = Self.blank() }
                }
                if !app.hooks.isEmpty {
                    ForEach(HookEvent.allCases) { e in
                        let rules = app.hooks.filter { $0.event == e }
                        if !rules.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                GroupTitle(text: e.title)
                                ForEach(rules) { r in HookRow(app: app, rule: r) { editing = r } }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    GroupTitle(text: "Готовые")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                        ForEach(HookTemplate.all) { t in
                            let added = app.hooks.contains { $0.command == t.rule.command }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(t.name).tw(13, .medium, lh: 18).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    if added {
                                        IconLabel(text: "есть", icon: "check", size: 12).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                                    } else {
                                        LButton(title: "Добавить", kind: .outline, small: true) {
                                            app.hooks.append(HookRule(event: t.rule.event, matcher: t.rule.matcher, command: t.rule.command,
                                                                      timeout: t.rule.timeout, name: t.rule.name))
                                            app.saveHooks()
                                        }
                                        .fixedSize()
                                    }
                                }
                                Text(t.note).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                                Text(t.rule.event.title + (t.rule.matcher.isEmpty ? "" : " · \(t.rule.matcher)"))
                                    .tw(11, lh: 14).foregroundStyle(p.mutedFg.opacity(0.8))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
                            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { r in
            HookEditor(app: app, rule: r) { editing = nil }
        }
    }

    /// Новый хук (кнопка в шапке страницы)
    static func blank() -> HookRule { HookRule(event: .stop, command: "") }
}

private struct HookRow: View {
    @Bindable var app: AppModel
    let rule: HookRule
    let edit: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon("zap", 16).foregroundStyle(rule.enabled ? p.glow : p.mutedFg).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rule.name.isEmpty ? "Хук" : rule.name).tw(14, .medium, lh: 20)
                    if rule.event.hasMatcher {
                        Text(rule.matcher.isEmpty ? "любой инструмент" : rule.matcher).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.mutedFg)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.md))
                    }
                }
                Text(rule.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg)
                    .lineLimit(2).truncationMode(.tail)
            }
            Spacer(minLength: 12)
            LSwitch(isOn: Binding(get: { rule.enabled }, set: { on in
                if let i = app.hooks.firstIndex(where: { $0.id == rule.id }) { app.hooks[i].enabled = on; app.saveHooks() }
            }))
        }
        .padding(14)
        .background(hover ? p.card.opacity(0.7) : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .onHover { hover = $0 }
        .onRightClick { point in
            app.menu = MenuState(items: [
                MenuItem(title: "Изменить", key: "e", action: edit),
                MenuItem(title: rule.enabled ? "Выключить" : "Включить", key: "t") {
                    if let i = app.hooks.firstIndex(where: { $0.id == rule.id }) { app.hooks[i].enabled.toggle(); app.saveHooks() }
                },
                MenuItem(title: "Удалить", key: "d", destructive: true, separated: true) {
                    app.hooks.removeAll { $0.id == rule.id }
                    app.saveHooks()
                },
            ], anchor: point)
        }
    }
}

private struct HookEditor: View {
    @Bindable var app: AppModel
    let rule: HookRule
    let close: () -> Void

    @Environment(\.palette) private var p
    @State private var draft = HookRule(event: .stop, command: "")
    @State private var testing = false
    @State private var result: (code: Int32, output: String)?

    var body: some View {
        let isNew = !app.hooks.contains { $0.id == rule.id }
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Новый хук" : "Хук").tw(18, .semibold, lh: 24)
            field("Название") { GlowField(placeholder: "Например: звук по окончании", text: $draft.name) }
            field("Когда", aside: draft.event.note) {
                Picker("", selection: $draft.event) {
                    ForEach(HookEvent.allCases) { e in Text(e.title).tag(e) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)
            }
            if draft.event.hasMatcher {
                field("Какой инструмент", aside: "Bash, Edit|Write, mcp__github__.* — пусто: любой") {
                    GlowField(placeholder: "Bash", text: $draft.matcher, mono: true)
                }
            }
            field("Команда", aside: "запускается в sh; на вход — JSON о событии (tool_name, tool_input, prompt…)") {
                TextField(text: $draft.command, axis: .vertical) { Text("afplay /System/Library/Sounds/Glass.aiff").foregroundStyle(p.mutedFg.opacity(0.7)) }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3...10)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            }
            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.code == 0 ? "Код 0 — пропустит" : result.code == 2 ? "Код 2 — остановит действие" : "Код \(result.code) — ошибка, Claude Code её покажет и продолжит")
                        .tw(12, .medium, lh: 16).foregroundStyle(result.code == 2 ? Palette.destructive : p.foreground)
                    if !result.output.isEmpty {
                        Text(result.output).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg).lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
            }
            HStack(spacing: 8) {
                LButton(title: "Проверить", icon: "zap", kind: .outline, small: true, busy: testing) {
                    testing = true
                    Task { result = await app.testHook(draft); testing = false }
                }
                .disabled(draft.command.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                .help("Запустить с примером события — ничего не сломает, если команда сама ничего не меняет")
                Spacer()
                if !isNew {
                    LButton(title: "Удалить", icon: "trash", kind: .ghost, small: true) {
                        app.hooks.removeAll { $0.id == rule.id }
                        app.saveHooks()
                        close()
                    }
                }
                LButton(title: "Отмена", kind: .ghost, small: true, action: close)
                LButton(title: "Сохранить", kind: .primary, small: true) {
                    var r = draft
                    if !r.event.hasMatcher { r.matcher = "" }
                    if let i = app.hooks.firstIndex(where: { $0.id == rule.id }) { app.hooks[i] = r } else { app.hooks.append(r) }
                    app.saveHooks()
                    close()
                }
                .disabled(draft.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(p.background)
        .onAppear { draft = rule }
    }

    private func field<C: View>(_ title: String, aside: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).tw(12, .medium, lh: 16)
            if let aside { Text(aside).tw(11, lh: 14).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true) }
            content()
        }
    }
}

// MARK: предложение Lumen под ответом

/// «Lumen предлагает коннектор / хук» — подключает человек одним нажатием
struct ProposalCard: View {
    let app: AppModel
    let message: ChatMessage
    let proposal: CustomizeProposal

    @Environment(\.palette) private var p
    @State private var showCode = false
    @State private var editing: ConnectorEdit?

    var body: some View {
        let isHook = proposal.kind == .hook
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Icon(isHook ? "zap" : (proposal.server?.isRemote == true ? "globe" : "terminal"), 14).foregroundStyle(p.glow)
                Text(isHook ? "Предлагаю хук «\(proposal.name)»" : "Предлагаю коннектор «\(proposal.name)»" + (proposal.script != nil ? " — свой, написал сам" : ""))
                    .tw(13, .medium, lh: 18)
            }
            if !proposal.why.isEmpty {
                Text(proposal.why).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(3)
            }
            Group {
                if let h = proposal.hook {
                    Text(h.event.title + (h.event.hasMatcher && !h.matcher.isEmpty ? " · \(h.matcher)" : "") + "\n" + h.command)
                } else if let s = proposal.server {
                    Text(s.summary)
                }
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.mutedFg).lineLimit(4).textSelection(.enabled)
            if let code = proposal.script {
                Button { showCode.toggle() } label: {
                    IconLabel(text: showCode ? "Скрыть код" : "Код сервера", icon: showCode ? "chevron-down" : "chevron-right", size: 12)
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
                .buttonStyle(.plain)
                if showCode {
                    ScrollView {
                        Text(code).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(8)
                    .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
                }
            }
            switch proposal.state {
            case .pending:
                HStack(spacing: 8) {
                    LButton(title: isHook ? "Добавить" : "Подключить", icon: "check", kind: .outline, small: true) { accept() }
                    if !isHook, proposal.script == nil, let s = proposal.server {
                        LButton(title: "Посмотреть", kind: .ghost, small: true) {
                            editing = ConnectorEdit(name: app.freeConnectorName(proposal.name), server: s)
                        }
                    }
                    LButton(title: "Не надо", kind: .ghost, small: true) { app.setProposal(proposal.id, .declined, in: message) }
                }
            case .accepted:
                HStack(spacing: 8) {
                    Text(isHook ? "Добавлен — работает со следующего ответа." : "Подключён — работает со следующего сообщения.")
                        .tw(12, lh: 16).foregroundStyle(p.mutedFg)
                    if !isHook, case .needsLogin = app.connectorStatus[proposal.name] {
                        LButton(title: "Войти через браузер", icon: "globe", kind: .primary, small: true) {
                            Task { await app.loginSaved(proposal.name) }
                        }
                    }
                    LButton(title: "Кастомизация", kind: .ghost, small: true) {
                        app.customizeTab = isHook ? .hooks : .connectors
                        app.page = .skills
                    }
                }
            case .declined:
                Text("Не стали подключать.").tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(p.glow.opacity(0.05), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.25)))
        .sheet(item: $editing) { e in
            ConnectorEditor(app: app, edit: e) {
                editing = nil
                if app.connectors.mcpServers[e.name] != nil { app.setProposal(proposal.id, .accepted, in: message) }
            }
        }
    }

    private func accept() {
        app.acceptProposal(proposal, in: message)
    }
}
