import AppKit
import LumenCore
import SwiftUI

/// Цвета тем: «Люмен» и «Монохром» — из макета (`ui/src/index.css`, OKLCH → sRGB), «Светлая» и своя — от них.
public struct Palette: Sendable {
    let background, foreground, card, secondary, muted, mutedFg, sidebar, sidebarAccent: Color
    let primary, primaryFg, popover: Color
    /// Свет Люмена: акцент — не заливка, а свечение
    let glow, glowCore, glowSoftBase, borderBase: Color

    var border: Color { borderBase.opacity(0.08 * borderScale) }
    var input: Color { borderBase.opacity(0.11 * borderScale) }
    var sidebarBorder: Color { borderBase.opacity(0.07 * borderScale) }
    var glowSoft: Color { glowSoftBase.opacity(isMono ? 0.12 : 0.18) }
    var glowFaint: Color { glowSoftBase.opacity(isMono ? 0.04 : 0.07) }
    let isMono: Bool
    var isLight = false
    /// Контраст из настроек: во сколько раз заметнее линии
    var borderScale = 1.0
    /// Разница правок — только знаками +/−, без цвета строк
    var diffSigns = false

    /// Текст и значки на светящейся заливке (кнопка отправки, отметка): на тёмной теме — чёрные, на светлой — белые
    var onGlow: Color { isLight ? .white : .black }
    var scheme: ColorScheme { isLight ? .light : .dark }

    static let destructive = Color(hex: 0xFF6467)
    static let ok = Color(hex: 0x34D399)

    static let lumen = Palette(
        background: Color(hex: 0x0C0A07), foreground: Color(hex: 0xF0EBE0), card: Color(hex: 0x15110D),
        secondary: Color(hex: 0x221D17), muted: Color(hex: 0x1F1B16), mutedFg: Color(hex: 0x9F978B),
        sidebar: Color(hex: 0x070504), sidebarAccent: Color(hex: 0x1A1510),
        primary: Color(hex: 0xFAE6BB), primaryFg: Color(hex: 0x1C140C), popover: Color(hex: 0x1A1510),
        glow: Color(hex: 0xFEC766), glowCore: Color(hex: 0xFFF8DB), glowSoftBase: Color(hex: 0xF5B75B),
        borderBase: Color(hex: 0xF7E2B8), isMono: false)

    static let mono = Palette(
        background: Color(hex: 0x0C0C0C), foreground: Color(hex: 0xF5F5F5), card: Color(hex: 0x141414),
        secondary: Color(hex: 0x222222), muted: Color(hex: 0x1F1F1F), mutedFg: Color(hex: 0x929292),
        sidebar: Color(hex: 0x060606), sidebarAccent: Color(hex: 0x181818),
        primary: Color(hex: 0xF5F5F5), primaryFg: Color(hex: 0x0D0D0D), popover: Color(hex: 0x161616),
        glow: Color(hex: 0xE4E4E4), glowCore: Color(hex: 0xFFFFFF), glowSoftBase: Color(hex: 0xFFFFFF),
        borderBase: Color(hex: 0xFFFFFF), isMono: true)

    /// Светлая: тёплая бумага, тёмные чернила, янтарный свет темнее — чтобы читался на белом
    static let light = Palette(
        background: Color(hex: 0xFBF9F5), foreground: Color(hex: 0x1E1A15), card: Color(hex: 0xFFFFFF),
        secondary: Color(hex: 0xF0ECE4), muted: Color(hex: 0xF3F0EA), mutedFg: Color(hex: 0x716A60),
        sidebar: Color(hex: 0xF4F1EB), sidebarAccent: Color(hex: 0xE8E3D9),
        primary: Color(hex: 0x1E1A15), primaryFg: Color(hex: 0xFFFFFF), popover: Color(hex: 0xFFFFFF),
        glow: Color(hex: 0xC97A12), glowCore: Color(hex: 0xFFF1D0), glowSoftBase: Color(hex: 0xE8A23A),
        borderBase: Color(hex: 0x2A2016), isMono: false, isLight: true)

