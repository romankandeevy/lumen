// Иконка Lumen: светящаяся сфера (как в окне, Orb.swift) на тёплой темноте.
// Собирает build/AppIcon.icon (формат Icon Composer); build.sh компилирует его через actool в AppIcon.icns + Assets.car.
// Запуск: swift tools/make-icon.swift  (из папки проекта)
import AppKit

let px = 1024
let s = CGFloat(px)

func image(_ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func radial(_ cg: CGContext, at c: CGPoint, radius: CGFloat, stops: [(CGColor, CGFloat)]) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
    cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

// Цвета темы «Люмен» (Theme.swift)
let glow: UInt32 = 0xFEC766, glowCore: UInt32 = 0xFFF8DB, glowSoft: UInt32 = 0xF5B75B

// Слой 1 — свет: тёплое сияние вокруг сферы, мягко растворяется к краям
let light = image { cg in
    let c = CGPoint(x: s / 2, y: s / 2 - s * 0.01)
    radial(cg, at: c, radius: s * 0.52, stops: [(rgb(glowSoft, 0.5), 0), (rgb(glowSoft, 0.16), 0.42), (rgb(glowSoft, 0.04), 0.7), (rgb(glowSoft, 0), 1)])
}

// Слой 2 — сама сфера: свечение glow от 50%/55%, блик glowCore от 35%/30% (координаты «сверху», поэтому y переворачиваем)
let orb = image { cg in
    let r = s * 0.205
    let center = CGPoint(x: s / 2, y: s / 2 - s * 0.01)
    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    // ореол прямо у края сферы
    radial(cg, at: center, radius: r * 1.45, stops: [(rgb(glow, 0.6), 0.6), (rgb(glowSoft, 0.18), 0.8), (rgb(glowSoft, 0), 1)])
    cg.saveGState()
    cg.addEllipse(in: rect)
    cg.clip()
    // основа: тёплое золото, к низу глубже
    radial(cg, at: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.maxY - rect.height * 0.55), radius: rect.width * 0.75,
           stops: [(rgb(0xFFD68A), 0), (rgb(glow), 0.3), (rgb(0xE9A23F), 0.7), (rgb(0xA8661A), 1)])
    // к краю темнее — сфера, а не кружок
    radial(cg, at: center, radius: r, stops: [(rgb(0x6B3A0C, 0), 0.68), (rgb(0x6B3A0C, 0.18), 0.88), (rgb(0x6B3A0C, 0.42), 1)])
    // блик сверху слева
    radial(cg, at: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - rect.height * 0.3), radius: rect.width * 0.62,
           stops: [(rgb(glowCore, 1), 0), (rgb(glowCore, 0.55), 0.2), (rgb(glowCore, 0.12), 0.48), (rgb(glowCore, 0), 0.75)])
    // отражённый свет снизу справа — сфера объёмная
    radial(cg, at: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.maxY - rect.height * 0.86), radius: rect.width * 0.4,
           stops: [(rgb(glowCore, 0.25), 0), (rgb(glowCore, 0), 1)])
    cg.restoreGState()
}

let icon = URL(fileURLWithPath: "build/AppIcon.icon")
try? FileManager.default.removeItem(at: icon)
try! FileManager.default.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try! light.write(to: icon.appendingPathComponent("Assets/light.png"))
try! orb.write(to: icon.appendingPathComponent("Assets/orb.png"))
// фон — тёплая темнота окна Lumen; стекло, блики и тень выключены, чтобы цвета были как в приложении
let json = """
{
  "fill" : { "solid" : "srgb:0.07843,0.06275,0.04706,1.00000" },
  "groups" : [
    {
      "layers" : [
        { "glass" : false, "image-name" : "orb.png", "name" : "orb" },
        { "glass" : false, "image-name" : "light.png", "name" : "light" }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
"""
try! json.write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
// превью для глаз: оба слоя на фоне в одном PNG
let preview = image { cg in
    cg.setFillColor(rgb(0x14100C))
    let path = CGPath(roundedRect: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
    cg.addPath(path)
    cg.fillPath()
    cg.addPath(path)
    cg.clip()
    for d in [light, orb] {
        let img = NSBitmapImageRep(data: d)!.cgImage!
        cg.draw(img, in: CGRect(x: 0, y: 0, width: s, height: s))
    }
}
try! preview.write(to: URL(fileURLWithPath: "build/icon-preview.png"))
print("готово: build/AppIcon.icon, превью build/icon-preview.png")
