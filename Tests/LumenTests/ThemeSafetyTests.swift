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
    app.update {
        $0.appearance = .dark
        $0.userThemes = [UserTheme(id: "user-b", name: "Светлый фон", base: "lumen", darkColors: ThemeOverrides(background: "#E9EEF2"))]
        $0.themeID = "user-b"
    }
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

/// 26.10: четыре готовые темы — все пары текста и акцента читаются, свои цвета поверх готовых не ложатся
@MainActor @Test func builtInThemesAreReadableAndLocked() {
    #expect(Palette.Family.builtIn.map(\.id) == ["lumen", "mono", "corona", "aurora"])
    for f in Palette.Family.builtIn {
        for p in [f.dark, f.light] {
            #expect(p.foreground.contrast(with: p.background) >= 12, "\(f.name): текст")
            #expect(p.mutedFg.contrast(with: p.background) >= 7, "\(f.name): второстепенный")
            #expect(p.faint.contrast(with: p.background) >= 4.5, "\(f.name): тихий")
            #expect(p.glow.contrast(with: p.background) >= 4.5, "\(f.name): акцент")
        }
    }
    // старые свои цвета поверх готовой темы при загрузке пропадают, у своей — переезжают в тему
    let json = ##"{"themeID":"sunset","appearance":"dark","userThemes":[{"id":"user-x","name":"X","hue":200,"tint":0.4}],"themeOverrides":{"lumen|dark":{"background":"#FFFFFF"},"user-x|dark":{"accent":"#FF0000"}}}"##
    let p = try! JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    #expect(p.themeID == "corona")
    #expect(p.themeOverrides.isEmpty)
    #expect(p.userThemes.first?.darkColors?.accent == "#FF0000")
    var q = p
    q.themeID = "lumen"
    #expect(Palette.resolve(q, systemDark: true).background.hexString == "#0A0B0F")
}
