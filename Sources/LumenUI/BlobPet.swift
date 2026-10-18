import AppKit
import LumenCore
import SwiftUI

/// Состояния капли (макет «Капли Люмена»): покой, думает, … комета. Пять из них — те же, что у сферы Lumen
enum BlobAnim: String, CaseIterable, Hashable {
    case idle, thinking, wink, wide, alert, notification, exclamation, sleep, egg, hexagon, play, orbit, burst, comet

    var name: String {
        switch self {
        case .idle: "Покой"
        case .thinking: "Думает"
        case .wink: "Подмигивает"
        case .wide: "Глаза шире"
        case .alert: "Тревога"
        case .notification: "Уведомление"
        case .exclamation: "Восклицание"
        case .sleep: "Сон"
        case .egg: "Яйцо"
        case .hexagon: "Шестиугольник"
        case .play: "Пишет"
        case .orbit: "Орбита"
        case .burst: "Вспышка"
        case .comet: "Комета"
        }
    }

    /// Когда это в Lumen
    var role: String {
        switch self {
        case .idle: "ждёт: дышит и моргает"
        case .thinking: "думает над ответом: капля распадается на три точки"
        case .wink: "принял задачу"
        case .wide: "заметил новое"
        case .alert: "ждёт твоего ответа: «!» ходит туда-сюда"
        case .notification: "есть новое сообщение"
        case .exclamation: "важное"
        case .sleep: "давно тихо: глаза закрыты, храпит"
        case .egg: "запускается"
        case .hexagon: "работает с файлами"
        case .play: "пишет ответ: треугольник качается, как кнопка «играть»"
        case .orbit: "агент работает с инструментами"
        case .burst: "запомнил"
        case .comet: "быстро ищет или отправляет"
        }
    }

    /// Неподвижный кадр (превью и «меньше движения»): момент, где состояние видно лучше всего
    var rep: Double {
        switch self {
        case .idle: 0.4
        case .thinking: 0.5
        case .wink: 1.5
        case .wide: 0.45
        case .alert: 1.2
        case .notification: 0.8
        case .exclamation: 0.3
        case .sleep: 1.2
        case .egg: 0.2
        case .hexagon: 0.5
        case .play: 0.3
        case .orbit: 1
        case .burst: 0.4
        case .comet: 1
        }
    }
}

extension PetMood {
    /// Состояние Lumen → состояние капли
    var blob: BlobAnim {
        switch self {
        case .idle: .idle
        case .thinking: .thinking
        case .writing: .play
        case .remember: .burst
        case .sleep: .sleep
        }
    }
}

// MARK: формы и лица

enum BlobGeo {
    static let N = 96
    static let tau = Double.pi * 2

    struct Form { let r: [Double]; let oy: Double; let fy: Double }

    static func mod(_ a: Double, _ b: Double) -> Double { let m = a.truncatingRemainder(dividingBy: b); return m < 0 ? m + b : m }
    static func wrapPi(_ a: Double) -> Double { mod(a + .pi, tau) - .pi }

    static func blurArr(_ a: [Double], _ k: Int) -> [Double] {
        let n = a.count
        return (0..<n).map { i in
            var s = 0.0, w = 0.0
            for j in -k...k {
                let ww = exp(-Double(j * j) / (Double(k * k) / 2 + 0.0001))
                s += a[(i + j + n) % n] * ww; w += ww
            }
            return s / w
        }
    }

    static func polyR(_ n: Int, _ R: Double, _ phi0: Double) -> [Double] {
        let ap = R * cos(.pi / Double(n)), seg = tau / Double(n)
        return (0..<N).map { i in
            var d = mod(Double(i) / Double(N) * tau - (phi0 + .pi / Double(n)), seg)
            if d > seg / 2 { d -= seg }
            return ap / cos(d)
        }
    }

    static func mk(_ oy: Double = 0, _ fy: Double = 0, _ fn: (Double) -> Double) -> Form {
        Form(r: (0..<N).map { fn(Double($0) / Double(N) * tau) }, oy: oy, fy: fy)
    }

    /// Облако — объединение кругов: сверху бугры, снизу почти ровно
    static func cloud() -> Form {
        let C: [(Double, Double, Double)] = [(0, 6, 38), (-34, 12, 26), (35, 13, 25), (-14, -14, 27), (18, -18, 30), (-24, 26, 24), (26, 27, 23), (0, 30, 26)]
        let r: [Double] = (0..<N).map { i in
            let d0 = cos(Double(i) / Double(N) * tau), d1 = sin(Double(i) / Double(N) * tau)
            var best = 0.0
            for c in C {
                let b = d0 * c.0 + d1 * c.1, disc = b * b - (c.0 * c.0 + c.1 * c.1) + c.2 * c.2
                if disc > 0 { best = max(best, b + disc.squareRoot()) }
            }
            return best
        }
        return Form(r: blurArr(r, 1), oy: 0, fy: 8)
    }

