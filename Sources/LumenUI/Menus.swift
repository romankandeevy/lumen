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
    let action: () -> Void
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
                if item.separated { p.border.frame(height: 1).padding(.vertical, 5).padding(.horizontal, 2) }
                MenuRow(item: item) {
                    app.menu = nil
                    item.action()
                }
            }
        }
        .padding(6)
        .frame(minWidth: 220)
        .background(p.popover, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.foreground.opacity(0.1)))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

private struct MenuRow: View {
    let item: MenuItem
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(item.title).tw(14, lh: 20)
                Spacer(minLength: 24)
                if let key = item.key { Text(String(key).uppercased()).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
            }
            .foregroundStyle(item.destructive ? Palette.destructive : p.foreground)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: R.md))
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
                HStack(spacing: 10) {
                    Icon("search", 16).foregroundStyle(p.mutedFg)
                    TextField("Найти в разговорах: слово, проект, файл", text: $query)
                        .textFieldStyle(.plain).font(.geist(15)).focused($focused)
                        .onSubmit { if let first = results.first { open(first.0) } }
                }
                .padding(.horizontal, 14).frame(height: 48)
                .overlay(alignment: .bottom) { p.border.frame(height: 1) }
                // по высоте найденного, но не выше 380 — дальше прокрутка
                // высота по найденному (строка 36, со строкой найденного места 56), не выше 380
                ScrollView { list }
                    .frame(height: min(380, results.isEmpty ? 68 : results.reduce(12) { $0 + ($1.1 == nil ? 36 : 56) + 2 }))
            }
            .frame(width: 560)
            .background(p.popover, in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.foreground.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) { app.searchOpen = false; return .handled }
        .onChange(of: query) { hits = (try? app.store.searchConversations(query, limit: 12)) ?? [] }
    }

    private var list: some View {
                    VStack(alignment: .leading, spacing: 2) {
                        if results.isEmpty {
                            Text("Такого в разговорах не было.").tw(14, lh: 20).foregroundStyle(p.mutedFg)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                        ForEach(results, id: \.0.id) { c, snippet in
                            SearchRow(c: c, snippet: snippet) { open(c) }
                        }
                    }
                    .padding(6)
    }

    /// Сначала совпадения в названии, потом — в тексте (с найденным местом)
    private var results: [(Conversation, String?)] {
        var out: [(Conversation, String?)] = byTitle.map { ($0, nil) }
        for h in hits where !out.contains(where: { $0.0.id == h.conversationID }) {
            if let c = app.conversations.first(where: { $0.id == h.conversationID }) { out.append((c, h.snippet)) }
        }
        return Array(out.prefix(12))
    }

    private func open(_ c: Conversation) {
        app.searchOpen = false
        app.openChat(c)
    }

    private struct SearchRow: View {
        let c: Conversation
        let snippet: String?
        let action: () -> Void

        @Environment(\.palette) private var p
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Icon(c.kind == .agent ? "square-terminal" : "message-square", 16).foregroundStyle(p.mutedFg).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).tw(14, lh: 20).lineLimit(1)
                        if let snippet { Text(snippet).tw(12, lh: 16).foregroundStyle(p.mutedFg).lineLimit(2) }
                    }
                    Spacer(minLength: 8)
                    Text(RelativeWhen.string(c.updatedAt)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
                .foregroundStyle(p.foreground)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(height: snippet == nil ? 36 : 56)
                .background(hover ? p.foreground.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: R.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}
