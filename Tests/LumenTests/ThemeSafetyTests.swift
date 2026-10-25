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
