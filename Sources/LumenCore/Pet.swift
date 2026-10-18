import Foundation

/// Питомец Lumen (1.5): пять пиксельных зверей или глянцевая капля. Живёт поверх окон и вместо точек «работает»
/// показывает, что сейчас делает Lumen. У ботов вместо значка — своя капля (`Bot.look`).
public enum PetKind: String, Codable, Sendable, CaseIterable, Hashable {
    case cat, dog, robot, codex, claude, blob

    public var name: String {
        switch self {
        case .cat: "Кот"
        case .dog: "Собака"
        case .robot: "Робот"
        case .codex: "Кодекс"
        case .claude: "Клод"
        case .blob: "Капля"
        }
    }

    public var note: String {
        switch self {
        case .cat: "Рыжий, с полосками на лбу, усами и белыми лапками"
        case .dog: "Висячие уши, бирюзовый ошейник с биркой, язык"
        case .robot: "Экран вместо лица, ядро на груди, руки на шарнирах"
        case .codex: "Терминал вместо лица: глаза — «>_», на груди «</>»"
        case .claude: "Корона из лучей, тёплые щёки, огонёк на животе"
        case .blob: "Глянцевая капля: форма, лицо и цвет — свои"
        }
    }

    public var isPixel: Bool { self != .blob }
}

/// Форма капли. `egg` в выборе нет — в неё капля превращается в состоянии «Яйцо»
public enum BlobShape: String, Codable, Sendable, CaseIterable, Hashable {
    case circle, pebble, squircle, capsule, triangle, hexagon, cloud, droplet

    public var name: String {
        switch self {
        case .circle: "Круг"
        case .pebble: "Галька"
        case .squircle: "Квадрат"
        case .capsule: "Капсула"
        case .triangle: "Треугольник"
        case .hexagon: "Шестиугольник"
        case .cloud: "Облако"
        case .droplet: "Капля"
        }
    }
}

/// Лицо капли: глаза-блики разной формы
public enum BlobFace: String, Codable, Sendable, CaseIterable, Hashable {
    case neutral, attentive, surprised, excited, happy, laughing, angry, sad
    case scared, suspicious, confused, curious, proud, shy, unimpressed, sleepy

    public var name: String {
        switch self {
        case .neutral: "Спокойный"
        case .attentive: "Внимательный"
        case .surprised: "Удивлён"
        case .excited: "Рад"
        case .happy: "Доволен"
        case .laughing: "Смеётся"
        case .angry: "Злится"
        case .sad: "Грустит"
        case .scared: "Боится"
        case .suspicious: "Подозревает"
        case .confused: "Не понял"
        case .curious: "Любопытный"
        case .proud: "Гордый"
        case .shy: "Смущён"
        case .unimpressed: "Не впечатлён"
        case .sleepy: "Сонный"
        }
    }
}

/// Как выглядит капля: форма, лицо, цвет (#rrggbb)
public struct BlobLook: Codable, Sendable, Equatable, Hashable {
    public var shape: BlobShape
    public var face: BlobFace
    public var color: String

    public init(shape: BlobShape = .circle, face: BlobFace = .attentive, color: String = "#eab04a") {
        self.shape = shape
        self.face = face
        self.color = color
    }

    /// Цвета на выбор: янтарь — свет Lumen, глина и лёд — как у Claude и Codex
    public static let palette: [(hex: String, name: String)] = [
        ("#eab04a", "Янтарь"), ("#2f2a27", "Графит"), ("#d97757", "Глина"), ("#6cc8e8", "Лёд"),
        ("#ee6a5a", "Коралл"), ("#f08a3a", "Апельсин"), ("#f1cf3a", "Лимон"), ("#4fcf9a", "Мята"),
        ("#2f9e7a", "Хвоя"), ("#4a8df0", "Небо"), ("#e86fa5", "Роза"), ("#efe7d8", "Молоко"),
    ]

    /// Оттенок цвета 0…360 — по нему у бота подсвечиваются подписи и рамки
    public var hue: Double {
        let (r, g, b) = BlobLook.rgb(color)
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0.0001 else { return 30 }
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return h
    }

    /// Капля для бота, у которого её ещё нет: цвет по его оттенку, форма — по id (у разных ботов разная)
    public static func forBot(id: String, hue: Double) -> BlobLook {
        let shapes: [BlobShape] = [.circle, .squircle, .pebble, .hexagon, .cloud, .droplet, .capsule, .triangle]
        let n = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return BlobLook(shape: shapes[n % shapes.count], face: .attentive, color: hexFromHue(hue))
    }

    /// #rrggbb для оттенка: насыщенный, но не кислотный — как цвета палитры
    public static func hexFromHue(_ hue: Double) -> String {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = 0.62, v = 0.9
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        func hx(_ v: Double) -> String { String(format: "%02x", Int(((v + m) * 255).rounded())) }
        return "#" + hx(r) + hx(g) + hx(b)
    }

    /// r, g, b в 0…1
    public static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.92, 0.69, 0.29) }
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
}

/// Размер питомца поверх окон
public enum PetSize: String, Codable, Sendable, CaseIterable, Hashable {
    case small, medium, large

    public var points: Double {
        switch self {
        case .small: 96
        case .medium: 128
        case .large: 160
        }
    }
}

/// Настройки питомца (Настройки → Внешний вид → Питомец)
public struct PetPrefs: Codable, Sendable, Equatable {
    /// Питомец включён
    public var enabled = false
    public var kind = PetKind.cat
    /// Как выглядит капля, если выбрана она
    public var blob = BlobLook()
    /// Сидит поверх всех окон (маленькое окно без рамки, его можно перетащить)
    public var floating = true
    /// Вместо точек «работает» в переписке
    public var inChat = true
    public var size = PetSize.medium

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        kind = (try? c.decodeIfPresent(PetKind.self, forKey: .kind)) ?? .cat
        blob = (try? c.decodeIfPresent(BlobLook.self, forKey: .blob)) ?? BlobLook()
        floating = (try? c.decodeIfPresent(Bool.self, forKey: .floating)) ?? true
        inChat = (try? c.decodeIfPresent(Bool.self, forKey: .inChat)) ?? true
        size = (try? c.decodeIfPresent(PetSize.self, forKey: .size)) ?? .medium
    }
}

extension Bot {
    /// Капля бота: своя, если выбрана в конструкторе, иначе по оттенку и id
    public var blobLook: BlobLook { look ?? BlobLook.forBot(id: id, hue: hue) }
}