    /// Формы по имени; `egg` — только для состояния «Яйцо»
    static let forms: [String: Form] = [
        "circle": mk { _ in 72 },
        "pebble": mk { t in 70 * (1 + 0.07 * sin(2 * t + 0.6) + 0.05 * sin(3 * t + 1.9) + 0.03 * sin(5 * t + 0.4)) },
        "squircle": mk { t in 66 / pow(pow(abs(cos(t)), 4) + pow(abs(sin(t)), 4), 0.25) },
        "capsule": mk { t in 1 / pow(pow(abs(cos(t) / 84), 3.4) + pow(abs(sin(t) / 46), 3.4), 1 / 3.4) },
        "triangle": Form(r: blurArr(polyR(3, 88, -.pi / 2), 3), oy: 12, fy: 12),
        "hexagon": Form(r: blurArr(polyR(6, 78, -.pi / 2), 2), oy: 0, fy: 0),
        "cloud": cloud(),
        "droplet": mk(12, 14) { t in let d = wrapPi(t + .pi / 2); return 58 + 36 * exp(-d * d / (2 * 0.34 * 0.34)) },
        "egg": mk(0, 4) { t in let s = sin(t), c = cos(t); return 58 * 74 / (74 * 74 * c * c + 58 * 58 * s * s).squareRoot() * (1 + 0.1 * s) },
    ]

    /// Глаза: x, y, ширина, высота, поворот, скругление (1 — капсула)
    static let faces: [String: [[Double]]] = [
        "neutral": [[-23, -10, 9, 26, -18, 1], [22, -14, 8, 24, -18, 1]],
        "attentive": [[-22, -8, 9, 22, 0, 1], [22, -8, 9, 22, 0, 1]],
        "surprised": [[-22, -6, 21, 21, 0, 1], [22, -6, 21, 21, 0, 1]],
        "excited": [[-22, -6, 18, 28, 0, 1], [22, -6, 18, 28, 0, 1]],
        "happy": [[-22, -6, 20, 7, 0, 1], [22, -6, 20, 7, 0, 1]],
        "laughing": [[-22, -10, 22, 6, -16, 1], [22, -10, 22, 6, 16, 1]],
        "angry": [[-22, -8, 24, 8, 22, 1], [22, -8, 24, 8, -22, 1]],
        "sad": [[-22, -4, 20, 9, -20, 1], [22, -4, 20, 9, 20, 1]],
        "scared": [[-17, -6, 18, 30, 0, 1], [17, -6, 18, 30, 0, 1]],
        "suspicious": [[-22, -8, 20, 7, 0, 1], [22, -8, 10, 10, 0, 1]],
        "confused": [[-22, -12, 16, 16, 0, 1], [22, -4, 8, 8, 0, 1]],
        "curious": [[-22, -8, 10, 22, 14, 1], [22, -8, 10, 22, 14, 1]],
        "proud": [[-22, -2, 24, 12, 0, 0.3], [22, -2, 24, 12, 0, 0.3]],
        "shy": [[-24, 4, 8, 8, 0, 1], [24, 4, 8, 8, 0, 1]],
        "unimpressed": [[-24, -4, 18, 6, 0, 1], [22, -4, 26, 6, 0, 1]],
        "sleepy": [[-22, 4, 11, 7, 0, 1], [22, 4, 11, 7, 0, 1]],
        "closed": [[-22, 3, 22, 4.5, 0, 1], [22, 3, 22, 4.5, 0, 1]],
    ]

    static func eyeLerp(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { (0..<6).map { a[$0] + (b[$0] - a[$0]) * t } }
}

// MARK: цвет

enum BlobColor {
    struct RGB { var r, g, b: Double }

