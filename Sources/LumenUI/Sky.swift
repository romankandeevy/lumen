import AppKit
import SwiftUI

/// Фон главной области (lumen-theme.css: `.grain` + `.sky`): зерно, звёзды (только в тёмной) и лучи короны из центра знака.
/// Ничего не движется. На стартовом экране звёзды и лучи в полную силу; в открытом чате звёзды .55, лучи .3 (в светлой .35).
/// Лежит под содержимым; сайдбар его не получает.
struct Sky: View {
    /// Стартовый экран (приветствие и пустое поле) — иначе открытый чат или другая страница
    var start: Bool
    /// Центр знака в координатах области; nil — как в CSS: `calc(50% - 236px)` по горизонтали и 40% по вертикали
    var center: CGPoint?
    /// Доли области вместо смещения 236 pt (знакомство: знак по центру)
    var centeredAt: CGPoint?

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        GeometryReader { g in
            let c = center ?? centeredAt.map { CGPoint(x: g.size.width * $0.x, y: g.size.height * $0.y) }
                ?? CGPoint(x: g.size.width / 2 - 236, y: g.size.height * 0.4)
            ZStack {
                Grain(light: p.isLight)
                // звёзды и днём (Рома, 22.10): на светлой — тёмные «чернильные» точки тех же мест и размеров
                Stars(tint: p.markTint, light: p.isLight).opacity(start ? 1 : 0.55)
                Rays(center: c, size: g.size, light: p.isLight, tint: p.markTint).opacity(start ? 1 : (p.isLight ? 0.35 : 0.3))
            }
            .animation(lessMotion ? nil : .easeInOut(duration: 0.8), value: start)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Куда ставить лучи: знак на стартовом экране сообщает свой центр (в пространстве «main»)
struct SkyAnchorKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGPoint?
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) { value = nextValue() ?? value }
}

extension View {
    func skyAnchor() -> some View {
        background {
            GeometryReader { g in
                let f = g.frame(in: .named("main"))
                Color.clear.preference(key: SkyAnchorKey.self, value: CGPoint(x: f.midX, y: f.midY))
            }
        }
    }
}

// MARK: зерно

/// Шум плитками 180 pt: белый (в светлой — чернила) с прозрачностью .09 × шум (.055); убирает полосы градиентов
private struct Grain: View {
    let light: Bool

    var body: some View {
        Image(nsImage: Self.tile(light: light))
            .resizable(resizingMode: .tile)
    }

    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor static func tile(light: Bool) -> NSImage {
        if let i = cache[light] { return i }
        let side = 360   // 180 pt в двойном разрешении
        var seeded = Seeded(seed: light ? 7 : 3)
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let k = light ? 0.055 : 0.09
        let rgb: (Double, Double, Double) = light ? (0.08, 0.09, 0.14) : (1, 1, 1)
        for i in 0..<(side * side) {
            // fractalNoise: значения около 0.5, разброс небольшой
            let n = min(1, max(0, 0.5 + 0.17 * seeded.gauss()))
            let a = k * n
            px[i * 4] = UInt8(min(255, rgb.0 * a * 255))
            px[i * 4 + 1] = UInt8(min(255, rgb.1 * a * 255))
            px[i * 4 + 2] = UInt8(min(255, rgb.2 * a * 255))
            px[i * 4 + 3] = UInt8(min(255, a * 255))
        }
        let image = px.withUnsafeMutableBytes { raw -> CGImage? in
            let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            return ctx?.makeImage()
        }
        let ns = image.map { NSImage(cgImage: $0, size: NSSize(width: 180, height: 180)) } ?? NSImage()
        cache[light] = ns
        return ns
    }

    /// Воспроизводимый шум: зерно не «мерцает» между запусками
    private struct Seeded {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double { (0..<4).reduce(0) { a, _ in a + next() } - 2 }   // ≈ N(0, 0.58)
    }
}

// MARK: звёзды

/// Редкие неподвижные звёзды: две плитки (520 и 830 pt) с белыми и голубоватыми точками. Рисуются один раз
private struct Stars: View {
    var tint: UInt32?
    var light = false

