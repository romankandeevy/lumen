import AppKit
import LumenCore
import SwiftUI

/// Плашка агента сверху страницы: кто и что делает, «Пауза» и «Стоп»; если человек сам тронул страницу — «Вернуть агенту».
/// Опасное действие (оплата, заказ, удаление) агент выполняет только после «Разрешить» в карточке
struct AgentBar: View {
    @Bindable var browser: BrowserModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 8) {
            if let a = browser.approval {
                ApprovalCard(approval: a) { browser.resolveApproval($0) }
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if browser.agentActive || browser.paused {
                bar.transition(.move(edge: .top).combined(with: .opacity))
            }
            if let n = browser.note {
                Text(n).tw(12, .medium, lh: 16).foregroundStyle(p.foreground)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(p.popover, in: Capsule())
                    .overlay(Capsule().strokeBorder(p.border))
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.page, value: browser.agentActive)
        .animation(Motion.page, value: browser.paused)
        .animation(Motion.page, value: browser.approval?.id)
        .animation(Motion.page, value: browser.note)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if browser.takeover {
                Icon("hand", 13).foregroundStyle(p.glow)
                Text("Вы управляете браузером").tw(12.5, .medium, lh: 16).lineLimit(1)
            } else if browser.paused {
                PauseGlyph().foregroundStyle(p.mutedFg)
                Text("На паузе").tw(12.5, .medium, lh: 16)
            } else {
                LiveDot(color: p.glow, size: 6)
                Text(browser.activity ?? "Работает в браузере").tw(12.5, .medium, lh: 16).lineLimit(1)
            }
            if browser.agentInBackground {
                AgentBarButton(label: "Смотреть", icon: "eye") { browser.watchAgent() }
            }
            p.border.frame(width: 1, height: 14)
            if browser.paused {
                AgentBarButton(label: browser.takeover ? "Вернуть агенту" : "Продолжить", icon: "play") { browser.resume() }
            } else {
                AgentBarButton(label: "Пауза", glyph: true) { browser.pause() }
            }
            AgentBarButton(label: "Стоп", icon: "square", danger: true) { browser.stop() }
        }
        .foregroundStyle(p.foreground)
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 32)
        .fixedSize()
        .background {
            Capsule().fill(p.popover)
                .overlay(Capsule().strokeBorder(browser.paused ? p.border : p.glow.opacity(0.35)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        }
    }
}

private struct PauseGlyph: View {
    var body: some View {
        HStack(spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 10)
            RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 10)
        }
        .frame(width: 13, height: 13)
    }
}

private struct AgentBarButton: View {
    let label: String
    var icon: String?
    var glyph = false
    var danger = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if glyph { PauseGlyph() } else if let icon { Icon(icon, 11) }
                Text(label).tw(12, .medium, lh: 16)
            }
            .foregroundStyle(hover ? (danger ? Color.red : p.foreground) : p.mutedFg)
            .padding(.horizontal, 8).frame(height: 24)
            .background(hover ? p.foreground.opacity(0.07) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label)
    }
}

struct ApprovalCard: View {
    let approval: BrowserModel.Approval
    let decide: (Bool) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Icon("shield-check", 18).foregroundStyle(p.glow).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(approval.title).tw(13.5, .semibold, lh: 18).foregroundStyle(p.foreground)
                    Text(approval.detail).tw(12.5, lh: 17).foregroundStyle(p.mutedFg)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                LButton(title: "Не разрешать", kind: .ghost, size: .xs) { decide(false) }
                LButton(title: "Разрешить", kind: .glow, size: .xs) { decide(true) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(p.popover, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.4)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }
}

/// Полоса прогресса загрузки: тонкая линия под вкладками
struct LoadBar: View {
    var loading: Bool
    var progress: Double
    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { g in
            Rectangle().fill(p.glow)
                .frame(width: g.size.width * max(0.08, min(1, progress)))
                .opacity(loading ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: progress)
                .animation(.easeOut(duration: 0.35), value: loading)
        }
        .frame(height: 2)
    }
}

