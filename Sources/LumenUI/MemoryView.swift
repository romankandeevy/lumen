import LumenCore
import SwiftUI

/// «Что Lumen знает» (`pages/memory-page.tsx`): факты с источником (закрепить / изменить / забыть)
/// граф связей (GraphView.swift) и поиск по прошлым разговорам.
struct MemoryView: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var kind: MemoryKind?
    @State private var query = ""
    @State private var adding = false
    @State private var file: URL?
    @State private var hits: [ConversationHit] = []

    enum Mode: Hashable { case facts, graph, talks }
    @State private var graph: GraphModel?

    private var shown: [MemoryFact] {
        let base = app.memories.filter { kind == nil || $0.kind == kind }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        // поиск с русскими окончаниями (FTS), плюс простое вхождение — чтобы находилось и по кусочку слова
        let found = Set(((try? app.store.searchMemories(query, limit: 200)) ?? []).compactMap(\.id))
        return base.filter { f in found.contains(f.id ?? -1) || f.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        PageFrame(title: "Что Lumen знает",
                  lead: "Память о тебе, твоих проектах и людях вокруг. Она подставляется в каждый разговор: закреплённое — всегда, остальное — когда к месту.") {
            LButton(title: "Запомнить факт", icon: "plus", kind: .primary) { adding = true }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MiniSegmented(value: $app.memoryMode, options: [(.facts, "Факты, \(app.memories.count)"), (.graph, "Граф"), (.talks, "Прошлые разговоры")])
                    if app.memoryMode != .graph {
                        SearchField(text: $query, placeholder: app.memoryMode == .facts ? "Найти факт" : "Найти в разговорах: слово, проект, файл")
                    } else {
                        Spacer()
                    }
                }
                if app.memoryMode == .graph {
                    Group {
                        if let graph {
                            GraphView(app: app, model: graph)
                        } else {
                            Color.clear.onAppear { graph = GraphModel(graph: app.memoryGraph()) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 480)
                    .padding(.bottom, 24)
                    .onChange(of: app.memories) { graph?.update(app.memoryGraph()) }
                } else {
                // xl:grid-cols-[1fr_280px]: на широком окне файлы и настройки сбоку, иначе — снизу
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            main.frame(minWidth: 560)
                            aside.frame(width: 280)
                        }
                        VStack(alignment: .leading, spacing: 32) { main; aside }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
                }
            }
        }
        .sheet(isPresented: $adding) { AddFactSheet(app: app) { adding = false }.environment(\.palette, p) }
        .sheet(item: $file) { url in MemoryFileSheet(app: app, url: url) { file = nil }.environment(\.palette, p) }
        .overlay(alignment: .bottom) { forgottenBanner }
        .onChange(of: query) { searchTalks() }
        .onChange(of: app.memoryMode) { searchTalks() }
    }

    @ViewBuilder private var main: some View {
            VStack(alignment: .leading, spacing: 16) {
                if app.memoryMode == .facts {
                    HStack(spacing: 6) {
                        KindChip(name: "Всё", active: kind == nil) { kind = nil }
                        ForEach(MemoryKind.allCases) { k in KindChip(name: k.name, active: kind == k) { kind = k } }
                    }
                    VStack(spacing: 0) {
                        if shown.isEmpty {
                            Text(query.isEmpty ? "Здесь пусто. Скажи в чате «запомни, что…» — и факт появится тут."
                                               : "Ничего не нашлось. Попробуй другое слово или поищи в прошлых разговорах.")
                                .font(.geist(14)).foregroundStyle(p.mutedFg).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 40)
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { p.border.frame(height: 1) }
                            FactRow(app: app, fact: f)
                        }
                    }
                    .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
                    .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                } else {
                    VStack(spacing: 8) {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Напиши слово, проект или файл — найду, в каком разговоре это было.")
                                .font(.geist(14)).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if hits.isEmpty {
                            Text("В разговорах такого не было.").font(.geist(14)).foregroundStyle(p.mutedFg)
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                        ForEach(hits) { h in TalkCard(hit: h) { open(h.conversationID) } }
                    }
                }
            }
    }

    private var aside: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Файлы памяти")
                VStack(spacing: 6) {
                    FileRow(name: "USER.md", note: "кто ты и как с тобой говорить",
                            size: app.fileSize(app.memoryFileText(user: true))) { file = app.userFile }
                    FileRow(name: "MEMORY.md", note: "проекты, решения, люди",
                            size: app.fileSize(app.memoryFileText(user: false))) { file = app.memoryFile }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(text: "Как запоминать")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Запоминать само").font(.geist(14))
                            Text("Lumen сам сохраняет важное из разговора и показывает плашку «Запомнил». Выключено — только по просьбе «запомни».")
                                .font(.geist(12)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        LSwitch(isOn: Binding(get: { app.prefs.autoRemember }, set: { v in
                            app.update { $0.autoRemember = v }
                            app.chat.memoryChanged()
                        }))
                    }
                    if let last = app.memories.max(by: { $0.createdAt < $1.createdAt }) {
                        (Text("Последнее: ").foregroundStyle(p.mutedFg) + Text("«\(last.text)»"))
                            .font(.geist(12)).lineLimit(2)
                    }
                }
                .padding(14)
                .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
                .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
            }
        }
    }

    @ViewBuilder private var forgottenBanner: some View {
        if let f = app.lastForgotten {
            HStack(spacing: 10) {
                Icon("x", 14)
                Text("Забыл: ").foregroundStyle(p.mutedFg) + Text(f.text).strikethrough()
                Spacer(minLength: 8)
                Button { app.restoreForgotten() } label: {
                    IconLabel(text: "Вернуть", icon: "undo-2", size: 14).font(.geist(13, .medium))
                }
                .buttonStyle(.plain)
                Button { app.lastForgotten = nil } label: { Icon("x", 14).foregroundStyle(p.mutedFg) }
                    .buttonStyle(.plain)
            }
            .font(.geist(13)).lineLimit(1)
            .padding(.horizontal, 14).frame(height: 40)
            .background(p.popover, in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .frame(maxWidth: 520)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func searchTalks() {
        guard app.memoryMode == .talks else { return }
        hits = (try? app.store.searchConversations(query)) ?? []
    }

    private func open(_ conversationID: String) {
        if let c = app.conversations.first(where: { $0.id == conversationID }) { app.openChat(c) }
    }
}

/// Сегменты страницы (`Segmented` из макета): h-7 rounded-md text-xs на подложке muted/50
struct MiniSegmented<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { id, name in
                Button { value = id } label: {
                    Text(name).font(.geist(12))
                        .foregroundStyle(id == value ? p.foreground : p.mutedFg)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(id == value ? p.background : .clear, in: RoundedRectangle(cornerRadius: R.md))
                        .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(id == value ? p.border : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(p.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
    }
}

/// Поиск: h-8 rounded-lg border bg-input/30, лупа, крестик очистки
struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Icon("search", 16).foregroundStyle(p.mutedFg)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.geist(14)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Icon("x", 14).foregroundStyle(p.mutedFg) }
                    .buttonStyle(.plain).help("Очистить")
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .frame(minWidth: 224, maxWidth: .infinity)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(focused ? p.glow.opacity(0.35) : p.border))
        .shadow(color: focused ? p.glowSoft : .clear, radius: 14)
    }
}

