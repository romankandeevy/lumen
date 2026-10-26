import AppKit
import LumenCore
import SwiftUI

/// Цвета тем (26.10, mockups/themes): четыре готовые — «Люмен», «Монохром», «Корона», «Сияние», у каждой свет и темнота.
/// Готовые не меняются; своя тема — копия готовой со своими фоном, карточками, текстом и акцентом.
public struct Palette: Sendable {
    let background, foreground, card, secondary, muted, mutedFg, sidebar, sidebarAccent: Color
    let primary, primaryFg, popover: Color
    /// Свет Люмена: акцент — не заливка, а свечение
    let glow, glowCore, glowSoftBase, borderBase: Color

    var border: Color { borderBase.opacity((isLight ? 0.12 : 0.13) * borderScale) }
    var input: Color { borderBase.opacity(0.14 * borderScale) }
    var sidebarBorder: Color { borderBase.opacity(0.1 * borderScale) }
    var glowSoft: Color { glowSoftBase.opacity(isMono ? 0.12 : 0.18) }
    var glowFaint: Color { glowSoftBase.opacity(isMono ? 0.04 : 0.07) }
    let isMono: Bool
    var isLight = false
    /// Контраст из настроек: во сколько раз заметнее линии
    var borderScale = 1.0
    /// Разница правок — только знаками +/−, без цвета строк
    var diffSigns = false
    /// Тихий текст (даты, подсказки) — задан темой; nil — выводится из второстепенного
    var faintBase: Color?

    /// Текст и значки на светящейся заливке (кнопка отправки, отметка): на тёмной теме — чёрные, на светлой — белые
    var onGlow: Color { isLight ? .white : .black }
    var scheme: ColorScheme { isLight ? .light : .dark }