/// «Найти на странице» ⌘F
struct FindBar: View {
    @Bindable var browser: BrowserModel
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Icon("search", 13).foregroundStyle(p.mutedFg)
            TextField("", text: $browser.findText, prompt: Text("Найти на странице").foregroundStyle(p.mutedFg.opacity(0.7)))
                .textFieldStyle(.plain).font(.geist(12.5)).focused($focused)
                .onSubmit { Task { await browser.find(forward: true) } }
                .onChange(of: browser.findText) { _, _ in Task { await browser.find(forward: true) } }
                .onExitCommand { browser.closeFind() }
            if browser.findMiss && !browser.findText.isEmpty {
                Text("Нет совпадений").tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            BrowserTool(icon: "chevron-up", help: "Назад", enabled: !browser.findText.isEmpty) { Task { await browser.find(forward: false) } }
            BrowserTool(icon: "chevron-down", help: "Дальше", enabled: !browser.findText.isEmpty) { Task { await browser.find(forward: true) } }
            BrowserTool(icon: "x", help: "Закрыть · Esc") { browser.closeFind() }
        }
        .padding(.leading, 12).padding(.trailing, 4).frame(height: 36)
        .background(p.card)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
        .onAppear { focused = true }
    }
}

/// «Сохранить вход для сайта?» — после того, как человек сам вошёл
struct SaveLoginBanner: View {
    @Bindable var browser: BrowserModel
    let login: CapturedLogin
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            Icon("key-round", 15).foregroundStyle(p.glow)
            VStack(alignment: .leading, spacing: 1) {
                Text(login.update ? "Обновить пароль для \(login.host)?" : "Сохранить вход для \(login.host)?").tw(12.5, .medium, lh: 16)
                Text("\(login.username) · пароль уйдёт в Связку ключей, агенту он не виден").tw(11.5, lh: 15).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 4)
            LButton(title: "Никогда", kind: .ghost, size: .xs) { browser.dismissPendingLogin(never: true) }
            LButton(title: "Не сейчас", kind: .ghost, size: .xs) { browser.dismissPendingLogin(never: false) }
            LButton(title: login.update ? "Обновить" : "Сохранить", kind: .glow, size: .xs) { browser.savePendingLogin() }
        }
        .foregroundStyle(p.foreground)
        .padding(.horizontal, 12).frame(height: 46)
        .background(p.card)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }
}

/// Сохранённые входы: список по сайтам, «Подставить» на этой странице, «Добавить вход»
struct LoginsPopover: View {
    var app: AppModel
    @Bindable var browser: BrowserModel
    var close: () -> Void
    @Environment(\.palette) private var p
    @State private var adding = false
    @State private var site = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var label = ""
    @State private var error: String?