    static func rgb(_ hex: String) -> RGB { let (r, g, b) = BlobLook.rgb(hex); return RGB(r: r, g: g, b: b) }
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t) }
    static func color(_ c: RGB, _ a: Double = 1) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: a) }
    static let white = RGB(r: 1, g: 1, b: 1)

    static func hsl(_ c: RGB) -> (Double, Double, Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) } else if mx == c.g { h = (c.b - c.r) / d + 2 } else { h = (c.r - c.g) / d + 4 }
        return (h / 6, s, l)
    }

    static func fromHsl(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        guard s > 0 else { return RGB(r: l, g: l, b: l) }
        func f(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            let t = BlobGeo.mod(t0, 1)
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        return RGB(r: f(p, q, h + 1.0 / 3), g: f(p, q, h), b: f(p, q, h - 1.0 / 3))
    }

    /// Плавная лесенка: свет → основа → глубокая (чуть насыщеннее) тень, через сглаженные ступени
    static func ramp(_ c: RGB) -> Gradient {
        let h = hsl(c)
        let hi = (h.0, h.1 * 0.78, h.2 + (1 - h.2) * 0.44), lo = (h.0 - 0.012, min(1, h.1 * 1.1 + 0.05), h.2 * 0.52)
        func sm(_ u: Double) -> Double { u * u * (3 - 2 * u) }
        let stops: [Gradient.Stop] = [0, 0.12, 0.26, 0.4, 0.55, 0.7, 0.85, 1].map { o in
            let (a, b, u) = o <= 0.4 ? (hi, h, sm(o / 0.4)) : (h, lo, sm((o - 0.4) / 0.6))
            let rgb = fromHsl(a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u, a.2 + (b.2 - a.2) * u)
            return Gradient.Stop(color: color(rgb), location: o)
        }
        return Gradient(stops: stops)
    }

    @MainActor private static var ramps: [String: Gradient] = [:]

    /// Лесенка для цвета с подмешанным белым (светлые точки «Думает»)
    @MainActor static func ramp(_ hex: String, lighten: Double = 0) -> Gradient {
        let key = "\(hex)|\(lighten)"
        if let g = ramps[key] { return g }
        let g = ramp(mix(rgb(hex), white, lighten))
        ramps[key] = g
        return g
    }

    /// Шар с этой лесенкой в прямоугольнике: свет сверху слева
    @MainActor static func sphere(_ rect: CGRect, _ hex: String, lighten: Double = 0) -> GraphicsContext.Shading {
        .radialGradient(ramp(hex, lighten: lighten), center: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.22),
                        startRadius: 0, endRadius: max(rect.width, rect.height) * 1.0)
    }
}

// MARK: кадр

/// Куда стремится капля в этот момент состояния
struct BlobTarget {
    var shape: String
    var face: String
    var eyes: [[Double]]?
    var s = 1.0, sx = 1.0, sy = 1.0, x = 0.0, y = 0.0, rot = 0.0, piv = 62.0
    var alpha = 1.0, eyeA = 1.0, look = 1.0, blink = 1.0, shadow = 0.45, eyeCounter = 0.0
    var fast = false
    var ex = BlobExtras()
}

struct BlobExtras {
    struct Dot { var x, y, r: Double; var light: Double }
    struct Bang { var x, y, rot, dotY, dotS: Double; var rings: [(r: Double, a: Double)]; var sx = 1.0 }
    struct Badge { var s, pr, pa: Double }
    struct Z { var x, y, s, a: Double }
    struct Guide { var rx, ry, rot: Double }
    struct Bit { var x, y, r, a: Double }
    struct Trail { var pts: [(x: Double, y: Double, w: Double)]; var head: Bit? }

    var dots: [Dot]?
    var bang: Bang?
    var badge: Badge?
    var zs: [Z]?
    var orbit: Guide?
    var burst: [Bit]?
    var trail: Trail?
}

enum BlobMotion {
    static func blinkAt(_ t: Double, _ period: Double) -> Double {
        let m = BlobGeo.mod(t, period)
        guard m >= period - 0.16 else { return 1 }
        let u = (m - (period - 0.16)) / 0.16
        return 1 - 0.9 * (1 - abs(2 * u - 1))
    }

    static func breathe(_ t: Double, _ b: inout BlobTarget, _ amt: Double) {
        let s = sin(t * BlobGeo.tau / 3.4)
        b.sx = 1 + amt * s; b.sy = 1 - amt * s; b.y = -1.5 * s
    }