    /// Своя тема: всё считается от оттенка; tint — насколько фон и панели окрашены этим оттенком
    static func custom(_ c: CustomTheme) -> Palette {
        let h = c.hue / 360
        let s = 0.04 + 0.22 * c.tint
        func hsb(_ sat: Double, _ b: Double) -> Color { Color(hue: h, saturation: min(1, sat), brightness: min(1, b)) }
        if c.dark {
            return Palette(
                background: hsb(s * 0.6, 0.045), foreground: hsb(0.04, 0.95), card: hsb(s * 0.6, 0.075),
                secondary: hsb(s * 0.5, 0.13), muted: hsb(s * 0.5, 0.115), mutedFg: hsb(0.08, 0.63),
                sidebar: hsb(s * 0.6, 0.03), sidebarAccent: hsb(s * 0.55, 0.1),
                primary: hsb(0.22, 0.98), primaryFg: hsb(0.6, 0.1), popover: hsb(s * 0.55, 0.1),
                glow: hsb(0.62, 1), glowCore: hsb(0.14, 1), glowSoftBase: hsb(0.68, 0.96),
                borderBase: hsb(0.18, 0.97), isMono: false)
        }
        return Palette(
            background: hsb(s * 0.25, 0.985), foreground: hsb(0.18, 0.12), card: hsb(0, 1),
            secondary: hsb(s * 0.3, 0.94), muted: hsb(s * 0.25, 0.955), mutedFg: hsb(0.1, 0.45),
            sidebar: hsb(s * 0.3, 0.96), sidebarAccent: hsb(s * 0.4, 0.91),
            primary: hsb(0.18, 0.12), primaryFg: hsb(0, 1), popover: hsb(0, 1),
            glow: hsb(0.82, 0.76), glowCore: hsb(0.2, 1), glowSoftBase: hsb(0.72, 0.9),
            borderBase: hsb(0.3, 0.12), isMono: false, isLight: true)
    }

    /// Монохром при свете: белая бумага, чёрные чернила, «свет» — графит
    static let monoLight = Palette(
        background: Color(hex: 0xFAFAFA), foreground: Color(hex: 0x111111), card: Color(hex: 0xFFFFFF),
        secondary: Color(hex: 0xECECEC), muted: Color(hex: 0xF1F1F1), mutedFg: Color(hex: 0x6B6B6B),
        sidebar: Color(hex: 0xF3F3F3), sidebarAccent: Color(hex: 0xE4E4E4),
        primary: Color(hex: 0x111111), primaryFg: Color(hex: 0xFFFFFF), popover: Color(hex: 0xFFFFFF),
        glow: Color(hex: 0x1C1C1C), glowCore: Color(hex: 0x555555), glowSoftBase: Color(hex: 0x000000),
        borderBase: Color(hex: 0x000000), isMono: true, isLight: true)

    /// Тема целиком: цвета для светлого и тёмного. Свет (`Appearance`) выбирает, какие из них сейчас
    struct Family: Identifiable {
        let id: String
        let name: String
        let note: String
        let dark: Palette
        let light: Palette
        var user = false

        func palette(dark isDark: Bool) -> Palette { isDark ? dark : light }

        /// Встроенные: у каждой — своя идея света (лампа, полдень и полночь, закат, северное сияние, луна)
        static let builtIn: [Family] = [
            Family(id: "lumen", name: "Люмен", note: "Тёплый свет лампы", dark: .lumen, light: .light),
            Family(id: "mono", name: "Монохром", note: "Чёрное и белое, как Пульт", dark: .mono, light: .monoLight),
            hue("sunset", "Закат", "Медь и угли вечернего неба", 16, 0.45),
            hue("aurora", "Сияние", "Зелёный свет северной ночи", 162, 0.4),
            hue("moon", "Луна", "Холодный ровный свет", 218, 0.22),
        ]

        static func hue(_ id: String, _ name: String, _ note: String, _ h: Double, _ tint: Double, user: Bool = false) -> Family {
            Family(id: id, name: name, note: note,
                   dark: .custom(CustomTheme(dark: true, hue: h, tint: tint)),
                   light: .custom(CustomTheme(dark: false, hue: h, tint: tint)), user: user)
        }

