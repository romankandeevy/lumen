import AppKit
import LumenCore
import SwiftUI

/// Цвета тем из макета (`ui/src/index.css`, OKLCH → sRGB). Обе тёмные.
public struct Palette: Sendable {
    let background, foreground, card, secondary, muted, mutedFg, sidebar, sidebarAccent: Color
    let primary, primaryFg, popover: Color
    /// Свет Люмена: акцент — не заливка, а свечение
    let glow, glowCore, glowSoftBase, borderBase: Color

    var border: Color { borderBase.opacity(0.08) }
    var input: Color { borderBase.opacity(0.11) }
    var sidebarBorder: Color { borderBase.opacity(0.07) }
    var glowSoft: Color { glowSoftBase.opacity(isMono ? 0.12 : 0.18) }
    var glowFaint: Color { glowSoftBase.opacity(isMono ? 0.04 : 0.07) }
    let isMono: Bool

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

    static func of(_ t: Theme) -> Palette { t == .mono ? .mono : .lumen }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.lumen
}

private struct ReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    /// «Меньше движения» из настроек или системы
    var lessMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

// MARK: шрифт Geist (как в макете), лежит в Resources/Fonts

extension Font {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
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