    static func target(_ anim: BlobAnim, _ t: Double, look: BlobLook) -> BlobTarget {
        let tau = BlobGeo.tau
        var b = BlobTarget(shape: look.shape.rawValue, face: look.face.rawValue)
        func clamp(_ v: Double, _ a: Double, _ c: Double) -> Double { min(max(v, a), c) }
        let mod = BlobGeo.mod
        switch anim {
        case .idle:
            breathe(t, &b, 0.022); b.blink = blinkAt(t, 4.2)
        case .thinking:
            b.alpha = 0; b.s = 0.3; b.eyeA = 0; b.shadow = 0.25
            b.ex.dots = (0..<3).map { i in
                let w = max(0, sin(t * tau / 1.2 - Double(i) * 0.9))
                return .init(x: Double(i - 1) * 34, y: -10 * w * w, r: [10.0, 15, 12][i] * (1 + 0.12 * w), light: [0.35, 0, 0.15][i])
            }
        case .wink:
            breathe(t, &b, 0.02)
            let c = mod(t, 2.4), w = c > 1.1 && c < 1.9 ? sin((c - 1.1) / 0.8 * .pi) : 0, A = BlobGeo.faces["attentive"]!
            b.eyes = [A[0], BlobGeo.eyeLerp(A[1], [22, -3, 22, 5, 0, 1], clamp(w * 1.6, 0, 1))]; b.rot = 5 * w; b.look = 0.5
        case .wide:
            let c = mod(t, 2), w = c < 0.15 ? c / 0.15 : (c < 1.2 ? 1 : max(0, 1 - (c - 1.2) / 0.5)), pop = c < 0.5 ? sin(c / 0.5 * .pi) * 0.07 : 0
            b.sx = 1 + pop * 0.5; b.sy = 1 + pop; b.x = c < 0.5 ? sin(c * 60) * 1.2 : 0
            let F = BlobGeo.faces[b.face] ?? BlobGeo.faces["attentive"]!
            b.eyes = [BlobGeo.eyeLerp(F[0], [-22, -6, 26, 28, 0, 1], w), BlobGeo.eyeLerp(F[1], [22, -6, 26, 28, 0, 1], w)]
        case .alert:
            // один плавный цикл: на краях замедляется и ёрзает, на развороте подпрыгивает, наклоняется туда, куда идёт
            b.alpha = 0; b.eyeA = 0; b.shadow = 0.2
            let ph = t * tau / 5.2, k = 1.3, s = sin(ph), c = cos(ph), th = tanh(k * s)
            let x = 40 * th / tanh(k), v = c * (1 - th * th), av = abs(v), edge = clamp((abs(x) - 35) / 5, 0, 1)
            let step = abs(sin(t * tau * 1.05)) * av
            let lean = 15 * v + 2.4 * sin(t * tau * 1.05) * av
            let fidget = (1 - av) * (1.9 * sin(t * tau * 1.5) + 0.8 * sin(t * tau * 2.3 + 1))
            let jitter = 0.35 * sin(t * 37) + 0.25 * sin(t * 23.3)
            let hop = -6.5 * exp(-pow(c / 0.17, 2))
            let rg = (0..<2).map { i -> (r: Double, a: Double) in let q = mod(t * 0.5 + Double(i) * 0.5, 1); return (14 + 44 * q, 0.26 * (1 - q)) }
            b.ex.bang = .init(x: x + jitter * 0.8, y: -3.2 * step + hop, rot: lean + fidget + jitter, dotY: 56, dotS: 1, rings: rg,
                              sx: 1 - 0.5 * edge * edge * (abs(c) < 0.35 ? 1 : 0))
        case .notification:
            breathe(t, &b, 0.02); b.blink = blinkAt(t, 4.6); b.face = "attentive"
            let u = min(t / 0.45, 1), s = u < 1 ? 1 + 2.7 * pow(u - 1, 3) + 1.7 * pow(u - 1, 2) : 1, p = mod(t, 2.2)
            b.ex.badge = .init(s: clamp(s, 0, 1.4), pr: 12 + 20 * (p / 1.2), pa: p < 1.2 ? 0.6 * (1 - p / 1.2) : 0)
        case .exclamation:
            b.alpha = 0; b.eyeA = 0; b.shadow = 0.2
            let h = abs(sin(t * 3.2)), hd = abs(sin(t * 3.2 - 0.5))
            b.ex.bang = .init(x: 0, y: -22 * h, rot: -10, dotY: 56 - 14 * hd, dotS: 1, rings: [])
        case .sleep:
            let br = sin(t * tau / 4)
            b.sx = 1 + 0.03 * br; b.sy = 1 - 0.03 * br; b.y = 3 - 1.5 * br; b.rot = 3; b.look = 0.1
            b.eyes = BlobGeo.faces["closed"]; b.shadow = 0.4
            b.ex.zs = (0..<3).map { k in
                let u = mod(t / 2.8 + Double(k) / 3, 1)
                return .init(x: 38 + u * 26 + Double(k) * 2, y: -34 - u * 46, s: 0.5 + 0.8 * u, a: sin(.pi * u) * 0.95)
            }
        case .egg:
            b.shape = "egg"; b.rot = 7 * sin(t * tau / 1.5); b.sx = 1 + 0.015 * sin(t * tau / 1.5 + 1); b.blink = blinkAt(t, 3.6)
        case .hexagon:
            b.shape = "hexagon"; b.rot = 9 * sin(t * tau / 2.6); breathe(t, &b, 0.02); b.blink = blinkAt(t, 3.9)
        case .play:
            b.shape = "triangle"; b.piv = 0; b.rot = 90 + 6 * sin(t * tau / 1.2); b.x = 6 * sin(t * tau / 1.2)
            b.eyeCounter = 1; b.blink = blinkAt(t, 3.3); b.face = "attentive"
        case .orbit:
            let a0 = t * 1.4, rx = 60.0, ry = 30.0, tilt = -0.32, ca = cos(tilt), sa = sin(tilt)
            func pos(_ a: Double) -> (x: Double, y: Double, z: Double) {
                let x = rx * cos(a), y = ry * sin(a)
                return (x * ca - y * sa, x * sa + y * ca, sin(a))
            }
            let p = pos(a0)
            b.piv = 0; b.fast = true; b.s = 0.3 + 0.07 * p.z; b.x = p.x; b.y = p.y; b.shadow = 0; b.look = 0.6
            let pts = (0...40).map { i -> (x: Double, y: Double, w: Double) in
                let q = pos(a0 - Double(i) * 0.055)
                return (q.x, q.y, 14 * pow(1 - Double(i) / 40, 1.2) * (0.8 + 0.2 * q.z))
            }
            b.ex.trail = .init(pts: pts, head: nil)
            b.ex.orbit = .init(rx: rx, ry: ry, rot: tilt * 180 / .pi)
        case .burst:
            let u = mod(t / 1.5, 1), e = 1 - pow(1 - u, 3)
            b.s = 0.09 + (u < 0.12 ? 0.12 * sin(u / 0.12 * .pi) : 0); b.piv = 0; b.eyeA = 0; b.shadow = 0.15
            b.ex.burst = (0..<14).map { i in
                let a = Double(i) / 14 * tau + Double(i % 2) * 0.2, v = 0.6 + Double(i % 3) * 0.2
                return .init(x: cos(a) * (10 + 80 * e * v), y: sin(a) * (10 + 80 * e * v), r: 4.5 * (1 - u * 0.7) + 1, a: max(0, 1 - pow(u, 1.6)))
            }
        case .comet:
            b.alpha = 0; b.eyeA = 0; b.shadow = 0
            let ca = cos(-0.49), sa = sin(-0.49)
            let pts = (0...44).map { i -> (x: Double, y: Double, w: Double) in
                let a = t * 2.4 - Double(i) * 0.042, x = 70 * cos(a), y = 36 * sin(a)
                return (x * ca - y * sa, x * sa + y * ca, 9.5 * pow(1 - Double(i) / 44, 1.35))
            }
            b.ex.trail = .init(pts: pts, head: .init(x: pts[0].x, y: pts[0].y, r: 10, a: 1))
        }
        return b
    }
}