/// Фильтр вида: rounded-full border px-3 py-1 text-xs
struct KindChip: View {
    let name: String
    let active: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(name).font(.geist(12))
                .foregroundStyle(active || hover ? p.foreground : p.mutedFg)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(active ? p.glow.opacity(0.1) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(active ? p.glow.opacity(0.4) : p.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Строка факта (`FactRow`): точка (светится, если закреплён), текст, вид / источник / когда; действия по наведению
struct FactRow: View {
    @Bindable var app: AppModel
    let fact: MemoryFact

    @Environment(\.palette) private var p
    @State private var hover = false
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(fact.pinned ? p.glow : p.foreground.opacity(0.25)).frame(width: 6, height: 6)
                .shadow(color: fact.pinned ? p.glow : .clear, radius: 4)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                if editing {
                    TextField("", text: $text).textFieldStyle(.plain).font(.geist(14))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.md))
                        .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.glow.opacity(0.5)))
                        .focused($focused)
                        .onSubmit(save)
                        .onExitCommand { editing = false }
                } else {
                    Text(fact.text).tw(14, lh: 22.75).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(fact.kind.name)
                    slash
                    if let cid = fact.conversationID, let c = app.conversations.first(where: { $0.id == cid }) {
                        Button("из «\(fact.source)»") { app.openChat(c) }.buttonStyle(.plain)
                    } else {
                        Text(fact.source == "Знакомство" || fact.source == "Добавлено вручную" ? fact.source : "из «\(fact.source)»")
                    }
                    slash
                    Text(RelativeWhen.string(fact.createdAt))
                }
                .tw(12, lh: 16).foregroundStyle(p.mutedFg)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                if editing {
                    LButton(title: "Сохранить", icon: "check", kind: .primary, size: .xs, action: save)
                } else {
                    icon(fact.pinned ? "pin-off" : "pin", fact.pinned ? "Открепить" : "Закрепить: всегда в разговоре") {
                        app.updateMemory(fact) { $0.pinned.toggle() }
                    }
                    icon("pencil", "Изменить") {
                        text = fact.text
                        editing = true
                        focused = true
                    }
                    icon("x", "Забыть") { withAnimation { app.forget(fact) } }
                }
            }
            .opacity(editing || hover ? 1 : 0.4)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var slash: some View { Text("/").foregroundStyle(p.foreground.opacity(0.2)) }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { app.updateMemory(fact) { $0.text = t } }
        editing = false
    }

    private func icon(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        IconButton(icon: name, help: help, action: action).frame(width: 32, height: 32)
    }
}

