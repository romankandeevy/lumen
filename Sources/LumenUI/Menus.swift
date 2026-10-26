import AppKit
import LumenCore
import SwiftUI

// Свои меню и поиск вместо системных окон macOS — как в Claude: тёмная панель, справа буква-клавиша.

/// Пункт меню. `key` — буква, которой его можно выбрать, пока меню открыто.
struct MenuItem: Identifiable {
    let id = UUID()
    var title: String
    var key: Character?
    var destructive = false
    /// Разделитель перед пунктом
    var separated = false
    /// Значок 20 слева; nil — подбирается по названию (`guessIcon`)
    var icon: String? = nil
    let action: () -> Void

    /// Значки пунктов по названию — одинаковые во всех меню (хендофф, 1.7.3)
    static func guessIcon(_ title: String) -> String? {
        let t = title.lowercased()
        if t.hasPrefix("закрепить") || t.hasPrefix("открепить") { return "pin" }
        if t.hasPrefix("переименовать") || t.hasPrefix("изменить") { return "pencil" }
        if t.hasPrefix("переместить в проект") { return "layers" }
        if t.hasPrefix("сделать навык") { return "sparkles" }
        if t.hasPrefix("удалить") { return "trash" }
        if t.hasPrefix("открыть") { return "external-link" }
        if t.hasPrefix("скопировать") { return "copy" }
        if t.hasPrefix("показать в finder") { return "folder-open" }
        if t.hasPrefix("проверить") { return "rotate-cw" }
        if t.hasPrefix("выключить") || t.hasPrefix("включить") { return "power" }
        if t.hasPrefix("новый проект") { return "plus" }
        if t.hasPrefix("убрать из проекта") { return "x" }
        return nil
    }
}

/// Открытое меню: что в нём и где (в координатах окна, от левого верхнего угла)
struct MenuState {
    var items: [MenuItem]
    var anchor: CGPoint
}

/// Слой поверх окна: меню у точки вызова, щелчок мимо — закрыть, буква — выбрать, Esc — закрыть
struct MenuLayer: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        if let menu = app.menu {
            GeometryReader { g in
                // меню не выходит за край окна; в замыкания — только числа
                let x = min(menu.anchor.x, g.size.width - 260)
                let y = menu.anchor.y
                let height = g.size.height
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001).onTapGesture { app.menu = nil }
                    panel(menu)
                        .fixedSize()
                        .alignmentGuide(.leading) { _ in -x }
                        .alignmentGuide(.top) { d in -min(y, height - d.height - 8) }
                }
            }
            .ignoresSafeArea()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.escape) { app.menu = nil; return .handled }
            .onKeyPress { press in
                guard let ch = press.characters.lowercased().first,
                      let item = menu.items.first(where: { $0.key.map { Character($0.lowercased()) } == ch }) else { return .ignored }
                app.menu = nil
                item.action()
                return .handled
            }
        }
    }

    private func panel(_ menu: MenuState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(menu.items) { item in
                if item.separated { p.border.frame(height: 1).padding(.vertical, 4).padding(.horizontal, 10) }
                MenuRow(item: item) {
                    app.menu = nil
                    item.action()
                }
            }
        }
        .padding(6)
        .frame(minWidth: 240)
        .popoverChrome()
    }
}

private struct MenuRow: View {
    let item: MenuItem
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        // пункт меню хендоффа: h28, по бокам 10, значок 20, буква-клавиша справа 12 тусклым
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = item.icon ?? MenuItem.guessIcon(item.title) {
                    Icon(icon, 20).foregroundStyle(item.destructive ? Palette.destructive : p.mutedFg)
                }
                Text(item.title).font(.geist(14, .medium)).lineLimit(1)
                Spacer(minLength: 24)
                if let key = item.key { Text(String(key).uppercased()).font(.geist(12)).foregroundStyle(p.faint) }
            }
            .foregroundStyle(item.destructive ? Palette.destructive : p.foreground)
            .padding(.horizontal, 10).frame(height: 28)
            .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Ловит правую кнопку мыши над видом и отдаёт точку в координатах окна (сверху слева).
/// Системное контекстное меню не нужно — открывается своё.
struct RightClick: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.action = action
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.action = action }

    final class CatcherView: NSView {
        var action: ((CGPoint) -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            guard let window else { return }
            let p = event.locationInWindow
            action?(CGPoint(x: p.x, y: (window.contentView?.bounds.height ?? window.frame.height) - p.y))
        }

        // левая кнопка и наведение проходят насквозь
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp else { return nil }
            return super.hitTest(point)
        }
    }
}

extension View {
    /// Правая кнопка — своё меню
    func onRightClick(_ action: @escaping (CGPoint) -> Void) -> some View {
        overlay(RightClick(action: action))
    }
}

// MARK: поиск (⌘K)

