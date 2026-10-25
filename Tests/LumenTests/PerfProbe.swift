import AppKit
import LumenCore
import SwiftUI
import Testing
@testable import LumenUI

/// Замер на настоящих данных (копия папки Lumen): `LUMEN_PERF_HOME=/копия swift test --filter perfProbe`.
/// Сколько занимает первая раскладка окна, смена страниц и открытие самых длинных разговоров
private let perfHome = ProcessInfo.processInfo.environment["LUMEN_PERF_HOME"]

@MainActor @Test(.enabled(if: perfHome != nil)) func perfProbe() async throws {
    let t0 = Date()
    let app = try AppModel(paths: AppPaths(root: URL(fileURLWithPath: perfHome!)))
    print("модель: \(ms(t0)) мс, разговоров \(app.conversations.count), фактов \(app.memories.count)")
    let size = CGRect(x: 0, y: 0, width: 1470, height: 860)
    let host = NSHostingView(rootView: RootView(app: app).frame(width: size.width, height: size.height))
    host.frame = size
    let window = NSWindow(contentRect: size, styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    var t = Date()
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    print("первая раскладка: \(ms(t)) мс")
    for (name, page) in [("память", AppModel.Page.memory), ("кастомизация", .skills), ("артефакты", .artifacts), ("чат", .chat)] {
        t = Date()
        app.page = page
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        print("страница «\(name)»: \(ms(t)) мс")
        try await Task.sleep(for: .milliseconds(300))
    }
    let longest = app.conversations.sorted { ((try? app.store.messages(in: $0.id).count) ?? 0) > ((try? app.store.messages(in: $1.id).count) ?? 0) }.prefix(3)
    for c in longest {
        t = Date()
        app.openChat(c)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let first = ms(t)
        try await Task.sleep(for: .milliseconds(400))
        print("разговор «\(c.title.prefix(30))» (\((try? app.store.messages(in: c.id).count) ?? 0) сообщ.): \(first) мс")
    }
    t = Date()
    app.openSettings(.theme)
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    print("настройки: \(ms(t)) мс")
}

private func ms(_ d: Date) -> Int { Int(Date().timeIntervalSince(d) * 1000) }
