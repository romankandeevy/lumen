import AppKit
import SwiftUI
import Testing
import LumenCore
@testable import LumenUI

// Прыжок вверх в конце ответа (Рома, 19.10): «он написал сообщение — и меня поднимает вверх, приходится листать вниз».
// Модель переписки как в ChatView: ленивый список сообщений, под ним план и идущий ответ (вне списка).
// Конец хода: план уходит, идущий ответ становится сообщением списка, появляется карточка «что дальше».

@MainActor @Observable final class FakeTranscript {
    var messages: [Int] = Array(0..<24)
    var streaming = true
    var plan = true
    var next = false
    var atBottom = true
    /// Высота поля ввода под перепиской: растёт от очереди сообщений, вложений, длинного черновика
    var composer: CGFloat = 80

    static func text(_ i: Int) -> String {
        "Абзац ответа \(i): " + String(repeating: "слова, которые переносятся по ширине колонки; ", count: 4 + (i * 7) % 12)
            + "\n\nВторой абзац — **жирное**, `код` и [ссылка](https://example.com). " + String(repeating: "ещё текст ", count: 10 + i % 9)
    }
}

private struct FakeChat: View {
    @Bindable var t: FakeTranscript
    let pinBottom: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Rectangle().frame(height: t.composer)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(t.messages, id: \.self) { i in
                        // готовые ответы — как в переписке: RichText → LinkText (NSTextView)
                        RichText(text: FakeTranscript.text(i)).frame(width: 600, alignment: .leading)
                    }
                    if t.next { Rectangle().frame(width: 600, height: 120) }
                    VStack {
                        if t.plan { Rectangle().frame(width: 600, height: 180) }
                        // идущий ответ печатается SwiftUI-текстом с курсором, готовый — уже LinkText
                        if t.streaming { RichText(text: FakeTranscript.text(t.messages.count), caret: true).frame(width: 600, alignment: .leading) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(32)
            }
            .defaultScrollAnchor(.bottom)
            // как в ChatView: где мы и, с правкой, — держать низ
            .modifier(ScrollTracking(atBottom: $t.atBottom, follow: pinBottom ? { proxy.scrollTo("bottom", anchor: .bottom) } : {}))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                if pinBottom && t.atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .environment(\.palette, Palette.light)
            .onChange(of: t.messages.count) { if t.atBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }
}

/// Дождаться, пока окно разложится и прокрутка встанет (в общем прогоне тесты идут медленнее)
@MainActor private func settle(_ host: NSView, _ seconds: Double = 0.8) async throws {
    let until = Date().addingTimeInterval(seconds)
    var last: CGFloat? = nil
    while Date() < until {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let now = gapToBottom(host)
        if now != nil, now == last, Date() > until.addingTimeInterval(-seconds / 2) { return }
        last = now
    }
}

/// Сколько точек от низа переписки до низа экрана (0 — у самого низа)
@MainActor private func gapToBottom(_ view: NSView) -> CGFloat? {
    func find(_ v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView { return s }
        for sub in v.subviews { if let s = find(sub) { return s } }
        return nil
    }
    guard let scroll = find(view), let doc = scroll.documentView else { return nil }
    let clip = scroll.contentView.bounds
    return doc.isFlipped ? doc.frame.height - clip.maxY : clip.minY
}

/// Окно с моделью переписки; `steps` — что меняем после того, как переписка встала к низу
@MainActor private func gapAfter(pinBottom: Bool, start: (FakeTranscript) -> Void, prepare: ((FakeTranscript) -> Void)? = nil,
                                  change: (FakeTranscript) -> Void) async throws -> CGFloat {
    let t = FakeTranscript()
    start(t)
    let host = NSHostingView(rootView: FakeChat(t: t, pinBottom: pinBottom).frame(width: 700, height: 600))
    host.frame = CGRect(x: 0, y: 0, width: 700, height: 600)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    try await settle(host, 1.2)
    #expect((gapToBottom(host) ?? 99) < 40) // сначала — у низа (как в ScrollTracking: ближе 40 pt — «внизу»)
    if let prepare {
        prepare(t)
        try await settle(host)
    }
    change(t)
    try await settle(host, 1.2)
    return gapToBottom(host) ?? 99
}

/// Человек отправил сообщение и смотрит вниз; агент начал ход: план и идущий ответ появились под последним сообщением
@MainActor @Test(.serialized) func agentStartKeepsTranscriptAtBottom() async throws {
    let idle: (FakeTranscript) -> Void = { $0.streaming = false; $0.plan = false }
    // человек отправил — сообщение в список, переписку крутит вниз (как onChange(messages.count) в ChatView)
    let sent: (FakeTranscript) -> Void = { $0.messages.append($0.messages.count) }
    let start: (FakeTranscript) -> Void = { $0.plan = true; $0.streaming = true }
    let before = try await gapAfter(pinBottom: false, start: idle, prepare: sent, change: start)
    let after = try await gapAfter(pinBottom: true, start: idle, prepare: sent, change: start)
    _ = before // здесь SwiftUI и раньше держал низ — тест сторожит, чтобы так и осталось
    print("начало хода: до правки \(before) pt от низа, после — \(after) pt")
    if #available(macOS 15.0, *) { #expect(after < 40) }
}

/// Конец хода: план уходит, идущий ответ становится сообщением, появляется карточка «что дальше»
@MainActor @Test(.serialized) func endOfTurnKeepsTranscriptAtBottom() async throws {
    let finish: (FakeTranscript) -> Void = { t in
        t.plan = false; t.streaming = false; t.messages.append(t.messages.count); t.next = true
    }
    let before = try await gapAfter(pinBottom: false, start: { _ in }, change: finish)
    let after = try await gapAfter(pinBottom: true, start: { _ in }, change: finish)
    print("конец хода: до правки \(before) pt от низа, после — \(after) pt")
    if #available(macOS 15.0, *) { #expect(after < 40) }
}

/// Под перепиской выросло поле ввода (очередь, вложения, длинный черновик): видимая часть стала ниже
@MainActor @Test(.serialized) func growingComposerKeepsTranscriptAtBottom() async throws {
    let grow: (FakeTranscript) -> Void = { $0.composer = 220 }
    let before = try await gapAfter(pinBottom: false, start: { _ in }, change: grow)
    #expect(before > 100) // так было: низ переписки уезжал под поле ввода
    let after = try await gapAfter(pinBottom: true, start: { _ in }, change: grow)
    print("поле ввода выросло: до правки \(before) pt от низа, после — \(after) pt")
    if #available(macOS 15.0, *) { #expect(after < 40) }
}

/// Переписка без «резинки» (Рома, 19.10): дальше начала и конца не тянется
@MainActor @Test(.serialized) func transcriptHasNoOverscroll() async throws {
    let host = NSHostingView(rootView: ScrollView { VStack { ForEach(0..<60, id: \.self) { Text("строка \($0)") } }.background(NoBounce()) }
        .frame(width: 300, height: 300))
    host.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func find(_ v: NSView) -> NSScrollView? { if let s = v as? NSScrollView { return s }; for x in v.subviews { if let s = find(x) { return s } }; return nil }
    var found: NSScrollView?
    for _ in 0..<30 where found?.verticalScrollElasticity != NSScrollView.Elasticity.none {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        found = find(host)
    }
    let scroll = try #require(found)
    #expect(scroll.verticalScrollElasticity == .none)
}

/// Панели выезжают плавно, и переписка едет вместе с ними (Рома, 25.10). Раньше ширину меняли рывком,
/// чтобы прокрутка не уезжала вверх; теперь сторожим: длинный разговор у низа — после левой и правой панели он у низа
@MainActor @Test(.serialized, arguments: [1100.0, 1600.0]) func panelsSlideAndTranscriptStaysAtBottom(width: Double) async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-panels-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let c = Conversation(title: "Длинный", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    for i in 0..<30 {
        try app.store.save(ChatMessage(conversationID: c.id, role: i % 2 == 0 ? .user : .assistant, text: FakeTranscript.text(i)))
    }
    app.reloadConversations()
    app.openChat(c)
    let size = CGRect(x: 0, y: 0, width: width, height: 720)
    let host = NSHostingView(rootView: RootView(app: app).frame(width: size.width, height: size.height))
    host.frame = size
    let window = NSWindow(contentRect: size, styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    try await settle(host, 2)
    let start = transcriptGapToBottom(host) ?? 99
    #expect(start < 60) // 48 — нижнее поле переписки
    var worst: CGFloat = 0
    let transcriptGap = { transcriptGapToBottom(host) ?? 99 }
    for flip in [{ app.update { $0.sidebarHidden.toggle() } }, { app.update { $0.contextOpen.toggle() } },
                 { app.update { $0.sidebarHidden.toggle() } }, { app.update { $0.contextOpen.toggle() } }] {
        flip()
        var trace: [Int] = []
        var xs: [Int] = []
        for _ in 0..<25 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            trace.append(Int(transcriptGap()))
            xs.append(Int(transcriptScrollMinX(host) ?? -1))
        }
        print("место переписки (\(Int(width))): \(xs)")
        print("ход (\(Int(width))): \(trace)")
        // во время движения переписка тоже у низа, а не уезжает и возвращается
        #expect((trace.max() ?? 0) < 60)
        try await settle(host, 1.2)
        print("шаг: \(transcriptGap()) pt от низа")
        worst = max(worst, transcriptGap())
    }
    print("панели: в начале \(start) pt от низа, худшее после движения — \(worst) pt")
    #expect(worst < 60)
}

/// Как gapToBottom, но у самой длинной прокрутки в окне — переписки (в окне есть и прокрутка левой панели)
@MainActor private func transcriptGapToBottom(_ view: NSView) -> CGFloat? {
    func all(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(all) }
    guard let scroll = all(view).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
          let doc = scroll.documentView else { return nil }
    let clip = scroll.contentView.bounds
    return doc.isFlipped ? doc.frame.height - clip.maxY : clip.minY
}

@MainActor private func transcriptScrollMinX(_ view: NSView) -> CGFloat? {
    func all(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(all) }
    guard let scroll = all(view).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else { return nil }
    return scroll.convert(scroll.bounds, to: nil).minX
}
