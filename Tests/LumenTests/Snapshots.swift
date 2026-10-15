import AppKit
import SwiftUI
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenUI

// Снимки экранов для сверки с макетом (ui/, mockups/). Рисуются в невидимом окне — экран не трогают.
//   LUMEN_SNAP=/путь/к/папке swift test --filter Snapshots

private let snapDir = ProcessInfo.processInfo.environment["LUMEN_SNAP"]

@MainActor
enum Snap {
    static func registerFonts() {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Fonts").standardized
        for f in ["Regular", "Medium", "SemiBold", "Bold"] {
            CTFontManagerRegisterFontsForURL(dir.appendingPathComponent("Geist-\(f).ttf") as CFURL, .process, nil)
        }
    }

    static func save<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 1180, height: 760)) async throws {
        guard let dir = snapDir else { return }
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600)) // анимации и прокрутка до конца
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        window.close()
    }

    /// Приложение с чистыми данными во временной папке
    static func app() throws -> AppModel {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-snap-\(UUID().uuidString)")
        return try AppModel(paths: AppPaths(root: home))
    }
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotsMatchMockup() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    try await Snap.save(RootView(app: app), "01-onboarding")

    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    try await Snap.save(RootView(app: app), "03-new-chat")

    // разговор как в макете (mockups/02-chat.jpg)
    let c = Conversation(title: "Lumen: замысел", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Напомни, на чём мы остановились с Люменом и что я просил про кнопки?"))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Остановились на макете первой версии: память между разговорами, люди, характер ответов и боты-агенты.\n\nПро кнопки ты просил одно: когда я внедряю мокап или новую функцию, существующие кнопки остаются на местах. Двигаю только по твоей просьбе."))
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Да. И запомни: светлую тему не делаем, только тёмные."))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Понял. Тёмных тем будет две — «Люмен» и «Монохром». Светлой не будет."))
    for t in ["Что поделаем сегодня?", "Тексты для блога"] {
        try app.store.save(Conversation(title: t, backend: .subscription, model: .sonnet, effort: .medium))
    }
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "02-chat")

    for s in SettingsView.Section.allCases {
        app.page = .settings(s)
        try await Snap.save(RootView(app: app), "12-settings-\(s)")
    }
}

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotOrb() async throws {
    try await Snap.save(HStack(spacing: 60) {
        Orb(state: .idle, size: 96, animated: false)
        Orb(state: .idle, size: 22, animated: false).scaleEffect(4)
    }.frame(width: 400, height: 240).background(Palette.lumen.card).environment(\.palette, .lumen), "orb", size: CGSize(width: 400, height: 240))
}