    var body: some View {
        Canvas { ctx, size in
            for tile in SkyData.tiles {
                var oy = 0.0
                while oy < size.height {
                    var ox = 0.0
                    while ox < size.width {
                        for (cx, cy, r, blue, a) in tile.stars {
                            let rect = CGRect(x: ox + cx - r, y: oy + cy - r, width: r * 2, height: r * 2)
                            let color = light ? Self.ink(blue, a, tint) : (blue ? Self.blue(a, tint) : Color(.sRGB, white: 1, opacity: a))
                            ctx.fill(Path(ellipseIn: rect), with: .color(color))
                        }
                        ox += tile.size
                    }
                    oy += tile.size
                }
            }
        }
    }
}

extension Stars {
    /// Звезда на светлой: чернильная точка (голубоватая — синее), у других тем — со светом темы
    static func ink(_ blue: Bool, _ a: Double, _ tint: UInt32?) -> Color {
        let base = blue ? (50.0, 75.0, 160.0) : (28.0, 38.0, 72.0)
        var c = base
        if let t = tint {
            let k = 0.45
            c = (base.0 * (1 - k) + Double((t >> 16) & 255) * k * 0.6, base.1 * (1 - k) + Double((t >> 8) & 255) * k * 0.6,
                 base.2 * (1 - k) + Double(t & 255) * k * 0.6)
        }
        return Color(.sRGB, red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, opacity: min(1, a * 1.15))
    }

    /// Голубоватая звезда; у других тем — со светом темы
    static func blue(_ a: Double, _ tint: UInt32?) -> Color {
        guard let t = tint else { return Color(.sRGB, red: 201 / 255, green: 215 / 255, blue: 1, opacity: a) }
        let k = 0.55
        return Color(.sRGB, red: (201 * (1 - k) + Double((t >> 16) & 255) * k) / 255, green: (215 * (1 - k) + Double((t >> 8) & 255) * k) / 255,
                     blue: (255 * (1 - k) + Double(t & 255) * k) / 255, opacity: a)
    }
}

// MARK: лучи

/// Лучи короны веером из центра знака: дымка 700 pt и конус из 61 остановки, затухающий по радиусу (до 1250 pt).
/// Светлая — тот же рисунок «тушью», с умножением на бумагу
private struct Rays: View {
    let center: CGPoint
    let size: CGSize
    let light: Bool
    var tint: UInt32?

    private func mixed(_ c: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
        guard let t = tint else { return c }
        return (c.0 * (1 - k) + Double((t >> 16) & 255) * k, c.1 * (1 - k) + Double((t >> 8) & 255) * k, c.2 * (1 - k) + Double(t & 255) * k)
    }

    var body: some View {
        let u = UnitPoint(x: size.width > 0 ? center.x / size.width : 0.5, y: size.height > 0 ? center.y / size.height : 0.4)
        // у других тем лучи окрашены светом темы (у «Люмена» — ровно из CSS)
        let ray = mixed(light ? (30.0, 40.0, 80.0) : (205.0, 218.0, 255.0), 0.5)
        let haze = mixed(light ? (28.0, 38.0, 72.0) : (150.0, 175.0, 255.0), 0.85)
        let c = { (t: (Double, Double, Double), a: Double) in Color(.sRGB, red: t.0 / 255, green: t.1 / 255, blue: t.2 / 255, opacity: a) }
        ZStack {
            RadialGradient(stops: [.init(color: c(haze, 0.07), location: 0), .init(color: c(haze, 0.025), location: 260.0 / 700),
                                   .init(color: c(haze, 0), location: 1)],
                           center: u, startRadius: 0, endRadius: 700)
            AngularGradient(stops: SkyData.rays.map { .init(color: c(ray, $0.0), location: $0.1 / 360) },
                            center: u, angle: .degrees(-90))
                .mask {
                    RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 160.0 / 1250),
                                           .init(color: .black.opacity(0.32), location: 460.0 / 1250), .init(color: .black.opacity(0.1), location: 850.0 / 1250),
                                           .init(color: .clear, location: 1)],
                                   center: u, startRadius: 0, endRadius: 1250)
                }
        }
        .compositingGroup()
        .blendMode(light ? .multiply : .normal)
        .drawingGroup()
    }
}