/// Живое состояние одной капли: к цели она плавно перетекает (форма, глаза, положение), дополнения проявляются и гаснут
final class BlobSim {
    var r = BlobGeo.forms["circle"]!.r
    var oy = 0.0, fy = 0.0
    var eyes = BlobGeo.faces["attentive"]!
    var s = 1.0, sx = 1.0, sy = 1.0, x = 0.0, y = 0.0, rot = 0.0, piv = 62.0, alpha = 1.0, eyeA = 1.0, shadow = 0.45, eyeCounter = 0.0
    var lx = 0.0, ly = 0.0
    var ea: [String: Double] = ["dots": 0, "bang": 0, "badge": 0, "zs": 0, "orbit": 0, "burst": 0, "trail": 0]
    var ex = BlobExtras()
    var last: Double?
    var target = BlobTarget(shape: "circle", face: "attentive")

    /// Шаг: `t` — время в состоянии, `now` — часы (для плавности), `gaze` — куда смотреть (−1…1) или nil — блуждать
    func step(_ anim: BlobAnim, look: BlobLook, t: Double, now: Double, gaze: CGPoint?, snap: Bool) {
        let b = BlobMotion.target(anim, t, look: look)
        target = b
        let dt = snap ? 1 : min(0.05, max(0, now - (last ?? now)))
        last = now
        let k = snap ? 1 : 1 - exp(-dt * 9), kt = snap ? 1 : 1 - exp(-dt * (b.fast ? 60 : 16)), ke = snap ? 1 : 1 - exp(-dt * 14)
        let f = BlobGeo.forms[b.shape] ?? BlobGeo.forms["circle"]!
        for i in 0..<BlobGeo.N { r[i] += (f.r[i] - r[i]) * k }
        oy += (f.oy - oy) * k; fy += (f.fy - fy) * k
        let ev = b.eyes ?? BlobGeo.faces[b.face] ?? BlobGeo.faces["attentive"]!
        for e in 0..<2 { for j in 0..<6 { eyes[e][j] += (ev[e][j] - eyes[e][j]) * k } }
        s += (b.s - s) * kt; sx += (b.sx - sx) * kt; sy += (b.sy - sy) * kt
        x += (b.x - x) * kt; y += (b.y - y) * kt; rot += (b.rot - rot) * kt; piv += (b.piv - piv) * kt
        alpha += (b.alpha - alpha) * kt; eyeA += (b.eyeA - eyeA) * kt; shadow += (b.shadow - shadow) * kt; eyeCounter += (b.eyeCounter - eyeCounter) * kt
        let g = gaze ?? CGPoint(x: sin(now * 0.6) * 0.5, y: cos(now * 0.45) * 0.25)
        let kl = snap ? 1 : 1 - exp(-dt * 8)
        lx += (g.x * b.look - lx) * kl; ly += (g.y * b.look - ly) * kl
        func fade(_ name: String, _ on: Bool) { ea[name, default: 0] += ((on ? 1 : 0) - ea[name, default: 0]) * ke }
        if let v = b.ex.dots { ex.dots = v }; fade("dots", b.ex.dots != nil)
        if let v = b.ex.bang { ex.bang = v }; fade("bang", b.ex.bang != nil)
        if let v = b.ex.badge { ex.badge = v }; fade("badge", b.ex.badge != nil)
        if let v = b.ex.zs { ex.zs = v }; fade("zs", b.ex.zs != nil)
        if let v = b.ex.orbit { ex.orbit = v }; fade("orbit", b.ex.orbit != nil)
        if let v = b.ex.burst { ex.burst = v }; fade("burst", b.ex.burst != nil)
        if let v = b.ex.trail { ex.trail = v }; fade("trail", b.ex.trail != nil)
    }
}