        static func of(_ t: UserTheme) -> Family {
            hue(t.id, t.name.isEmpty ? "Без названия" : t.name, "Своя тема", t.hue, t.tint, user: true)
        }

        static func all(_ prefs: Preferences) -> [Family] { builtIn + prefs.userThemes.map(of) }

        static func find(_ id: String, _ prefs: Preferences) -> Family {
            all(prefs).first { $0.id == id } ?? builtIn[0]
        }
    }

    /// Тема для света: при раздельных режимах у тёмного своя
    static func themeID(_ prefs: Preferences, dark: Bool) -> String {
        dark && prefs.separateModes ? (prefs.darkThemeID ?? prefs.themeID) : prefs.themeID
    }

    static func overridesKey(_ id: String, dark: Bool) -> String { id + (dark ? "|dark" : "|light") }

    /// Цвета окна: выбранная тема при выбранном свете (системный — как сейчас в macOS), поверх — свои цвета и контраст
    static func resolve(_ prefs: Preferences, systemDark: Bool) -> Palette {
        let dark = prefs.appearance == .system ? systemDark : prefs.appearance == .dark
        let id = themeID(prefs, dark: dark)
        var p = Family.find(id, prefs).palette(dark: dark)
        if let o = prefs.themeOverrides[overridesKey(id, dark: dark)] { p = p.with(o) }
        return p.with(contrast: prefs.contrast, diffSigns: prefs.diffMarkers == .signs)
    }

    /// Свои цвета: акцент — свет; фон — фон, а карточки и панели выводятся из него; текст — текст и подписи
    func with(_ o: ThemeOverrides) -> Palette {
        let bg = o.background.flatMap(Color.init(hexString:)) ?? background
        let fg = o.foreground.flatMap(Color.init(hexString:)) ?? foreground
        let glowC = o.accent.flatMap(Color.init(hexString:)) ?? glow
        let newBg = o.background != nil, newFg = o.foreground != nil
        var p = Palette(
            background: bg, foreground: fg,
            card: newBg ? bg.mixed(with: fg, 0.035) : card,
            secondary: newBg ? bg.mixed(with: fg, 0.1) : secondary,
            muted: newBg ? bg.mixed(with: fg, 0.08) : muted,
            mutedFg: newFg || newBg ? fg.mixed(with: bg, 0.42) : mutedFg,
            sidebar: newBg ? bg.mixed(with: isLight ? .white : .black, isLight ? 0.4 : 0.35) : sidebar,
            sidebarAccent: newBg ? bg.mixed(with: fg, 0.07) : sidebarAccent,
            primary: newFg ? fg : primary, primaryFg: newBg ? bg : primaryFg,
            popover: newBg ? bg.mixed(with: fg, 0.05) : popover,
            glow: glowC, glowCore: o.accent != nil ? glowC.mixed(with: .white, 0.7) : glowCore,
            glowSoftBase: o.accent != nil ? glowC : glowSoftBase,
            borderBase: newFg ? fg : borderBase, isMono: isMono, isLight: isLight)
        p.borderScale = borderScale
        p.diffSigns = diffSigns
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

// MARK: шрифт Geist (как в макете), лежит в Resources/Fonts

extension Font {
    /// Масштаб шрифтов интерфейса (Настройки → Тема → Расширенные): 1 = базовые 14 pt
    nonisolated(unsafe) static var uiScale: CGFloat = 1

    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let size = size * uiScale
        let name: String
        switch weight {
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        case .bold, .heavy, .black: name = "Geist-Bold"
        default: name = "Geist-Regular"
        }
        // без бандла (swift run) шрифта нет — системный того же веса
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: weight)
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
        case .geist: content.tw(s, lh: l)
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

    /// Естественная высота строки шрифта (как её рисует Text)
    static func height(_ size: CGFloat, _ weight: Font.Weight) -> CGFloat {
        let name: String
        switch weight {
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        case .bold, .heavy, .black: name = "Geist-Bold"
        default: name = "Geist-Regular"
        }
        let font = NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }
}
