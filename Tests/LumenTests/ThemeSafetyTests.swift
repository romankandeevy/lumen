import SwiftUI
import Testing
import LumenCore
@testable import LumenUI

/// 25.10: светлый фон у тёмной темы давал белое на белом — приложение становилось нечитаемым, а выхода не было
@MainActor @Test func lightBackgroundOnDarkThemeStaysReadable() {
    var o = ThemeOverrides()
    o.background = "#E9EEF2"
    let p = Palette.lumen.with(o)
    #expect(p.isLight)
    #expect(p.foreground.contrast(with: p.background) >= 7)
    #expect(p.mutedFg.contrast(with: p.background) >= 3)
}

@MainActor @Test func unreadableTextColorIsReplaced() {
    var o = ThemeOverrides()
    o.background = "#101010"
    o.foreground = "#161616"
    let p = Palette.lumen.with(o)
    #expect(p.foreground.contrast(with: p.background) >= 4.5)
}

@MainActor @Test func darkBackgroundOnLightThemeFlipsToDark() {
    var o = ThemeOverrides()
    o.background = "#0B0B12"
    let p = Palette.light.with(o)
    #expect(!p.isLight)
    #expect(p.foreground.contrast(with: p.background) >= 7)
}

@MainActor @Test func goodOverridesAreKept() {
    var o = ThemeOverrides()
    o.background = "#000000"
    o.foreground = "#FFFFFF"
    let p = Palette.lumen.with(o)
    #expect(p.foreground.hexString == "#FFFFFF")
    #expect(p.background.hexString == "#000000")
}

/// 26.10: светлый фон в тёмном режиме переворачивал палитру, и «Тема» начинала читать и писать цвета светлого режима —
/// пикер показывал белый, а фон в окне не менялся. Режим — по настройке, не по цвету
@MainActor @Test func lightBackgroundDoesNotSwitchEditedMode() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-mode-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.update { $0.appearance = .dark; $0.themeOverrides[Palette.overridesKey($0.themeID, dark: true)] = ThemeOverrides(background: "#E9EEF2") }
    #expect(app.palette.isLight)          // палитра светлая — текст тёмный, читается
    #expect(app.isDarkMode)               // но правим по-прежнему цвета тёмного режима
    #expect(app.palette.background.hexString == "#E9EEF2")
}

/// 26.10: «Монохром» при свете с чёрным фоном — графитовый акцент сливался, пропали значки выбранного
@MainActor @Test func accentStaysVisibleOnOverriddenBackground() {
    var o = ThemeOverrides()
    o.background = "#000000"
    o.foreground = "#000000"
    let p = Palette.monoLight.with(o)
    #expect(p.glow.contrast(with: p.background) >= 3)
    #expect(p.foreground.contrast(with: p.background) >= 4.5)
    var dim = ThemeOverrides()
    dim.accent = "#0E0E10"
    #expect(Palette.lumen.with(dim).glow.contrast(with: Palette.lumen.background) >= 3)
}
