import AppKit
import SwiftUI
import Testing
@testable import LumenCore
@testable import LumenUI

// Снимки браузера 1.7 для сверки глазами:  LUMEN_SNAP=/путь swift test --filter BrowserSnapshots
private let snapDir = ProcessInfo.processInfo.environment["LUMEN_SNAP"]

@MainActor @Test(.enabled(if: snapDir != nil)) func snapshotBrowserSeventeen() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Роман", address: .ty, backend: .subscription, theme: .lumen)
    let b = app.browser
    let p = Palette.lumen
    func pane(_ name: String, full: Bool = false, size: CGSize = CGSize(width: 640, height: 520)) async throws {
        try await Snap.save(BrowserPane(app: app, browser: b, full: full).environment(\.palette, p).background(p.background), name, size: size)
    }

    b.webView.loadHTMLString("<h1>Билеты</h1>", baseURL: URL(string: "https://tickets.example.com"))
    try await Task.sleep(for: .milliseconds(900))

    // 1. агент на странице: курсор, рамка вокруг кнопки, плашка «Пауза / Стоп»
    b.activity = "designer · Нажимает «Оплатить заказ»"
    b.setSnapshotState(agent: true)
    b.presence.move(to: CGPoint(x: 330, y: 250), rect: CGRect(x: 250, y: 232, width: 160, height: 38), who: "designer", target: "кнопка «Оплатить заказ»")
    b.presence.click(at: CGPoint(x: 330, y: 250))
    try await pane("17-agent-cursor")

    // 2. просьба о разрешении
    b.setSnapshotState(approval: BrowserModel.Approval(who: "designer", title: "Нажать кнопка «Оплатить заказ»?",
                                                       detail: "designer хочет сделать это на «tickets.example.com». Разрешить?"))
    try await pane("17-approval")
    b.setSnapshotState(approval: .some(nil))

    // 3. человек взял управление
    b.setSnapshotState(agent: true, paused: true, takeover: true)
    try await pane("17-takeover")

    // 4. поиск по странице и предложение сохранить вход
    b.setSnapshotState(agent: false, paused: false, takeover: false)
    b.presence.rest()
    b.findOpen = true
    b.findText = "билет"
    b.pendingLogin = CapturedLogin(host: "tickets.example.com", username: "roma@example.com", password: "x", update: false)
    try await pane("17-find-and-save")
    b.findOpen = false
    b.pendingLogin = nil

    // 5. несколько вкладок: значок сайта, вкладка агента со светящейся точкой, файл
    let t2 = b.newTab(configuration: nil)
    t2.title = "Билеты — Москва → Сочи"
    t2.owner = "designer"
    b.setSnapshotState(agentTab: t2.id)
    let t3 = b.newTab(configuration: nil)
    t3.title = "Документы"
    b.select(t3.id)
    try await pane("17-tabs")

    // 6. окно входов
    let vault = b.vault
    _ = try? vault.add(host: "tickets.example.com", username: "roma@example.com", password: "pass-1234-snap")
    _ = try? vault.add(host: "github.com", username: "romankandeevy", password: "pass-5678-snap", label: "личный")
    try await Snap.save(LoginsPopover(app: app, browser: b) {}.environment(\.palette, p), "17-logins", size: CGSize(width: 360, height: 300))
    for l in vault.logins { vault.remove(l.id) }

    // 6б. пустая вкладка: «Макеты» и «Новый макет»
    let blank = b.newTab(configuration: nil)
    b.select(blank.id)
    try await pane("17-new-tab-designs", size: CGSize(width: 640, height: 640))

    // 6в. «Питомцы» с меткой «Бета»
    app.openSettings(.pet)
    try await Snap.save(RootView(app: app), "17-pets-beta", size: CGSize(width: 1280, height: 760))
    app.settingsOpen = false

    // 7. на всё окно
    app.browserOpen = true
    app.browserFull = true
    try await Snap.save(RootView(app: app), "17-full", size: CGSize(width: 1440, height: 820))
    app.browserFull = false
    app.browserOpen = false
}
