import AppKit
import SwiftUI
import Testing
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