// MARK: рисование

enum BlobDraw {
    /// Контур капли по радиусам: гладкая кривая через 96 точек
    static func body(_ r: [Double], _ oy: Double) -> Path {
        let n = r.count
        let P: [CGPoint] = (0..<n).map { i in
            let th = Double(i) / Double(n) * BlobGeo.tau
            return CGPoint(x: r[i] * cos(th), y: r[i] * sin(th) + oy)
        }
        var path = Path()
        path.move(to: P[0])
        for i in 0..<n {
            let p0 = P[(i + n - 1) % n], p1 = P[i], p2 = P[(i + 1) % n], p3 = P[(i + 2) % n]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    /// Сужающаяся лента по точкам (хвост кометы и орбиты)
    static func ribbon(_ pts: [(x: Double, y: Double, w: Double)], _ k: Double) -> Path {
        let n = pts.count
        var L: [CGPoint] = [], R: [CGPoint] = []
        for i in 0..<n {
            let p = pts[i], a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            let dx = b.x - a.x, dy = b.y - a.y, l = max((dx * dx + dy * dy).squareRoot(), 0.0001), nx = -dy / l, ny = dx / l
            L.append(CGPoint(x: p.x + nx * p.w * k, y: p.y + ny * p.w * k)); R.append(CGPoint(x: p.x - nx * p.w * k, y: p.y - ny * p.w * k))
        }
        var path = Path()
        path.addLines(L + R.reversed())
        path.closeSubpath()
        return path
    }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }

    @MainActor static func draw(_ g0: GraphicsContext, size: CGSize, sim c: BlobSim, look: BlobLook) {
        var g = g0
        let unit = min(size.width, size.height) / 200
        g.translateBy(x: size.width / 2, y: size.height / 2)
        g.scaleBy(x: unit, y: unit)
        let hex = look.color, rgb = BlobColor.rgb(hex)
        let lum = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        let main = BlobColor.color(rgb)
        let X = c.ex, ea = c.ea

        // тень под каплей
        g.drawLayer { l in
            l.opacity = min(max(c.shadow, 0), 1)
            l.addFilter(.blur(radius: 5 * unit))
            let rx = 52 * (0.3 + 0.7 * min(1, c.s))
            l.fill(Path(ellipseIn: CGRect(x: -rx, y: 80, width: rx * 2, height: 16)), with: .color(.black))
        }

        // сзади: дорожка орбиты и хвост
        if let o = X.orbit, ea["orbit", default: 0] > 0.01 {
            var l = g
            l.opacity = ea["orbit", default: 0]
            l.rotate(by: .degrees(o.rot))
            l.stroke(Path(ellipseIn: CGRect(x: -o.rx, y: -o.ry, width: o.rx * 2, height: o.ry * 2)), with: .color(.white.opacity(0.14)), lineWidth: 1.5)
        }
        if let tr = X.trail, ea["trail", default: 0] > 0.01, let first = tr.pts.first, let last = tr.pts.last {
            var l = g
            l.opacity = ea["trail", default: 0]
            let a = CGPoint(x: first.x, y: first.y), b = CGPoint(x: last.x, y: last.y)
            let outer = Gradient(stops: [.init(color: BlobColor.color(rgb, 0.85), location: 0), .init(color: BlobColor.color(rgb, 0.45), location: 0.45), .init(color: BlobColor.color(rgb, 0), location: 1)])
            let light = BlobColor.mix(rgb, BlobColor.white, 0.5)
            let inner = Gradient(stops: [.init(color: BlobColor.color(light, 0.95), location: 0), .init(color: BlobColor.color(light, 0.55), location: 0.45), .init(color: BlobColor.color(light, 0), location: 1)])
            l.fill(ribbon(tr.pts, 1), with: .linearGradient(outer, startPoint: a, endPoint: b))
            l.fill(ribbon(tr.pts, 0.4), with: .linearGradient(inner, startPoint: a, endPoint: b))
        }

        // тело
        if c.alpha > 0.01 {
            var bg = g
            bg.opacity = min(max(c.alpha, 0), 1)
            bg.translateBy(x: c.x + c.lx * 3, y: c.y)
            bg.translateBy(x: 0, y: c.piv)
            bg.rotate(by: .degrees(c.rot))
            bg.scaleBy(x: c.sx * c.s, y: c.sy * c.s)
            bg.translateBy(x: 0, y: -c.piv)
            let path = body(c.r, c.oy)
            let box = path.boundingRect
            let k = unit * c.s
            bg.fill(path, with: BlobColor.sphere(box, hex))
            bg.drawLayer { l in
                l.clip(to: path)
                // отражённый свет снизу
                let bounce = BlobColor.mix(rgb, BlobColor.white, 0.4)
                l.fill(Path(ellipseIn: CGRect(x: 6 - 64, y: 60 - 30, width: 128, height: 60)),
                       with: .radialGradient(Gradient(stops: [.init(color: BlobColor.color(bounce, 0.3), location: 0), .init(color: BlobColor.color(bounce, 0.1), location: 0.6), .init(color: BlobColor.color(bounce, 0), location: 1)]),
                                             center: CGPoint(x: 6, y: 60), startRadius: 0, endRadius: 64))
                // тень вдоль края — повторяет форму
                l.drawLayer { s in
                    s.addFilter(.blur(radius: 9 * k))
                    s.stroke(path.offsetBy(dx: -8, dy: -9), with: .color(.black.opacity(0.34)), lineWidth: 30)
                }
                // светлый край сверху слева
                l.drawLayer { s in
                    s.addFilter(.blur(radius: 3 * k))
                    s.stroke(path.offsetBy(dx: 4, dy: 5), with: .color(BlobColor.color(BlobColor.mix(rgb, BlobColor.white, 0.6), 0.42)), lineWidth: 8)
                }
                // мягкий блик
                l.fill(Path(ellipseIn: CGRect(x: -22 - 38, y: -34 - 26, width: 76, height: 52)),
                       with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.62), location: 0), .init(color: .white.opacity(0.24), location: 0.4), .init(color: .white.opacity(0.06), location: 0.75), .init(color: .white.opacity(0), location: 1)]),
                                             center: CGPoint(x: -22, y: -34), startRadius: 0, endRadius: 38))
                var hl = l
                hl.translateBy(x: -27, y: -40)
                hl.rotate(by: .degrees(-28))
                hl.scaleBy(x: 1, y: 9.0 / 15)
                hl.fill(circle(0, 0, 15), with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.8), location: 0), .init(color: .white.opacity(0.3), location: 0.5), .init(color: .white.opacity(0), location: 1)]),
                                                                 center: .zero, startRadius: 0, endRadius: 15))
            }
            // глаза
            if c.eyeA > 0.01 {
                var eg = bg
                eg.opacity = min(max(c.eyeA, 0), 1)
                eg.translateBy(x: c.lx * 13 * c.target.look, y: c.ly * 9 * c.target.look)
                eg.rotate(by: .degrees(-c.rot * c.eyeCounter))
                let eye = lum > 0.6 ? Color(red: 0.11, green: 0.1, blue: 0.09) : Color(red: 1, green: 0.973, blue: 0.925)
                for e in c.eyes {
                    let w = e[2], h = max(2, e[3] * c.target.blink), rr = min(w, h) / 2 * min(max(e[5], 0), 1)
                    let rect = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: rr)
                    let t = CGAffineTransform(rotationAngle: e[4] * .pi / 180).concatenating(CGAffineTransform(translationX: e[0], y: e[1] + c.fy))
                    eg.fill(rect.applying(t), with: .color(eye))
                }
            }
        }

        // спереди: точки «думает»
        if let dots = X.dots, ea["dots", default: 0] > 0.01 {
            var l = g
            l.opacity = ea["dots", default: 0]
            for d in dots {
                let p = circle(d.x, d.y, d.r)
                l.fill(p, with: BlobColor.sphere(p.boundingRect, hex, lighten: d.light))
            }
        }
        // «!»
        if let bg = X.bang, ea["bang", default: 0] > 0.01 {
            var l = g
            l.opacity = ea["bang", default: 0]
            l.translateBy(x: bg.x, y: bg.y)
            l.translateBy(x: 0, y: 56); l.rotate(by: .degrees(bg.rot)); l.translateBy(x: 0, y: -56)
            l.scaleBy(x: bg.sx, y: 1)
            for ring in bg.rings { l.stroke(circle(0, 56, ring.r), with: .color(main.opacity(ring.a)), lineWidth: 3) }
            let bar = Path(roundedRect: CGRect(x: -9, y: -72, width: 18, height: 84), cornerRadius: 9)
            l.fill(bar, with: BlobColor.sphere(bar.boundingRect, hex))
            let dot = circle(0, bg.dotY, 11 * bg.dotS)
            l.fill(dot, with: BlobColor.sphere(dot.boundingRect, hex))
        }
        // значок уведомления
        if let bd = X.badge, ea["badge", default: 0] > 0.01 {
            var l = g
            l.opacity = ea["badge", default: 0]
            l.translateBy(x: 58, y: -58)
            l.scaleBy(x: bd.s, y: bd.s)
            let blue = Color(red: 0.29, green: 0.64, blue: 1)
            l.stroke(circle(0, 0, bd.pr), with: .color(blue.opacity(bd.pa)), lineWidth: 3)
            l.fill(circle(0, 0, 12), with: .color(blue))
            l.stroke(circle(0, 0, 12), with: .color(.white.opacity(0.35)), lineWidth: 1.5)
        }
        // храп
        if let zs = X.zs, ea["zs", default: 0] > 0.01 {
            for z in zs {
                var l = g
                l.opacity = z.a * ea["zs", default: 0]
                l.translateBy(x: z.x, y: z.y); l.rotate(by: .degrees(-8)); l.scaleBy(x: z.s, y: z.s)
                var p = Path()
                p.move(to: CGPoint(x: -7, y: -7)); p.addLine(to: CGPoint(x: 7, y: -7)); p.addLine(to: CGPoint(x: -7, y: 7)); p.addLine(to: CGPoint(x: 7, y: 7))
                l.stroke(p, with: .color(Color(red: 0.616, green: 0.596, blue: 0.561)), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
            }
        }
        // вспышка
        if let bits = X.burst, ea["burst", default: 0] > 0.01 {
            for p in bits where p.a > 0.01 {
                var l = g
                l.opacity = p.a * ea["burst", default: 0]
                let c0 = circle(p.x, p.y, p.r)
                l.fill(c0, with: BlobColor.sphere(c0.boundingRect, hex))
            }
        }
        // голова кометы
        if let tr = X.trail, let h = tr.head, ea["trail", default: 0] > 0.01 {
            var l = g
            l.opacity = ea["trail", default: 0]
            let p = circle(h.x, h.y, h.r)
            l.fill(p, with: BlobColor.sphere(p.boundingRect, hex))
        }
    }
}