/// Найденный разговор: заголовок, когда, место с подсветкой
struct TalkCard: View {
    let hit: ConversationHit
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon(hit.kind == .agent ? "square-terminal" : "message-square", 14).foregroundStyle(p.mutedFg)
                    Text(hit.title).font(.geist(14, .medium)).lineLimit(1)
                    Spacer()
                    Text(RelativeWhen.string(hit.date)).font(.geist(12)).foregroundStyle(p.mutedFg)
                }
                Text(hit.snippet).font(.geist(14)).foregroundStyle(p.foreground.opacity(0.8)).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? p.card : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(hover ? p.glow.opacity(0.3) : p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Файл памяти в боковой колонке
struct FileRow: View {
    let name: String
    let note: String
    let size: String
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon("file-text", 16).foregroundStyle(p.mutedFg)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 12, design: .monospaced))
                    Text(note).font(.geist(12)).foregroundStyle(p.mutedFg).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(size).font(.geist(11)).foregroundStyle(p.mutedFg)
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hover ? p.card : p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Окно файла памяти (`FileDialog`)
struct MemoryFileSheet: View {
    @Bindable var app: AppModel
    let url: URL
    let close: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 14, weight: .medium, design: .monospaced))
                Text("Этот вид на память Lumen читает в каждом разговоре. Файл собирается из фактов — править удобнее в приложении.")
                    .font(.geist(14)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                Text(app.memoryFileText(user: url == app.userFile))
                    .font(.system(size: 12, design: .monospaced)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .frame(maxHeight: 320)
            .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            HStack {
                Spacer()
                LButton(title: "Открыть в редакторе", kind: .outline) { app.openInEditor(url) }
                LButton(title: "Готово", kind: .primary, action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 576)
        .background(p.popover)
        .foregroundStyle(p.foreground)
        .preferredColorScheme(p.scheme)
    }
}

/// «Запомнить факт» (`AddFact`): текст, вид, закрепить
struct AddFactSheet: View {
    @Bindable var app: AppModel
    let close: () -> Void

    @Environment(\.palette) private var p
    @State private var text = ""
    @State private var kind: MemoryKind = .you
    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Запомнить факт").font(.geist(18, .semibold)) } icon: { Icon("brain", 16).foregroundStyle(p.glow) }
                Text("Одна мысль — один факт. Lumen будет учитывать его в разговорах.").font(.geist(14)).foregroundStyle(p.mutedFg)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Например: по пятницам релизов не делаем").font(.geist(14)).foregroundStyle(p.mutedFg)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                TextEditor(text: $text).font(.geist(14)).scrollContentBackground(.hidden)
                    .padding(.horizontal, 7).padding(.vertical, 8)
            }
            .frame(minHeight: 80)
            .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            HStack(spacing: 12) {
                MiniSegmented(value: $kind, options: MemoryKind.allCases.map { ($0, $0.name) })
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    LSwitch(isOn: $pinned)
                    Text("Закрепить").font(.geist(14))
                }
            }
            HStack {
                Spacer()
                LButton(title: "Отмена", kind: .ghost, action: close).keyboardShortcut(.cancelAction)
                LButton(title: "Запомнить", kind: .primary) {
                    app.addMemory(text, kind: kind, pinned: pinned)
                    close()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(p.popover)
        .foregroundStyle(p.foreground)
        .preferredColorScheme(p.scheme)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Плашка «Запомнил» (`Remembered`): полоска света проходит один раз; изменить, забыть, вернуть
struct RememberedCard: View {
    @Bindable var app: AppModel
    let id: Int64
    /// Строка в общем списке «Запомнил N»: без рамки и подписи, действия — значками
    var compact = false

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion
    @State private var editing = false
    @State private var text = ""
    @State private var forgotten: MemoryFact?
    @State private var shine: CGFloat = -0.4

    var body: some View {
        if compact, let f = app.memory(id) {
            compactRow(f)
        } else if let f = app.memory(id) {
            HStack(alignment: .top, spacing: 12) {
                Icon("brain", 16).foregroundStyle(p.glow).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Запомнил").font(.geist(12)).foregroundStyle(p.mutedFg)
                    if editing {
                        TextField("", text: $text).textFieldStyle(.plain).font(.geist(14))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.md))
                            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.glow.opacity(0.5)))
                            .onSubmit { save(f) }
                            .onExitCommand { editing = false }
                    } else {
                        Text(f.text).font(.geist(14)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if editing {
                        LButton(title: "Сохранить", icon: "check", kind: .primary, size: .xs) { save(f) }
                    } else {
                        LButton(title: "Изменить", icon: "pencil", kind: .ghost, size: .xs) {
                            text = f.text
                            editing = true
                        }
                    }
                    LButton(title: "Забыть", icon: "x", kind: .ghost, size: .xs) {
                        forgotten = f
                        app.forget(f)
                        app.lastForgotten = nil // вернуть можно прямо здесь
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(p.glow.opacity(0.04), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay {
                // `.shine`: полоска света проходит по плашке один раз
                GeometryReader { g in
                    LinearGradient(colors: [.clear, p.glowSoft, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.4)
                        .offset(x: g.size.width * shine)
                }
                .clipShape(RoundedRectangle(cornerRadius: R.xl))
                .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.25)))
            .onAppear {
                guard !lessMotion else { shine = 1.2; return }
                withAnimation(.easeOut(duration: 1.6)) { shine = 1.2 }
            }
        } else if let f = forgotten {
            HStack(spacing: 8) {
                Icon("x", 14)
                Text("Забыл: ") + Text(f.text).strikethrough()
                Spacer(minLength: 8)
                Button {
                    var restored = f
                    restored.id = nil
                    if let saved = try? app.store.save(restored), let newID = saved.id { relink(newID) }
                    forgotten = nil
                    app.reloadMemories()
                } label: {
                    IconLabel(text: "Вернуть", icon: "undo-2", size: 14).foregroundStyle(p.foreground)
                }
                .buttonStyle(.plain)
            }
            .font(.geist(12)).foregroundStyle(p.mutedFg)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    /// Строка списка: текст факта, справа — «изменить» и «забыть» значками; забытое — зачёркнуто, с «Вернуть»
    @ViewBuilder private func compactRow(_ f: MemoryFact) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if editing {
                TextField("", text: $text).textFieldStyle(.plain).font(.geist(13))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(p.background.opacity(0.6), in: RoundedRectangle(cornerRadius: R.md))
                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.glow.opacity(0.5)))
                    .onSubmit { save(f) }
                    .onExitCommand { editing = false }
                IconButton(icon: "check", help: "Сохранить", side: 26, iconSize: 14) { save(f) }
            } else {
                Text(f.text).font(.geist(13)).foregroundStyle(p.textSoft).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    IconButton(icon: "pencil", help: "Изменить", side: 26, iconSize: 14) { text = f.text; editing = true }
                    IconButton(icon: "x", help: "Забыть", side: 26, iconSize: 14) {
                        forgotten = f
                        app.forget(f)
                        app.lastForgotten = nil
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func save(_ f: MemoryFact) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { app.updateMemory(f) { $0.text = t } }
        editing = false
    }

    /// Вернули забытое — у факта новый id: перепривязать плашку в сообщении
    private func relink(_ newID: Int64) {
        guard let i = app.chat.messages.firstIndex(where: { $0.remembered.contains(id) }) else { return }
        var m = app.chat.messages[i]
        m.remembered = m.remembered.map { $0 == id ? newID : $0 }
        _ = try? app.store.save(m)
        app.chat.reloadMessages()
    }
}

/// Запомнил много сразу (загрузил всё о себе — и тридцать фактов): одна плашка «Запомнил 30 фактов» вместо тридцати карточек.
/// По нажатию — список в своей области прокрутки (не длиннее 320), у каждого факта «изменить» и «забыть»
struct RememberedGroup: View {
    @Bindable var app: AppModel
    let ids: [Int64]
    /// Для снимков: показать раскрытым
    var initiallyOpen = false

    @Environment(\.palette) private var p
    @Environment(\.stepsOpened) private var stepsOpened
    @State private var open = false
    @State private var hover = false
    @State private var listHeight: CGFloat = 0

    private var count: Int { ids.filter { app.memory($0) != nil }.count }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: R.xl)
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 12) {
                    Icon("brain", 16).foregroundStyle(p.glow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Запомнил").font(.geist(12)).foregroundStyle(p.mutedFg)
                        Text("\(count) " + Plural.form(count, "факт", "факта", "фактов")).font(.geist(14))
                    }
                    Spacer(minLength: 8)
                    Text(open ? "Свернуть" : "Показать").font(.geist(12)).foregroundStyle(hover ? p.foreground : p.mutedFg)
                    Icon(open ? "chevron-up" : "chevron-down", 12).foregroundStyle(p.mutedFg)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            if open {
                p.glow.opacity(0.18).frame(height: 1)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                            if i > 0 { p.border.opacity(0.6).frame(height: 1).padding(.horizontal, 12) }
                            RememberedCard(app: app, id: id, compact: true)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(max(listHeight, 1), 320))
                .scrollBounceBehavior(.always)
                HStack {
                    Spacer()
                    Button("Открыть память") { app.page = .memory }.buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.glow)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(alignment: .top) { p.glow.opacity(0.18).frame(height: 1) }
            }
        }
        .background(p.glow.opacity(0.04), in: shape)
        .overlay(shape.strokeBorder(p.glow.opacity(0.25)))
        .onAppear { if initiallyOpen { open = true } }
        .onChange(of: open) { _, now in stepsOpened(now) }
        .onDisappear { if open { stepsOpened(false) } }
    }
}

/// «Опирался на N воспоминаний» — по нажатию список фактов
struct RecalledLine: View {
    @Bindable var app: AppModel
    let ids: [Int64]

    @Environment(\.palette) private var p
    @State private var open = false
    @State private var hover = false

    private var facts: [MemoryFact] { ids.compactMap { app.memory($0) } }

    var body: some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Icon("brain", 14)
                        Text("Опирался на \(facts.count) " + Plural.form(facts.count, "воспоминание", "воспоминания", "воспоминаний"))
                    }
                    .font(.geist(12)).foregroundStyle(hover ? p.glow : p.mutedFg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
                if open {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(facts) { f in
                            Text("· " + f.text).font(.geist(12)).foregroundStyle(p.mutedFg)
                        }
                        Button("Открыть память") { app.page = .memory }.buttonStyle(.plain).font(.geist(12)).foregroundStyle(p.glow)
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }
}
