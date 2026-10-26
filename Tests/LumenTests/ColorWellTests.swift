import AppKit
import LumenCore
import SwiftUI
import Testing
@testable import LumenUI

/// Пикер цвета как рукой (26.10): своя тема на основе «Монохрома», колодец «Фон» активен, цвет в системной панели
/// двигается кадр за кадром. Колодец держит то, что в руке; Lumen не меняется, пока не нажали «Сохранить»
@MainActor @Test(.serialized) func colorWellFollowsTheHandAndWaitsForSave() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-well-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update {
        $0.appearance = .light
        $0.userThemes = [UserTheme(id: "user-w", name: "Моя", base: "mono")]
        $0.themeID = "user-w"
    }
    let before = app.palette.background.hexString
    let size = CGRect(x: 0, y: 0, width: 900, height: 1400)
    let host = NSHostingView(rootView: ScrollView { ThemeSettings(app: app).padding(24) }
        .environment(\.palette, app.palette).frame(width: size.width, height: size.height))
    host.frame = size
    let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close(); NSColorPanel.shared.orderOut(nil) }
    for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50)) }

    func wells(_ v: NSView) -> [NSColorWell] { (v as? NSColorWell).map { [$0] } ?? [] + v.subviews.flatMap(wells) }
    let all = wells(host).sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY } // сверху вниз
    #expect(all.count == 4) // фон, карточки, текст, акцент — только у своей темы
    let background = try #require(all.first)
    background.activate(true)
    let panel = NSColorPanel.shared
    let path: [NSColor] = [.init(srgbRed: 0.6, green: 0.6, blue: 0.62, alpha: 1), .init(srgbRed: 0.3, green: 0.3, blue: 0.4, alpha: 1),
                           .init(srgbRed: 0.1, green: 0.12, blue: 0.3, alpha: 1), .init(white: 0, alpha: 1)]
    for c in path {
        panel.color = c
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        #expect(Color(nsColor: background.color).hexString == Color(nsColor: c).hexString)
    }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    // в руке — последний цвет; приложение и сохранённая тема — прежние, пока не нажали «Сохранить»
    #expect(Color(nsColor: background.color).hexString == "#000000")
    #expect(app.prefs.userThemes.first?.lightColors == nil)
    #expect(app.palette.background.hexString == before)
    background.deactivate()
}

/// Готовая тема: на экране «Тема» нет ни одного поля цвета
@MainActor @Test(.serialized) func builtInThemeHasNoColorFields() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-lock-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.themeID = "corona" }
    let size = CGRect(x: 0, y: 0, width: 900, height: 1400)
    let host = NSHostingView(rootView: ScrollView { ThemeSettings(app: app).padding(24) }
        .environment(\.palette, app.palette).frame(width: size.width, height: size.height))
    host.frame = size
    let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50)) }
    func wells(_ v: NSView) -> [NSColorWell] { (v as? NSColorWell).map { [$0] } ?? [] + v.subviews.flatMap(wells) }
    #expect(wells(host).isEmpty)
}