/// Поиск по разговорам: по названию и по тексту (FTS с русскими окончаниями)
struct SearchLayer: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var hits: [ConversationHit] = []
    @FocusState private var focused: Bool

    private var byTitle: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(app.conversations.prefix(8)) }
        return app.conversations.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { app.searchOpen = false }
            VStack(spacing: 0) {
                // шапка 52: лупа 20, поле 15, справа клавиша esc (хендофф, 1.7.3)
                HStack(spacing: 10) {
                    Icon("search", 20).foregroundStyle(p.mutedFg)
                    TextField("Найти в названиях и тексте всех разговоров", text: $query)
                        .textFieldStyle(.plain).font(.geist(15)).focused($focused)
                        .onSubmit { if let first = results.first { open(first.0) } }
                    KeyCap("esc")
                }
                .padding(.leading, 16).padding(.trailing, 12).frame(height: 52)
                .overlay(alignment: .bottom) { p.border.frame(height: 1) }
                // высота по найденному (строка 36, со строкой найденного места 56, подписи групп 27), не выше 420 — дальше прокрутка
                ScrollView { list }
                    .frame(height: min(420, listHeight))
                // внизу — подсказки клавиш
                HStack(spacing: 16) {
                    HStack(spacing: 4) { KeyCap("↵"); Text("открыть") }
                    HStack(spacing: 4) { KeyCap("⌘"); KeyCap("K"); Text("закрыть") }
                    Spacer()
                }
                .font(.geist(12)).foregroundStyle(p.faint)
                .padding(.horizontal, 14).frame(height: 36)
                .overlay(alignment: .top) { p.border.frame(height: 1) }
            }
            .frame(width: 600)
            .popoverChrome()
            .padding(.top, 84)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) { app.searchOpen = false; return .handled }
        .onChange(of: query) { hits = (try? app.store.searchConversations(query, limit: 30)) ?? [] }
    }

    private var list: some View {
                    VStack(alignment: .leading, spacing: 2) {
                        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
                        // пока ничего не набрано — сверху быстрые действия, ниже недавние разговоры
                        if !typed {
                            header("Действия")
                            ActionRow(icon: "plus", title: "Новый чат", keys: ["⌘", "N"]) { app.searchOpen = false; app.newChat() }
                            ActionRow(icon: "code-xml", title: "Новая задача агенту", keys: []) { app.searchOpen = false; app.newAgentTask() }
                            if !results.isEmpty { header("Недавние") }
                        }
                        if results.isEmpty && typed {
                            Text("Такого в разговорах не было.").tw(14, lh: 20).foregroundStyle(p.mutedFg)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                        // два раздела: совпало в названии и нашлось в самой переписке
                        let titled = results.filter { r in byTitle.contains { $0.id == r.0.id } }
                        let inText = results.filter { r in !byTitle.contains { $0.id == r.0.id } }
                        if typed && !titled.isEmpty { header("Названия") }
                        ForEach(titled, id: \.0.id) { c, snippet in
                            SearchRow(c: c, bot: c.botID.flatMap { id in app.bots.first { $0.id == id } }, snippet: snippet) { open(c) }
                        }
                        if typed && !inText.isEmpty { header("В переписке") }
                        ForEach(inText, id: \.0.id) { c, snippet in
                            SearchRow(c: c, bot: c.botID.flatMap { id in app.bots.first { $0.id == id } }, snippet: snippet) { open(c) }
                        }
                    }
                    .padding(6)
    }

    private func header(_ t: String) -> some View {
        Text(t).tw(12, lh: 17).foregroundStyle(p.faint).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
    }

    private var listHeight: CGFloat {
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let rows = results.reduce(CGFloat(12)) { $0 + ($1.1 == nil ? 36 : 56) + 2 }
        if typed { return results.isEmpty ? 68 : rows + 54 }
        return rows + 27 * 2 + 76
    }

    /// Строка быстрого действия: значок 20, название, клавиши справа
    private struct ActionRow: View {
        let icon: String
        let title: String
        let keys: [String]
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Icon(icon, 20).foregroundStyle(p.mutedFg)
                    Text(title).tw(14, lh: 20)
                    Spacer(minLength: 8)
                    HStack(spacing: 3) { ForEach(keys, id: \.self) { KeyCap($0) } }
                }
                .foregroundStyle(p.foreground)
                .padding(.horizontal, 10).frame(height: 36)
                .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }

    /// Сначала совпадения в названии, потом — в тексте (с найденным местом)
    private var results: [(Conversation, String?)] {
        // совпало и в названии, и в тексте — показать найденное место тоже
        var out: [(Conversation, String?)] = byTitle.map { c in (c, hits.first { $0.conversationID == c.id }?.snippet) }
        for h in hits where !out.contains(where: { $0.0.id == h.conversationID }) {
            if let c = app.conversations.first(where: { $0.id == h.conversationID }) { out.append((c, h.snippet)) }
        }
        return Array(out.prefix(30))
    }

    private func open(_ c: Conversation) {
        app.searchOpen = false
        app.openChat(c)
    }

    private struct SearchRow: View {
        let c: Conversation
        /// Разговор с ботом — его аватар вместо значка чата
        let bot: Bot?
        let snippet: String?
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let bot { BotAvatar(bot: bot, size: 20) } else { Icon(c.pinned ? "pin" : (c.kind == .agent ? "code-xml" : (c.kind == .bot ? "bot" : "message-square")), 20) }
                    }
                    .foregroundStyle(p.mutedFg).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).tw(14, lh: 20).lineLimit(1)
                        if let snippet { Text(snippet).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(2) }
                    }
                    Spacer(minLength: 8)
                    // когда был разговор — справа тусклым (хендофф, 1.7.3)
                    Text(RelativeWhen.string(c.updatedAt)).tw(12, lh: 20).foregroundStyle(p.faint)
                }
                .foregroundStyle(p.foreground)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(height: snippet == nil ? 36 : 56)
                .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

/// Клавиша чипом: «⌘», «K», «esc» — тонкая рамка, r5, 11 тусклым
struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    @Environment(\.palette) private var p

    var body: some View {
        Text(key).font(.geist(11)).foregroundStyle(p.mutedFg)
            .padding(.horizontal, 4).frame(minWidth: 18).frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(p.foreground.opacity(0.14)))
    }
}
