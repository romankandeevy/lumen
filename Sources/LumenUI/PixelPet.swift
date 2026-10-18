import AppKit
import LumenCore
import SwiftUI

/// Что сейчас делает питомец — те же состояния, что у сферы Lumen
enum PetMood: String, CaseIterable, Hashable {
    case idle, thinking, writing, remember, sleep

    var name: String {
        switch self {
        case .idle: "Покой"
        case .thinking: "Думает"
        case .writing: "Пишет"
        case .remember: "Запомнил"
        case .sleep: "Спит"
        }
    }

    init(_ orb: Orb.State) {
        switch orb {
        case .idle: self = .idle
        case .thinking: self = .thinking
        case .writing: self = .writing
        case .remember: self = .remember
        case .sleep: self = .sleep
        }
    }
}

/// Пиксельные питомцы (макет «Питомцы Люмена»): сетка 32×32, обводка и тени считаются сами,
/// кадр собирается из параметров состояния и тика (1 тик = 100 мс).
enum PixelPet {
    static let W = 32, H = 32

    struct RGB { var r, g, b: Double }
    struct Mat { let l, m, d: RGB }

    static func hex(_ s: String) -> RGB {
        let (r, g, b) = BlobLook.rgb(s)
        return RGB(r: r * 255, g: g * 255, b: b * 255)
    }
    static func mat(_ l: String, _ m: String, _ d: String) -> Mat { Mat(l: hex(l), m: hex(m), d: hex(d)) }
    static func flat(_ c: String) -> Mat { mat(c, c, c) }
    /// Math.round из макета: половина — вверх
    static func jr(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    struct Cell { let m: Mat; let id: Int }

    final class Grid {
        var c = [Cell?](repeating: nil, count: W * H)
        var id = 0

        func set(_ x: Double, _ y: Double, _ m: Mat, _ id: Int) {
            let xi = jr(x), yi = jr(y)
            if xi >= 0, xi < W, yi >= 0, yi < H { c[yi * W + xi] = Cell(m: m, id: id) }
        }
        func cell(_ x: Int, _ y: Int) -> Cell? { x < 0 || y < 0 || x >= W || y >= H ? nil : c[y * W + x] }

        func E(_ m: Mat, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
            id += 1
            var y = (cy - ry - 1).rounded(.down)
            while y <= (cy + ry + 1).rounded(.up) {
                var x = (cx - rx - 1).rounded(.down)
                while x <= (cx + rx + 1).rounded(.up) {
                    let dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry
                    if dx * dx + dy * dy <= 1 { set(x, y, m, id) }
                    x += 1
                }
                y += 1
            }
        }
        func R(_ m: Mat, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            id += 1
            guard y0 <= y1, x0 <= x1 else { return }
            for y in y0...y1 { for x in x0...x1 { set(Double(x), Double(y), m, id) } }
        }
        func RR(_ m: Mat, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ r: Int) {
            id += 1
            guard y0 <= y1, x0 <= x1 else { return }
            let rd = Double(r)
            for y in y0...y1 {
                for x in x0...x1 {
                    let cx: Double = x < x0 + r ? Double(x0 + r) : (x > x1 - r ? Double(x1 - r + 1) : Double(x) + 0.5)
                    let cy: Double = y < y0 + r ? Double(y0 + r) : (y > y1 - r ? Double(y1 - r + 1) : Double(y) + 0.5)
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    if dx * dx + dy * dy <= rd * rd + 0.2 { set(Double(x), Double(y), m, id) }
                }
            }
        }
        func T(_ m: Mat, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) {
            id += 1
            func s(_ px: Double, _ py: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
                (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
            }
            for y in 0..<H {
                for x in 0..<W {
                    let px = Double(x) + 0.5, py = Double(y) + 0.5
                    let d1 = s(px, py, ax, ay, bx, by), d2 = s(px, py, bx, by, cx, cy), d3 = s(px, py, cx, cy, ax, ay)
                    let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
                    if !(neg && pos) { set(Double(x), Double(y), m, id) }
                }
            }
        }
        func L(_ m: Mat, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, thick: Bool = false) {
            id += 1
            var steps = max(abs(x1 - x0), abs(y1 - y0)) * 2
            if steps == 0 { steps = 1 }
            let horiz = abs(x1 - x0) >= abs(y1 - y0)
            var i = 0.0
            while i <= steps {
                let x = Double(jr(x0 + (x1 - x0) * i / steps)), y = Double(jr(y0 + (y1 - y0) * i / steps))
                set(x, y, m, id)
                if horiz { set(x, y + 1, m, id); if thick { set(x, y - 1, m, id) } } else { set(x + 1, y, m, id); if thick { set(x - 1, y, m, id) } }
                i += 1
            }
        }
    }

    enum Eyes { case open, up, blink, squint, happy, sleep }

    /// Параметры кадра: сдвиги головы и тела, лапы, глаза, хвост, вспышка, приглушённость
    struct P {
        var j = 0, hx = 0, hy = 0, al = 0, ar = 0
        var eyes = Eyes.open
        var tail = 0, ears = 0, ray = 0
        var tongue = false
        var flash = 0.0
        var dim = false
        var p = -1
    }

    typealias Ov = (Int, Int, String) -> Void

    static func eye2(_ ov: Ov, _ x: Int, _ y: Int, _ style: Eyes, _ c: String, _ spec: String) {
        switch style {
        case .open, .up:
            let yy = style == .up ? y - 1 : y
            for i in 0..<2 { for j in 0..<3 { ov(x + i, yy + j, c) } }
            ov(x, yy, spec)
        case .blink: ov(x, y + 1, c); ov(x + 1, y + 1, c)
        case .squint: for i in 0..<2 { for j in 1..<3 { ov(x + i, y + j, c) } }
        case .happy: ov(x - 1, y + 2, c); ov(x, y + 1, c); ov(x + 1, y + 1, c); ov(x + 2, y + 2, c)
        case .sleep: ov(x - 1, y + 1, c); ov(x, y + 2, c); ov(x + 1, y + 2, c); ov(x + 2, y + 1, c)
        }
    }
    static func eyes(_ ov: Ov, _ xl: Int, _ y: Int, _ style: Eyes, _ c: String, _ spec: String) {
        eye2(ov, xl, y, style, c, spec); eye2(ov, 30 - xl, y, style, c, spec)
    }

    // MARK: питомцы

    struct Spec { let ol: String; let accent: String }

    static func spec(_ k: PetKind) -> Spec {
        switch k {
        case .cat: Spec(ol: "#3a1f14", accent: "#f3c97a")
        case .dog: Spec(ol: "#3a2214", accent: "#f3c97a")
        case .robot: Spec(ol: "#1b2230", accent: "#ffd98a")
        case .codex: Spec(ol: "#0b1417", accent: "#a8e6ff")
        case .claude, .blob: Spec(ol: "#3b1c10", accent: "#ffb98a")
        }
    }

    // материалы: свет, основа, тень
    private static let catFur = mat("#f7c58a", "#e8995a", "#b9693a"), cream = mat("#fff3dc", "#f6dcb0", "#d9b98a")
    private static let catStripe = mat("#b9633a", "#a8552e", "#8f4426"), catPink = flat("#e88a92")
    private static let dogFur = mat("#eab97c", "#d99a55", "#aa7035"), dogEar = mat("#a8734d", "#82532f", "#5a361f")
    private static let dogCollar = mat("#7fe0e8", "#3db7c4", "#247f8e"), dogGold = flat("#ffd36a"), dogNose = flat("#2a1a14"), dogTongue = flat("#e8737f")
    private static let steel = mat("#cfd8e3", "#97a6b8", "#5e6d82"), joint = mat("#8693a6", "#5e6d82", "#3d4757")
    private static let screen = flat("#0f1218"), neck = flat("#3d4757"), bulb = flat("#ffd98a")
    private static let cxBody = mat("#4f7d85", "#2f565e", "#1c3a42"), cxScreen = flat("#070b0d"), cxFoot = flat("#1a2d33"), cxLed = flat("#a8e6ff")
    private static let clay = mat("#f2a57f", "#d97757", "#a9502f"), rays = mat("#ffe0c4", "#f7b48a", "#e08a5c")
    private static let torso = mat("#c9694a", "#a9502f", "#7e3a22"), hand = mat("#f4b08a", "#e8895f", "#b9603c"), feet = flat("#7e3a22")

    static func paint(_ k: PetKind, _ g: Grid, _ P: P, _ ov: @escaping Ov) {
        let J = P.j, hx = P.hx, hy = P.hy + J
        let D = Double.init(_:) as (Int) -> Double
        let face: Ov = { x, y, c in ov(x + hx, y + hy, c) }
        switch k {
        case .cat:
            let tail = P.tail != 0 ? [(22, 27), (24, 27), (26, 26), (27, 24), (27, 22), (26, 20)] : [(22, 27), (24, 27), (25, 25), (26, 23), (26, 21), (25, 19)]
            for (i, t) in tail.enumerated() { g.R(i > 3 ? catStripe : catFur, t.0, t.1 + J, t.0 + 1, t.1 + 1 + J) }
            g.E(catFur, 8.5, 25.5 + D(J), 3.6, 3.6); g.E(catFur, 23.5, 25.5 + D(J), 3.6, 3.6)
            g.E(catFur, 16, 23 + D(J), 8, 6.5)
            g.R(cream, 11, 21 + J, 14, 27 + P.al + J); g.E(cream, 12.5, 28 + D(P.al + J), 3.2, 2.2)
            g.R(cream, 17, 21 + J, 20, 27 + P.ar + J); g.E(cream, 19.5, 28 + D(P.ar + J), 3.2, 2.2)
            g.T(catFur, D(7 + hx), D(8 + hy), D(8 + hx), D(1 + hy), D(13 + hx), D(6 + hy))
            g.T(catFur, D(24 + hx), D(8 + hy), D(23 + hx), D(1 + hy), D(18 + hx), D(6 + hy))
            g.T(catPink, D(9 + hx), D(6 + hy), D(9 + hx), D(3 + hy), D(12 + hx), D(6 + hy))
            g.T(catPink, D(22 + hx), D(6 + hy), D(22 + hx), D(3 + hy), D(19 + hx), D(6 + hy))
            g.E(catFur, D(16 + hx), D(13 + hy), 9.5, 7.5)
            g.R(catStripe, 15 + hx, 6 + hy, 16 + hx, 8 + hy); g.R(catStripe, 12 + hx, 7 + hy, 12 + hx, 8 + hy); g.R(catStripe, 19 + hx, 7 + hy, 19 + hx, 8 + hy)
            g.E(cream, D(16 + hx), 16.5 + D(hy), 5, 3)
            let d = "#2a1610"
            eyes(face, 11, 11, P.eyes, d, "#ffffff")
            face(15, 15, "#e88a92"); face(16, 15, "#e88a92")
            face(14, 17, d); face(17, 17, d); face(15, 18, d); face(16, 18, d)
            for q in [(3, 15), (4, 15), (5, 15), (3, 18), (4, 17), (5, 17), (28, 15), (27, 15), (26, 15), (28, 18), (27, 17), (26, 17)] { face(q.0, q.1, "#ffe9c9") }
        case .dog:
            let up = P.tail != 0 ? 1 : 0
            for (i, t) in [(23, 26), (24, 24), (25, 22 - up), (26, 20 - up * 2), (26, 18 - up * 2)].enumerated() {
                g.R(i > 2 ? cream : dogFur, t.0, t.1 + J, t.0 + 1, t.1 + 1 + J)
            }
            g.E(dogFur, 8.5, 25.5 + D(J), 3.6, 3.6); g.E(dogFur, 23.5, 25.5 + D(J), 3.6, 3.6)
            g.E(dogFur, 16, 23 + D(J), 8.5, 6.5)
            g.E(cream, 16, 23 + D(J), 4.2, 4.8)
            g.R(dogCollar, 11, 20 + J, 20, 21 + J)
            g.R(dogGold, 15, 22 + J, 16, 23 + J)
            g.R(cream, 11, 22 + J, 14, 27 + P.al + J); g.E(cream, 12.5, 28 + D(P.al + J), 3.2, 2.2)
            g.R(cream, 17, 22 + J, 20, 27 + P.ar + J); g.E(cream, 19.5, 28 + D(P.ar + J), 3.2, 2.2)
            g.E(dogEar, 7.5 + D(hx), D(14 + hy + P.ears), 3.2, 6.2)
            g.E(dogEar, 24.5 + D(hx), D(14 + hy + P.ears), 3.2, 6.2)
            g.E(dogFur, D(16 + hx), D(13 + hy), 9.2, 7.5)
            g.E(cream, D(16 + hx), 16.8 + D(hy), 4.8, 3.4)
            g.R(dogNose, 15 + hx, 14 + hy, 16 + hx, 15 + hy)
            if P.tongue { g.R(dogTongue, 15 + hx, 18 + hy, 16 + hx, 19 + hy) }
            let d = "#2a1610"
            eyes(face, 11, 10, P.eyes, d, "#ffffff")
            face(11, 8, "#fff3dc"); face(12, 8, "#fff3dc"); face(19, 8, "#fff3dc"); face(20, 8, "#fff3dc")
            face(14, 17, d); face(17, 17, d); face(15, 16, d); face(16, 16, d)
        case .robot:
            g.R(joint, 11, 27 + J, 13, 29); g.R(joint, 18, 27 + J, 20, 29)
            g.RR(steel, 9, 19 + J, 22, 28 + J, 3)
            g.R(neck, 14, 17 + J, 17, 20 + J)
            g.E(joint, 7, 21 + D(J), 2.6, 2.6); g.RR(steel, 5, 21 + J, 8, 26 + P.al + J, 1); g.E(joint, 7, 27.5 + D(P.al + J), 2.2, 2)
            g.E(joint, 25, 21 + D(J), 2.6, 2.6); g.RR(steel, 23, 21 + J, 26, 26 + P.ar + J, 1); g.E(joint, 25, 27.5 + D(P.ar + J), 2.2, 2)
            g.R(joint, 15, 2 + hy, 16, 5 + hy); g.E(bulb, 16, 1.6 + D(hy), 1.8, 1.6)
            g.R(joint, 4 + hx, 9 + hy, 5 + hx, 13 + hy); g.R(joint, 26 + hx, 9 + hy, 27 + hx, 13 + hy)
            g.RR(steel, 6 + hx, 5 + hy, 25 + hx, 18 + hy, 3)
            g.RR(screen, 8 + hx, 7 + hy, 23 + hx, 16 + hy, 2)
            let a = "#ffd98a", lt = "#fff3c8"
            eyes(face, 11, 9, P.eyes == .sleep ? .blink : P.eyes, a, lt)
            for x in 14...17 { face(x, 14, P.eyes == .sleep ? "#7a6a45" : a) }
            ov(15, 22 + J, lt); ov(16, 22 + J, lt); ov(15, 23 + J, a); ov(16, 23 + J, a)
            for q in [(14, 22), (17, 22), (14, 23), (17, 23)] { ov(q.0, q.1 + J, "#5e6d82") }
        case .codex:
            g.RR(cxFoot, 9, 26 + J, 13, 29, 1); g.RR(cxFoot, 18, 26 + J, 22, 29, 1)
            g.RR(cxBody, 3, 12 + J + P.al, 5, 18 + J + P.al, 1); g.RR(cxBody, 26, 12 + J + P.ar, 28, 18 + J + P.ar, 1)
            g.RR(cxBody, 6, 5 + J, 25, 27 + J, 4)
            g.R(cxLed, 15, 7 + J, 16, 7 + J)
            g.RR(cxScreen, 9, 9 + J, 22, 19 + J, 1)
            let c = "#a8e6ff", lt = "#e4faff", Y = 11 + J
            switch P.eyes {
            case .sleep:
                for i in 11...13 { ov(i, 14 + J, "#46606a") }
                for i in 18...20 { ov(i, 14 + J, "#46606a") }
            case .happy:
                for q in [(10, 15), (11, 14), (12, 14), (13, 15), (18, 15), (19, 14), (20, 14), (21, 15)] { ov(q.0, q.1 + J, c) }
            default:
                let dy = P.eyes == .up ? -1 : 0, sq = P.eyes == .squint
                for q in [(11, 0), (12, 1), (13, 2), (12, 3), (11, 4)] where !(sq && (q.1 == 0 || q.1 == 4)) { ov(q.0, Y + q.1 + dy, c) }
                if P.eyes != .blink { for i in 16...20 { ov(i, 15 + J + dy, lt) } }
            }
            for q in [(12, 21), (11, 22), (10, 23), (11, 24), (12, 25)] { ov(q.0, q.1 + J, c) }
            for q in [(19, 21), (20, 22), (21, 23), (20, 24), (19, 25)] { ov(q.0, q.1 + J, c) }
            for q in [(17, 21), (17, 22), (16, 23), (15, 24), (15, 25)] { ov(q.0, q.1 + J, lt) }
        case .claude, .blob:
            let cx = D(16 + hx), cy = D(15 + hy)
            g.R(feet, 12, 27 + J, 14, 29); g.R(feet, 17, 27 + J, 19, 29)
            g.RR(torso, 11, 20 + J, 20, 28 + J, 3)
            g.RR(hand, 8, 22 + J, 10, 27 + P.al + J, 1); g.E(hand, 9, 28 + D(P.al + J), 2.4, 2.2)
            g.RR(hand, 21, 22 + J, 23, 27 + P.ar + J, 1); g.E(hand, 23, 28 + D(P.ar + J), 2.4, 2.2)
            let len: [Double] = [11, 12.5, 11.5, 13.5, 11.5, 12.5, 11]
            for k in 0..<7 {
                let th = (-90 + Double(k) * 30) * .pi / 180, s = sin(th), c = cos(th), f = 1 + Double(P.ray) * 0.08
                g.L(rays, cx + s * 8.4, cy - c * 8.4, cx + s * len[k] * f, cy - c * len[k] * f, thick: true)
            }
            g.E(clay, cx, cy, 8.8, 8.2)
            let d = "#2b150d"
            eyes(face, 12, 13, P.eyes, d, "#ffffff")
            for q in [(10, 17), (11, 17), (20, 17), (21, 17)] { face(q.0, q.1, "#f08a8a") }
            face(14, 17, d); face(15, 18, d); face(16, 18, d); face(17, 17, d)
            ov(15, 25 + J, "#fff0c8"); ov(16, 25 + J, "#fff0c8"); ov(15, 26 + J, "#ffd98a"); ov(16, 26 + J, "#ffd98a")
        }
    }

    // MARK: кадр

    /// Параметры кадра по состоянию и тику
    static func params(_ mood: PetMood, _ t: Int) -> P {
        var P = P()
        let blink = (t % 47) >= 44
        switch mood {
        case .idle:
            P.hy = (t / 9) % 2; P.eyes = blink ? .blink : .open; P.tail = (t / 6) % 2; P.ears = P.hy; P.ray = P.hy
            P.tongue = (t % 60) > 40
        case .thinking:
            P.hx = [0, 1, 0, -1][(t / 6) % 4]; P.hy = (t / 12) % 2; P.eyes = .up; P.ears = P.hy; P.tail = (t / 10) % 2; P.ray = P.hy
        case .writing:
            let a = (t / 2) % 2
            P.al = a != 0 ? 0 : -3; P.ar = a != 0 ? -3 : 0; P.hy = 1; P.eyes = .squint; P.tail = (t / 2) % 2; P.ears = 1; P.ray = a
        case .remember:
            let p = t % 30
            P.p = p
            P.eyes = p < 16 ? .happy : .open
            P.j = (p >= 2 && p <= 4) ? -2 : ((p == 1 || p == 5) ? -1 : 0)
            P.flash = p < 3 ? 0.55 : (p < 5 ? 0.25 : 0); P.tail = p % 2; P.ray = p < 6 ? 1 : 0
            P.al = p > 1 && p < 12 ? -2 : 0; P.ar = P.al; P.tongue = p < 16
        case .sleep:
            P.hy = 1 + (t / 15) % 2; P.eyes = .sleep; P.dim = true; P.ears = 1
        }
        return P
    }

    /// Неподвижный кадр, когда «меньше движения»: в нём видно состояние
    static func still(_ mood: PetMood) -> Int {
        switch mood {
        case .idle: 3
        case .thinking: 14
        case .writing: 7
        case .remember: 5
        case .sleep: 24
        }
    }

    struct Buf {
        var px = [UInt8](repeating: 0, count: W * H * 4)
        mutating func put(_ x: Int, _ y: Int, _ c: RGB, _ a: Double = 255) {
            guard x >= 0, y >= 0, x < W, y < H else { return }
            let i = (y * W + x) * 4
            func u(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
            px[i] = u(c.r); px[i + 1] = u(c.g); px[i + 2] = u(c.b); px[i + 3] = u(a)
        }
    }

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    static func ellPoints(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ fn: (Int, Int) -> Void) {
        for y in 0..<H {
            for x in 0..<W {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { fn(x, y) }
            }
        }
    }

    private static let ink = hex("#2a1a14"), paper = hex("#f5efe3")

    static func bubble(_ buf: inout Buf, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
        var mask = Set<Int>()
        ellPoints(cx, cy, rx, ry) { x, y in mask.insert(y * 1000 + x) }
        for k in mask {
            let x = k % 1000, y = k / 1000
            for d in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !mask.contains((y + d.1) * 1000 + x + d.0) { buf.put(x + d.0, y + d.1, ink) }
        }
        for k in mask { buf.put(k % 1000, k / 1000, paper) }
    }

    static func props(_ buf: inout Buf, _ mood: PetMood, _ t: Int, _ accent: String) {
        let acc = hex(accent), dk = lerp(acc, RGB(r: 0, g: 0, b: 0), 0.45)
        switch mood {
        case .thinking:
            bubble(&buf, 26, 4.6, 5.4, 3.4)
            let n = (t / 4) % 4
            for i in 0..<3 where i < n {
                buf.put(23 + i * 3, 5, dk); buf.put(24 + i * 3, 5, dk); buf.put(23 + i * 3, 4, acc); buf.put(24 + i * 3, 4, acc)
            }
        case .writing:
            let x0 = 20, y0 = 0, x1 = 29, y1 = 8
            for i in (x0 - 1)...(x1 + 1) {
                for k in max(0, y0 - 1)...(y1 + 1) {
                    let inside = i >= x0 && i <= x1 && k >= y0 && k <= y1
                    buf.put(i, k, inside ? (k == 0 ? acc : paper) : ink)
                }
            }
            let lens = [7, 4, 6], base = (t / 2) % 14
            for i in 0..<3 {
                let len = max(0, min(lens[i], base - i * 3 + 1))
                for k in 0..<len { buf.put(21 + k, 2 + i * 2, i == 2 && k == len - 1 && (t % 4 < 2) ? ink : dk) }
            }
        case .sleep:
            let zs = (t / 10) % 4, zc = hex("#cfe3ff"), zi = [(21, 8), (24, 4), (27, 0)]
            for i in 0..<min(3, zs) {
                let zx = zi[i].0, zy = zi[i].1 + 1
                for q in [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)] { buf.put(zx + q.0, zy + q.1, zc) }
            }
        default: break
        }
    }

    static func remember(_ buf: inout Buf, _ p: Int, _ accent: String, ring: Bool) {
        guard p >= 0 else { return }
        let acc = hex(accent), white = RGB(r: 255, g: 250, b: 235)
        if ring {
            guard p < 14 else { return }
            let r = 5 + Double(p) * 1.15, a = (255 * (1 - Double(p) / 14)).rounded()
            for y in 0..<H {
                for x in 0..<W {
                    let d = ((Double(x) + 0.5 - 16) * (Double(x) + 0.5 - 16) + (Double(y) + 0.5 - 17) * (Double(y) + 0.5 - 17)).squareRoot()
                    if abs(d - r) < 0.62 { buf.put(x, y, acc, a) }
                }
            }
            return
        }
        for (i, s) in [(4, 5), (27, 7), (3, 21), (28, 19)].enumerated() {
            let q = p - i * 2
            guard q >= 0, q <= 8 else { continue }
            buf.put(s.0, s.1, white)
            if q > 1 && q < 6 { buf.put(s.0 - 1, s.1, white); buf.put(s.0 + 1, s.1, white); buf.put(s.0, s.1 - 1, white); buf.put(s.0, s.1 + 1, white) }
        }
    }

    /// Кадр: RGBA 32×32 (не умноженный на прозрачность)
    static func frame(_ kind: PetKind, _ mood: PetMood, _ t: Int) -> [UInt8] {
        let sp = spec(kind), P = params(mood, t), g = Grid()
        var ovs: [(Int, Int, RGB)] = []
        paint(kind, g, P) { x, y, c in if x >= 0, y >= 0, x < W, y < H { ovs.append((x, y, hex(c))) } }
        // свет сверху слева, тень снизу справа, обводка снаружи
        var out = [RGB?](repeating: nil, count: W * H)
        for y in 0..<H {
            for x in 0..<W {
                guard let c = g.c[y * W + x] else { continue }
                func edge(_ n: Cell?) -> Bool { n == nil || n!.id != c.id }
                let lightEdge = edge(g.cell(x, y - 1)) || edge(g.cell(x - 1, y))
                let darkEdge = edge(g.cell(x, y + 1)) || edge(g.cell(x + 1, y))
                let below = g.cell(x, y + 1)
                let dark2 = below != nil && below!.id == c.id && edge(g.cell(x, y + 2))
                var col = c.m.m
                if darkEdge && !lightEdge { col = c.m.d } else if lightEdge && !darkEdge { col = c.m.l } else if dark2 && !lightEdge { col = c.m.d }
                out[y * W + x] = col
            }
        }
        let olc = hex(sp.ol)
        for y in 0..<H {
            for x in 0..<W where g.c[y * W + x] == nil {
                if g.cell(x - 1, y) != nil || g.cell(x + 1, y) != nil || g.cell(x, y - 1) != nil || g.cell(x, y + 1) != nil { out[y * W + x] = olc }
            }
        }
        for o in ovs { out[o.1 * W + o.0] = o.2 }
        var buf = Buf()
        ellPoints(16, 29.6, 10, 1.7) { x, y in buf.put(x, y, RGB(r: 0, g: 0, b: 0), 70) }
        if mood == .remember { remember(&buf, P.p, sp.accent, ring: true) }
        for y in 0..<H {
            for x in 0..<W {
                guard var c = out[y * W + x] else { continue }
                if P.flash > 0 { c = lerp(c, RGB(r: 255, g: 250, b: 235), P.flash) }
                if P.dim {
                    let gr = (c.r + c.g + c.b) / 3
                    c = lerp(RGB(r: gr, g: gr, b: gr), c, 0.45)
                    c = lerp(c, RGB(r: 24, g: 30, b: 60), 0.3)
                    c = RGB(r: c.r * 0.66, g: c.g * 0.66, b: c.b * 0.7)
                }
                buf.put(x, y, c)
            }
        }
        props(&buf, mood, t, sp.accent)
        if mood == .remember { remember(&buf, P.p, sp.accent, ring: false) }
        return buf.px
    }

    // MARK: картинка

    @MainActor private static var cache: [String: CGImage] = [:]

    @MainActor static func image(_ kind: PetKind, _ mood: PetMood, _ t: Int) -> CGImage {
        let key = "\(kind.rawValue)|\(mood.rawValue)|\(t % 2820)"
        if let img = cache[key] { return img }
        var px = frame(kind, mood, t % 2820)
        // CGImage ждёт цвет, умноженный на прозрачность
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] < 255 {
            let a = Double(px[i + 3]) / 255
            px[i] = UInt8(Double(px[i]) * a); px[i + 1] = UInt8(Double(px[i + 1]) * a); px[i + 2] = UInt8(Double(px[i + 2]) * a)
        }
        let data = Data(px) as CFData
        let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        if cache.count > 3000 { cache.removeAll() }
        cache[key] = img
        return img
    }
}

/// Пиксельный питомец: 10 кадров в секунду, без сглаживания пикселей
struct PixelPetView: View {
    let kind: PetKind
    var mood: PetMood = .idle
    var size: CGFloat = 64
    var animated = true

    @Environment(\.lessMotion) private var lessMotion
    @State private var start = Date()

    var body: some View {
        let still = !animated || lessMotion
        TimelineView(.animation(minimumInterval: 0.1, paused: still)) { ctx in
            let t = still ? PixelPet.still(mood) : max(0, Int(ctx.date.timeIntervalSince(start) * 10))
            Image(decorative: PixelPet.image(kind, mood, t), scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: size, height: size)
        }
        .onChange(of: mood) { start = Date() }
        .accessibilityHidden(true)
    }
}
