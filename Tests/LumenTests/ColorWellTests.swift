import AppKit
import LumenCore
import SwiftUI
import Testing
@testable import LumenUI

/// Пикер цвета как рукой (26.10: «пикер сломался»): экран «Тема» в окне, колодец «Фон» активен,
/// цвет в системной панели двигается кадр за кадром. Цвет из темы не должен уводить колодец, а в тему уходит последний выбор
@MainActor @Test(.serialized) func colorWellFollowsTheHandAndSavesLastColor() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-well-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.appearance = .light; $0.themeID = "mono" }
    let size = CGRect(x: 0, y: 0, width: 900, height: 1200)
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
    #expect(all.count == 3) // акцент, фон, текст
    let background = try #require(all.dropFirst().first)
    background.activate(true)
    let panel = NSColorPanel.shared
    // «тянем» по кругу: несколько кадров подряд, последний — тёмно-синий
    let path: [NSColor] = [.init(srgbRed: 0.6, green: 0.6, blue: 0.62, alpha: 1), .init(srgbRed: 0.3, green: 0.3, blue: 0.4, alpha: 1),
                           .init(srgbRed: 0.1, green: 0.12, blue: 0.3, alpha: 1)]
    for c in path {
        panel.color = c
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        // колодец держит то, что в руке, а не то, что вернула тема
        #expect(Color(nsColor: background.color).hexString == Color(nsColor: c).hexString)
    }
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let saved = app.prefs.themeOverrides[Palette.overridesKey("mono", dark: false)]?.background
    #expect(saved == Color(nsColor: path.last!).hexString)
    #expect(Color(nsColor: background.color).hexString == saved)
    // тёмный фон в светлом режиме: палитра тёмная, текст читается, а правим всё ещё светлый режим
    #expect(!app.palette.isLight && app.palette.foreground.contrast(with: app.palette.background) >= 4.5)
    #expect(!app.isDarkMode)
    background.deactivate()
}