    private var vault: BrowserVault { browser.vault }
    private var here: String { URL(string: browser.url)?.host.map(BrowserVault.normalize) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Icon("key-round", 14).foregroundStyle(p.glow)
                Text("Входы в аккаунты").tw(13.5, .semibold, lh: 18)
                Spacer()
            }
            Text("Пароли лежат в Связке ключей Мака. Агент видит только «есть вход для сайта» и просит Lumen войти — сам пароль ему не показывается.")
                .tw(11.5, lh: 16).foregroundStyle(p.mutedFg)
            if vault.logins.isEmpty && !adding {
                Text("Пока ничего не сохранено. Войди на сайте сам — Lumen предложит запомнить вход, или добавь вручную.")
                    .tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.vertical, 6)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(vault.logins) { l in row(l) }
                }
            }
            .frame(maxHeight: 220)
            if adding { addForm } else {
                HStack(spacing: 8) {
                    LButton(title: "Добавить вход", icon: "plus", kind: .outline, size: .xs) {
                        site = here
                        adding = true
                    }
                    Spacer()
                    Toggle("Подставлять сами", isOn: Binding(get: { app.prefs.browserAutoLogin }, set: { v in app.update { $0.browserAutoLogin = v } }))
                        .toggleStyle(.switch).controlSize(.mini).font(.geist(11.5)).foregroundStyle(p.mutedFg)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(p.popover)
        .environment(\.palette, p)
    }

    private func row(_ l: SavedLogin) -> some View {
        HStack(spacing: 8) {
            Circle().fill(BrowserVault.siteMatches(saved: l.host, page: here) ? p.glow : p.mutedFg.opacity(0.4)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(l.host).tw(12.5, .medium, lh: 16).lineLimit(1)
                Text(l.title).tw(11.5, lh: 15).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 4)
            if BrowserVault.siteMatches(saved: l.host, page: here) {
                LButton(title: "Подставить", kind: .ghost, size: .xs) {
                    Task { _ = await browser.fillForHuman(l); close() }
                }
            }
            Button { vault.setAutoSubmit(l.id, !l.autoSubmit) } label: {
                Text(l.autoSubmit ? "сам нажмёт" : "только вставит").tw(10.5, lh: 14).foregroundStyle(p.mutedFg)
                    .padding(.horizontal, 5).frame(height: 18)
                    .background(p.foreground.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Когда агент попадает на страницу входа: сам нажимает «Войти» или только вставляет данные")
            BrowserTool(icon: "trash", help: "Удалить вход") { vault.remove(l.id) }
        }
        .padding(.horizontal, 6).frame(minHeight: 34)
        .background(p.foreground.opacity(0.03), in: RoundedRectangle(cornerRadius: R.md))
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("Сайт (github.com)", text: $site)
            field("Логин или почта", text: $user)
            SecureField("", text: $pass, prompt: Text("Пароль").foregroundStyle(p.mutedFg.opacity(0.7)))
                .textFieldStyle(.plain).font(.geist(12.5)).padding(.horizontal, 8).frame(height: 28)
                .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
                .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
            field("Подпись, если входов несколько (необязательно)", text: $label)
            if let error { Text(error).tw(11.5, lh: 15).foregroundStyle(.red) }
            HStack(spacing: 8) {
                Spacer()
                LButton(title: "Отмена", kind: .ghost, size: .xs) { adding = false; pass = ""; error = nil }
                LButton(title: "Сохранить", kind: .glow, size: .xs) { save() }
                    .disabled(site.isEmpty || user.isEmpty || pass.isEmpty)
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(p.mutedFg.opacity(0.7)))
            .textFieldStyle(.plain).font(.geist(12.5)).padding(.horizontal, 8).frame(height: 28)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
    }

    private func save() {
        do {
            try vault.add(host: site, username: user, password: pass, label: label.trimmingCharacters(in: .whitespacesAndNewlines))
            adding = false
            site = ""; user = ""; pass = ""; label = ""; error = nil
            browser.say("Вход сохранён в Связку ключей")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// История: по дням, поиск, открыть или убрать
struct HistoryPopover: View {
    @Bindable var browser: BrowserModel
    var close: () -> Void
    @Environment(\.palette) private var p
    @State private var query = ""

    private var items: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = browser.history.recent(300)
        return q.isEmpty ? Array(all.prefix(60)) : all.filter { $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }.prefix(60).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("История").tw(13.5, .semibold, lh: 18)
                Spacer()
                if !browser.history.entries.isEmpty {
                    Button("Очистить") { browser.history.clear() }.buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
                }
            }
            HStack(spacing: 6) {
                Icon("search", 12).foregroundStyle(p.mutedFg)
                TextField("", text: $query, prompt: Text("Поиск по истории").foregroundStyle(p.mutedFg.opacity(0.7)))
                    .textFieldStyle(.plain).font(.geist(12.5))
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
            if items.isEmpty {
                Text(query.isEmpty ? "Здесь появятся страницы, на которых ты побывал" : "Ничего не нашлось").tw(12, lh: 16)
                    .foregroundStyle(p.mutedFg).padding(.vertical, 8)
            }
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(items) { e in
                        HStack(spacing: 8) {
                            SiteIcon(host: URL(string: e.url)?.host, revision: 0)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.title.isEmpty ? e.url : e.title).tw(12.5, .medium, lh: 16).lineLimit(1)
                                Text(BrowserPane.addressParts(e.url).head + BrowserPane.addressParts(e.url).tail).tw(11.5, lh: 15)
                                    .foregroundStyle(p.mutedFg).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(Self.time(e.visited)).tw(11, lh: 14).foregroundStyle(p.faint)
                        }
                        .padding(.horizontal, 6).frame(height: 36)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let u = URL(string: e.url) { browser.open(u) }
                            close()
                        }
                        .contextMenu { Button("Убрать из истории") { browser.history.remove(e.url) } }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(width: 380)
        .background(p.popover)
        .environment(\.palette, p)
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
        return f.string(from: d)
    }
}

/// Загрузки: что скачано, открыть или показать в Finder
struct DownloadsPopover: View {
    @Bindable var browser: BrowserModel
    var app: AppModel
    var close: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Загрузки").tw(13.5, .semibold, lh: 18)
                Spacer()
                Button("Очистить") { browser.clearDownloads() }.buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.mutedFg)
            }
            ForEach(browser.downloadItems) { d in
                HStack(spacing: 8) {
                    Icon(d.state == .failed ? "triangle-alert" : "file-down", 15).foregroundStyle(d.state == .failed ? Color.red : p.mutedFg)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.name).tw(12.5, .medium, lh: 16).lineLimit(1)
                        Text(d.state == .running ? "Скачивается…" : (d.state == .failed ? "Не вышло" : "В «Загрузках»")).tw(11.5, lh: 15).foregroundStyle(p.mutedFg)
                    }
                    Spacer(minLength: 4)
                    if d.state == .done, let u = d.url {
                        BrowserTool(icon: "eye", help: "Открыть сбоку") { app.openInBrowser(u); close() }
                        BrowserTool(icon: "folder-open", help: "Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    }
                }
                .padding(.horizontal, 6).frame(minHeight: 36)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(p.popover)
        .environment(\.palette, p)
    }
}

/// Значок сайта (16 pt): со страницы, а пока его нет — глобус
struct SiteIcon: View {
    let host: String?
    let revision: Int
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if let host, let img = FaviconCache.shared.image(for: host) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Icon("globe", 13).foregroundStyle(p.mutedFg)
            }
        }
        .frame(width: 14, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .id(revision)
    }
}

/// Подсказки под адресной строкой: история и сохранённые ссылки
struct AddressSuggestions: View {
    let items: [(title: String, url: String)]
    let selected: Int
    let pick: (String) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                HStack(spacing: 8) {
                    SiteIcon(host: URL(string: it.url)?.host, revision: 0)
                    Text(it.title.isEmpty ? it.url : it.title).tw(12.5, .medium, lh: 16).lineLimit(1)
                    Text(BrowserPane.addressParts(it.url).head + BrowserPane.addressParts(it.url).tail).tw(12, lh: 16)
                        .foregroundStyle(p.mutedFg).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(i == selected ? p.foreground.opacity(0.07) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { pick(it.url) }
            }
        }
        .padding(.vertical, 4)
        .background(p.popover, in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

/// Строка окошка «Отправить в чат»
struct SendRow: View {
    let kind: SendKind
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(kind.icon, 14).foregroundStyle(p.mutedFg).frame(width: 18)
                Text(kind.title).tw(13, lh: 18)
                Spacer(minLength: 0)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 8).frame(height: 32)
            .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: R.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