    // Оттенки из макета 21.10 (синий шар): выводятся из цветов темы, у «Люмена» совпадают с макетом
    /// Приветствие
    var textStrong: Color { foreground.mixed(with: isLight ? .black : .white, 0.2) }
    /// Текст ответа
    var textBody: Color { foreground.mixed(with: background, 0.05) }
    /// Неактивные названия в «Недавних»
    var textSoft: Color { foreground.mixed(with: background, 0.12) }
    /// Модель и «сколько думать» под полем
    var textControl: Color { foreground.mixed(with: background, 0.2) }
    /// Даты, подсказка в поле, клавиши, стрелки
    var faint: Color { faintBase ?? mutedFg.mixed(with: background, 0.3) }
    /// Акцент заливкой; `glow` — акцент значков, курсора и рамки фокуса
    var accent: Color { glowSoftBase }
    /// Текст на акцентной подложке
    /// У светлой — сам акцент (#2F5BEA): светлый синий на белом не читается, а тёмный из CSS уже подобран
    var accentSoft: Color { isLight ? glow : glow.mixed(with: .white, 0.25) }
    var accentTint: Color { glowSoftBase.opacity(0.12) }
    /// Подложка под курсором у всех «призрачных» кнопок
    var hover: Color { borderBase.opacity(0.06) }
    /// Линия справа у панели и разделители
    var line: Color { borderBase.opacity(0.09 * borderScale) }
    /// Выбранная строка: мягкая подложка сверху вниз и тонкое кольцо внутри — без цветной черты
    var activeFill: LinearGradient {
        // светлый «Люмен»: белая «карточка» (--active-bg)
        if isLight && orbSpec { return LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom) }
        return LinearGradient(colors: [borderBase.opacity(0.075), borderBase.opacity(0.045)], startPoint: .top, endPoint: .bottom)
    }
    var activeRing: Color { borderBase.opacity(0.06) }
    /// Цвета «Люмена» из lumen-theme.css (отправка, поле ввода, пузырь); у других тем — выводятся из их света
    var orbSpec = false

    /// Цвет, которым корона, лучи и звёзды окрашены у других тем (RGB); у «Люмена» — nil: цвета ровно из CSS.
    /// Монохром — нейтральный серый, остальные — свет самой темы
    var markTint: UInt32? {
        if orbSpec { return nil }
        if isMono { return 0xDCDCDC }
        let c = NSColor(glowSoftBase).usingColorSpace(.sRGB) ?? .white
        return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
    }

    /// Поле ввода: сплошное, фон сквозь него не просвечивает (`--composer-bg`): почти чёрное / белое
    var composerFill: Color {
        if isLight { return orbSpec ? .white : card }
        return orbSpec ? Color(hex: 0x050608) : background.mixed(with: .black, 0.5)
    }

    /// Пузырь пользователя: тёмный — стекло с кольцом, светлый «Люмен» — #E9E9E4 без рамки (`--bubble-bg`)
    var bubbleFill: LinearGradient {
        if isLight && orbSpec { return LinearGradient(colors: [Color(hex: 0xE9E9E4), Color(hex: 0xE9E9E4)], startPoint: .top, endPoint: .bottom) }
        return LinearGradient(colors: [borderBase.opacity(0.075), borderBase.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    }
    var bubbleRing: Color { isLight && orbSpec ? .clear : borderBase.opacity(0.07) }

    static let destructive = Color(hex: 0xFF6467)
    static let ok = Color(hex: 0x34D399)

    /// Готовая тема из токенов макета (mockups/themes/themes.html): фон, карточки, выше, текст, второстепенный, тихий, акцент
    static func make(bg: UInt32, surface: UInt32, raised: UInt32, text: UInt32, text2: UInt32, faint: UInt32,
                     accent: UInt32, accentFill: UInt32, accentCore: UInt32, sidebar: UInt32, line: UInt32,
                     light: Bool, mono: Bool = false) -> Palette {
        var p = Palette(
            background: Color(hex: bg), foreground: Color(hex: text), card: Color(hex: surface),
            secondary: Color(hex: raised), muted: Color(hex: surface).mixed(with: Color(hex: raised), 0.5), mutedFg: Color(hex: text2),
            sidebar: Color(hex: sidebar), sidebarAccent: Color(hex: raised),
            primary: Color(hex: text), primaryFg: Color(hex: bg), popover: Color(hex: light ? 0xFFFFFF : surface),
            glow: Color(hex: accent), glowCore: Color(hex: accentCore), glowSoftBase: Color(hex: accentFill),
            borderBase: Color(hex: line), isMono: mono, isLight: light)
        p.faintBase = Color(hex: faint)
        return p
    }

    /// «Люмен»: затмение — чёрное небо и синяя корона; знак и небо из lumen-theme.css
    static let lumen: Palette = {
        var p = make(bg: 0x0A0B0F, surface: 0x15171D, raised: 0x1E2129, text: 0xF1F3F8, text2: 0xB8BECE, faint: 0x8B91A3,
                     accent: 0x7FA0FF, accentFill: 0x5B86FF, accentCore: 0xDCE5FF, sidebar: 0x101116, line: 0xFFFFFF, light: false)
        p.orbSpec = true
        return p
    }()

    /// «Люмен» при свете: тёплая бумага и синие чернила (#2F5BEA — светлый синий из тёмной на белом не читается)
    static let light: Palette = {
        var p = make(bg: 0xF7F7F4, surface: 0xFFFFFF, raised: 0xEEEEE9, text: 0x15171C, text2: 0x474C59, faint: 0x686D7B,
                     accent: 0x2F5BEA, accentFill: 0x2F5BEA, accentCore: 0xE4EBFF, sidebar: 0xEFEFEB, line: 0x141826, light: true)
        p.orbSpec = true
        return p
    }()

    /// «Монохром»: чёрное и белое, как Пульт; акцент — сам свет
    static let mono = make(bg: 0x0C0C0C, surface: 0x181818, raised: 0x222222, text: 0xF5F5F5, text2: 0xBDBDBD, faint: 0x919191,
                           accent: 0xFFFFFF, accentFill: 0xF5F5F5, accentCore: 0xFFFFFF, sidebar: 0x060606, line: 0xFFFFFF, light: false, mono: true)
    static let monoLight = make(bg: 0xFAFAFA, surface: 0xFFFFFF, raised: 0xEFEFEF, text: 0x111111, text2: 0x4A4A4A, faint: 0x6B6B6B,
                                accent: 0x111111, accentFill: 0x111111, accentCore: 0x555555, sidebar: 0xF3F3F3, line: 0x000000, light: true, mono: true)

    /// «Корона»: свет солнца из-за луны — золото на тёплом угле; при свете — песок и янтарь
    static let corona = make(bg: 0x0E0B07, surface: 0x1A150E, raised: 0x251E14, text: 0xF7EFE3, text2: 0xD2C3AA, faint: 0xA0927C,
                             accent: 0xF2B544, accentFill: 0xE9A62A, accentCore: 0xFFE9B8, sidebar: 0x0A0805, line: 0xFFECC8, light: false)
    static let coronaLight = make(bg: 0xFBF7F0, surface: 0xFFFFFF, raised: 0xF2EADC, text: 0x1E1810, text2: 0x56493A, faint: 0x75685A,
                                  accent: 0x9A5B07, accentFill: 0xB86F0B, accentCore: 0xFBE6C4, sidebar: 0xF5EEE3, line: 0x3C280A, light: true)

    /// «Сияние»: северное небо — зелёный свет над тёмной водой; при свете — утро у моря
    static let aurora = make(bg: 0x061110, surface: 0x0E1C1A, raised: 0x152724, text: 0xECF7F4, text2: 0xAFCBC4, faint: 0x82A59D,
                             accent: 0x3DDC97, accentFill: 0x22C784, accentCore: 0xC9F7E1, sidebar: 0x040C0B, line: 0xC8FFEB, light: false)
    static let auroraLight = make(bg: 0xF3F8F6, surface: 0xFFFFFF, raised: 0xE5EFEB, text: 0x0F1F1C, text2: 0x3D5852, faint: 0x5A7670,
                                  accent: 0x0B7D55, accentFill: 0x0E8A5F, accentCore: 0xD2F2E4, sidebar: 0xEAF2EF, line: 0x0A3228, light: true)

    /// Старая своя тема (до 26.10): всё считается от оттенка; tint — насколько фон и панели окрашены этим оттенком
    static func custom(_ c: CustomTheme) -> Palette {
        let h = c.hue / 360
        let s = 0.04 + 0.22 * c.tint
        func hsb(_ sat: Double, _ b: Double) -> Color { Color(hue: h, saturation: min(1, sat), brightness: min(1, b)) }
        if c.dark {
            let d = 0.12 + 0.55 * c.tint
            return Palette(
                background: hsb(d, 0.075), foreground: hsb(0.04, 0.95), card: hsb(d * 0.9, 0.13),
                secondary: hsb(d * 0.8, 0.2), muted: hsb(d * 0.8, 0.17), mutedFg: hsb(0.1, 0.74),
                sidebar: hsb(d, 0.05), sidebarAccent: hsb(d * 0.8, 0.14),
                primary: hsb(0.22, 0.98), primaryFg: hsb(0.6, 0.1), popover: hsb(d * 0.8, 0.13),
                glow: hsb(0.62, 1), glowCore: hsb(0.14, 1), glowSoftBase: hsb(0.68, 0.96),
                borderBase: hsb(0.18, 0.97), isMono: false)
        }
        return Palette(
            background: hsb(s * 0.25, 0.985), foreground: hsb(0.18, 0.12), card: hsb(0, 1),
            secondary: hsb(s * 0.3, 0.94), muted: hsb(s * 0.25, 0.955), mutedFg: hsb(0.1, 0.38),
            sidebar: hsb(s * 0.3, 0.96), sidebarAccent: hsb(s * 0.4, 0.91),
            primary: hsb(0.18, 0.12), primaryFg: hsb(0, 1), popover: hsb(0, 1),
            glow: hsb(0.82, 0.76), glowCore: hsb(0.2, 1), glowSoftBase: hsb(0.72, 0.9),
            borderBase: hsb(0.3, 0.12), isMono: false, isLight: true)
    }

    /// Тема целиком: цвета для светлого и тёмного. Свет (`Appearance`) выбирает, какие из них сейчас
    struct Family: Identifiable {
        let id: String
        let name: String
        let note: String
        let dark: Palette
        let light: Palette
        var user = false

        func palette(dark isDark: Bool) -> Palette { isDark ? dark : light }

        /// Четыре готовые — про свет на небе, как знак Lumen. Не меняются
        static let builtIn: [Family] = [
            Family(id: "lumen", name: "Люмен", note: "Затмение: чёрное небо, синяя корона", dark: .lumen, light: .light),
            Family(id: "mono", name: "Монохром", note: "Чёрное и белое, как Пульт", dark: .mono, light: .monoLight),
            Family(id: "corona", name: "Корона", note: "Свет солнца из-за луны: золото и янтарь", dark: .corona, light: .coronaLight),
            Family(id: "aurora", name: "Сияние", note: "Северное небо: зелёный свет над водой", dark: .aurora, light: .auroraLight),
        ]

        static func isBuiltIn(_ id: String) -> Bool { builtIn.contains { $0.id == id } }

        /// Основа своей темы — без её своих цветов (от неё поля показывают значения по умолчанию)
        static func base(of t: UserTheme) -> Family {
            if let b = t.base, let f = builtIn.first(where: { $0.id == b }) { return f }
            return Family(id: t.id, name: t.name, note: "Своя тема",
                          dark: .custom(CustomTheme(dark: true, hue: t.hue, tint: t.tint)),
                          light: .custom(CustomTheme(dark: false, hue: t.hue, tint: t.tint)), user: true)
        }

        static func of(_ t: UserTheme) -> Family {
            let b = base(of: t)
            let baseName = t.base.flatMap { id in builtIn.first { $0.id == id }?.name }
            return Family(id: t.id, name: t.name.isEmpty ? "Без названия" : t.name,
                          note: baseName.map { "Своя · на основе «\($0)»" } ?? "Своя тема",
                          dark: b.dark.with(t.colors(dark: true)), light: b.light.with(t.colors(dark: false)), user: true)
        }

        static func all(_ prefs: Preferences) -> [Family] { builtIn + prefs.userThemes.map(of) }

        static func find(_ id: String, _ prefs: Preferences) -> Family {
            let id = Preferences.renamedThemes[id] ?? id
            return all(prefs).first { $0.id == id } ?? builtIn[0]
        }
    }

    /// Тема для света: при раздельных режимах у тёмного своя
    static func themeID(_ prefs: Preferences, dark: Bool) -> String {
        dark && prefs.separateModes ? (prefs.darkThemeID ?? prefs.themeID) : prefs.themeID
    }

    static func overridesKey(_ id: String, dark: Bool) -> String { id + (dark ? "|dark" : "|light") }

    /// Цвета окна: выбранная тема при выбранном свете (системный — как сейчас в macOS), поверх — свои цвета и контраст
    static func resolve(_ prefs: Preferences, systemDark: Bool) -> Palette {
        let dark = prefs.appearance == .system ? systemDark : prefs.appearance == .dark // то же, что AppModel.isDarkMode
        // свои цвета — только у своих тем, они уже внутри Family.of; готовые темы не меняются
        let p = Family.find(themeID(prefs, dark: dark), prefs).palette(dark: dark)
        return p.with(contrast: prefs.contrast, diffSigns: prefs.diffMarkers == .signs)
    }

    /// Свои цвета: акцент — свет; фон — фон, а карточки и панели выводятся из него; текст — текст и подписи
    func with(_ o: ThemeOverrides) -> Palette {
        guard !o.isEmpty else { return self }
        let bg = o.background.flatMap(Color.init(hexString:)) ?? background
        var glowC = o.accent.flatMap(Color.init(hexString:)) ?? glow
        let newBg = o.background != nil, newFg = o.foreground != nil
        // Светлая она или тёмная — решает яркость фона (25.10: светлый фон у тёмной темы давал белое на белом и «слетало»)
        let light = newBg ? bg.luminance > 0.4 : isLight
        var fg = o.foreground.flatMap(Color.init(hexString:)) ?? foreground
        // Текст обязан читаться на фоне, какие бы цвета ни выбрали: иначе берём чернила под яркость фона
        if (!newFg && light != isLight) || fg.contrast(with: bg) < 3 {
            fg = light ? Color(hex: 0x15171C) : Color(hex: 0xF1F3F8)
        }
        let newFgEffective = newFg || fg.hexString != foreground.hexString
        // акцент тоже обязан быть виден: им рисуются значки выбранного, рамка фокуса, ссылки (26.10: пропала иконка «Темы»).
        // Сливается с фоном — светлеет (или темнеет) по шагам, пока не станет заметен
        if glowC.contrast(with: bg) < 3 {
            let toward: Color = light ? .black : .white
            var k = 0.15
            var c = glowC.mixed(with: toward, k)
            while c.contrast(with: bg) < 3, k < 0.95 { k += 0.1; c = glowC.mixed(with: toward, k) }
            glowC = c
        }
        let accentChanged = o.accent != nil || glowC.hexString != glow.hexString
        let surfaceC = o.surface.flatMap(Color.init(hexString:))
        var p = Palette(
            background: bg, foreground: fg,
            card: surfaceC ?? (newBg ? bg.mixed(with: fg, 0.06) : card),
            secondary: surfaceC.map { $0.mixed(with: fg, 0.07) } ?? (newBg ? bg.mixed(with: fg, 0.11) : secondary),
            muted: surfaceC.map { $0.mixed(with: fg, 0.035) } ?? (newBg ? bg.mixed(with: fg, 0.08) : muted),
            mutedFg: newFgEffective || newBg ? fg.mixed(with: bg, 0.38) : mutedFg,
            sidebar: newBg ? bg.mixed(with: light ? .white : .black, light ? 0.4 : 0.35) : sidebar,
            sidebarAccent: surfaceC.map { $0.mixed(with: fg, 0.07) } ?? (newBg ? bg.mixed(with: fg, 0.07) : sidebarAccent),
            primary: newFgEffective ? fg : primary, primaryFg: newBg ? bg : primaryFg,
            popover: surfaceC ?? (newBg ? bg.mixed(with: fg, 0.05) : popover),
            glow: glowC, glowCore: accentChanged ? glowC.mixed(with: .white, 0.7) : glowCore,
            glowSoftBase: accentChanged ? glowC : glowSoftBase,
            borderBase: newFgEffective ? fg : borderBase, isMono: isMono, isLight: light)
        p.borderScale = borderScale
        p.diffSigns = diffSigns
        // тихий текст: свой у темы, пока фон и текст её же; иначе — выводится из нового текста
        p.faintBase = newFgEffective || newBg ? nil : faintBase
        // свой акцент — и шар из него
        p.orbSpec = orbSpec && o.accent == nil
        return p
    }

    /// Контраст 0…100 (50 — как задумано): резче или мягче линии и подписи
    func with(contrast: Double, diffSigns: Bool) -> Palette {
        let k = (contrast - 50) / 50 // −1…1
        let muted = k > 0 ? mutedFg.mixed(with: foreground, 0.55 * k) : mutedFg.mixed(with: background, 0.35 * -k)
        var p = Palette(background: background, foreground: foreground, card: card, secondary: secondary, muted: self.muted,
                        mutedFg: muted, sidebar: sidebar, sidebarAccent: sidebarAccent, primary: primary, primaryFg: primaryFg,
                        popover: popover, glow: glow, glowCore: glowCore, glowSoftBase: glowSoftBase, borderBase: borderBase,
                        isMono: isMono, isLight: isLight)
        p.borderScale = max(0.4, 1 + k * 1.2)
        p.diffSigns = diffSigns
        p.orbSpec = orbSpec
        p.faintBase = faintBase.map { k > 0 ? $0.mixed(with: foreground, 0.45 * k) : $0.mixed(with: background, 0.3 * -k) }
        return p
    }

    static func of(_ t: Theme, custom: CustomTheme = CustomTheme()) -> Palette {
        switch t {
        case .lumen: .lumen
        case .mono: .mono
        case .light: .light
        case .custom: .custom(custom)
        }
    }
}

extension Color {
    /// «#1E1A15» или «1E1A15»; не цвет — nil
    init?(hexString s: String) {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        self.init(hex: v)
    }

    /// «#RRGGBB»
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// Относительная яркость по WCAG: 0 — чёрный, 1 — белый
    var luminance: Double {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    /// Контраст двух цветов по WCAG: 1 — одинаковые, 21 — чёрный с белым; читаемый текст — от 4,5
    func contrast(with other: Color) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Смесь: t = 0 — этот цвет, 1 — другой
    func mixed(with other: Color, _ t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black, b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let k = CGFloat(min(1, max(0, t)))
        return Color(.sRGB, red: Double(a.redComponent + (b.redComponent - a.redComponent) * k),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * k),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * k),
                     opacity: Double(a.alphaComponent + (b.alphaComponent - a.alphaComponent) * k))
    }

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.lumen
}