// MARK: вид

/// Где капля на экране — чтобы смотреть на курсор и вне её рамки
@MainActor final class ScreenAnchor {
    weak var view: NSView?
    private var lastMouse = CGPoint.zero
    private var movedAt = Date.distantPast

    /// Куда смотреть: −1…1 по осям (вверх — минус), или nil, если мышь давно не двигалась
    func gaze() -> CGPoint? {
        let m = NSEvent.mouseLocation
        if m != lastMouse { lastMouse = m; movedAt = Date() }
        guard Date().timeIntervalSince(movedAt) < 4, let v = view, let w = v.window else { return nil }
        let r = w.convertToScreen(v.convert(v.bounds, to: nil))
        let dx = m.x - r.midX, dy = r.midY - m.y
        let len = max((dx * dx + dy * dy).squareRoot(), 140)
        return CGPoint(x: dx / len, y: dy / len)
    }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context: Context) -> NSView { let v = NSView(); anchor.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { anchor.view = v }
}

/// Капля: форма, лицо и цвет из `look`, состояние — `anim`. Неподвижная рисуется один раз
struct BlobView: View {
    let look: BlobLook
    var anim: BlobAnim = .idle
    var size: CGFloat = 64
    var animated = true
    /// Следить глазами за курсором (большие капли: превью, питомец поверх окон)
    var followsCursor = false

    @Environment(\.lessMotion) private var lessMotion
    @State private var sim = BlobSim()
    @State private var start = Date()
    @State private var anchor = ScreenAnchor()

    var body: some View {
        let still = !animated || lessMotion
        TimelineView(.animation(minimumInterval: 1 / 40, paused: still)) { ctx in
            Canvas { g, sz in
                let now = ctx.date.timeIntervalSinceReferenceDate
                let t = still ? anim.rep : ctx.date.timeIntervalSince(start)
                sim.step(anim, look: look, t: t, now: now, gaze: followsCursor && !still ? anchor.gaze() : nil, snap: still || sim.last == nil)
                BlobDraw.draw(g, size: sz, sim: sim, look: look)
            }
        }
        .frame(width: size, height: size)
        .background { if followsCursor { AnchorView(anchor: anchor) } }
        .onChange(of: anim) { start = Date() }
        .accessibilityHidden(true)
    }
}