private struct ChatTextKey: EnvironmentKey {
    static let defaultValue = ChatText()
}

/// Текст переписки из настроек «Шрифты и масштаб»: шрифт и множитель размера
struct ChatText: Equatable {
    var font = ChatFont.geist
    var scale: Double = 1
    /// Размер кода в блоках кода
    var code: Double = 12.5
}

private struct ReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var chatText: ChatText {
        get { self[ChatTextKey.self] }
        set { self[ChatTextKey.self] = newValue }
    }

    /// «Меньше движения» из настроек или системы
    var lessMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

// MARK: шрифты. Интерфейс — системный (SF Pro, макет 21.10); Geist остался выбором для текста переписки,
// Literata — только приветствие. Оба лежат в Resources/Fonts

extension Font {
    /// Масштаб шрифтов интерфейса (Настройки → Тема → Расширенные): 1 = базовые 14 pt
    nonisolated(unsafe) static var uiScale: CGFloat = 1

    /// Шрифт интерфейса. Имя осталось от Geist: так он зовётся по всему коду
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * uiScale, weight: weight)
    }

    /// Geist для текста переписки («Шрифты и масштаб» → Geist)
    static func geistFace(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = GeistFace.name(weight)
        // без бандла (swift run) шрифта нет — системный того же веса
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
    }

    /// Приветствие: Literata с оптическим размером под кегль (opsz 7…72), вес 400
    @MainActor static func greeting(_ size: CGFloat) -> Font {
        Font(Greeting.font(size * uiScale))
    }
}

enum GeistFace {
    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Geist-Medium"
        case .semibold: "Geist-SemiBold"
        case .bold, .heavy, .black: "Geist-Bold"
        default: "Geist-Regular"
        }
    }
}

enum Greeting {
    @MainActor private static var cache: [CGFloat: NSFont] = [:]

    /// Оси variable-шрифта: «opsz» и «wght» по их 4-буквенным тегам
    @MainActor static func font(_ size: CGFloat) -> NSFont {
        if let f = cache[size] { return f }
        func tag(_ s: String) -> NSNumber { NSNumber(value: s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
        let f: NSFont
        if let base = NSFont(name: "Literata", size: size) {
            let d = base.fontDescriptor.addingAttributes([
                NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [tag("opsz"): min(72, max(7, size)), tag("wght"): 400],
            ])
            f = NSFont(descriptor: d, size: size) ?? base
        } else {
            // шрифта нет (swift run) — системный с засечками
            let sys = NSFont.systemFont(ofSize: size)
            f = sys.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? sys
        }
        cache[size] = f
        return f
    }
}

// MARK: иконки Lucide (как в макете), SVG в Resources/Icons

/// Иконка Lucide: обводка цветом текста вокруг, размер в точках (size-4 = 16)
struct Icon: View {
    let name: String
    var size: CGFloat = 16

    init(_ name: String, _ size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// В бандле — Contents/Resources/Icons; в тестах и снимках — папка из LUMEN_ICONS
    @MainActor static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        var url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
        if url == nil, let dir = ProcessInfo.processInfo.environment["LUMEN_ICONS"] {
            url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).svg")
        }
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[name] = img
        return img
    }

    var body: some View {
        Group {
            if let img = Self.image(name) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: высота строки как в CSS (line-height): Text в SwiftUI ниже, чем в браузере

extension View {
    /// Шрифт Geist и высота строки: `.tw(14, lh: 20)` = text-sm, `.tw(15, lh: 24.75)` = text-[0.9375rem] leading-[1.65]
    func tw(_ size: CGFloat, _ weight: Font.Weight = .regular, lh: CGFloat) -> some View {
        let natural = LineMetrics.height(size * Font.uiScale, weight)
        let extra = max(0, lh * Font.uiScale - natural)
        return self.font(.geist(size, weight))
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

/// Текст переписки: размер и высота строки как в макете, умноженные на масштаб; шрифт — выбранный
private struct ChatTextStyle: ViewModifier {
    let size: CGFloat
    let lh: CGFloat
    @Environment(\.chatText) private var t

    func body(content: Content) -> some View {
        let s = size * t.scale, l = lh * t.scale
        switch t.font {
        case .geist:
            let natural = LineMetrics.geistHeight(s * Font.uiScale)
            let extra = max(0, l * Font.uiScale - natural)
            content.font(.geistFace(s * Font.uiScale)).lineSpacing(extra).padding(.vertical, extra / 2)
        case .system, .serif, .mono:
            let design: Font.Design = t.font == .serif ? .serif : (t.font == .mono ? .monospaced : .default)
            let natural = ceil(NSFont.systemFont(ofSize: s).ascender - NSFont.systemFont(ofSize: s).descender + NSFont.systemFont(ofSize: s).leading)
            let extra = max(0, l - natural)
            content.font(.system(size: t.font == .mono ? s * 0.92 : s, design: design))
                .lineSpacing(extra).padding(.vertical, extra / 2)
        }
    }
}

extension View {
    /// Как `.tw`, но для текста переписки: учитывает «Шрифты и масштаб»
    func chatTw(_ size: CGFloat, lh: CGFloat) -> some View { modifier(ChatTextStyle(size: size, lh: lh)) }
}

enum LineMetrics {
    @MainActor private static var cache: [String: CGFloat] = [:]

    /// Естественная высота строки шрифта интерфейса (как её рисует Text)
    static func height(_ size: CGFloat, _ weight: Font.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight.ns)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// То же для Geist в переписке
    static func geistHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont(name: GeistFace.name(.regular), size: size) ?? .systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }
}

extension Font.Weight {
    var ns: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
