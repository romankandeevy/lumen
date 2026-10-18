import Foundation

// Питомец — картинка из простых фигур. Пресет или модель задаёт фигуры, роли и цвета; движения у ролей
// одни на все питомцы (PetView в LumenUI). Поэтому описание короткое и безопасное: ни скриптов, ни ссылок,
// ни внешних картинок — только числа и цвета.

/// Настроение питомца: из состояния агента и тишины
public enum PetMood: String, Codable, Sendable, CaseIterable {
    case idle, thinking, writing, happy, sleep
}

/// Фигура: эллипс, прямоугольник со скруглением или треугольник с вершиной сверху
public enum PetShape: String, Codable, Sendable {
    case ellipse, rect, triangle
}

/// Роль — что за часть и какое движение ей достаётся: тело дышит, хвост виляет, глаза моргают, уши хлопают
public enum PetRole: String, Codable, Sendable {
    case body, head, eye, ear, tail, accent
}

/// Одна фигура. Координаты в поле 100×100, y сверху вниз, как в SVG
public struct PetPart: Codable, Sendable, Equatable {
    public var shape: PetShape
    public var role: PetRole
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    /// Поворот вокруг центра, градусы
    public var rotation: Double
    /// `#RRGGBB`
    public var color: String
    /// Скругление прямоугольника
    public var radius: Double

    public init(shape: PetShape, role: PetRole = .accent, x: Double, y: Double, w: Double, h: Double,
                rotation: Double = 0, radius: Double = 0, color: String) {
        self.shape = shape
        self.role = role
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.rotation = rotation
        self.radius = radius
        self.color = color
    }

    // модель может не написать роль, поворот или скругление: берём безопасные значения
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = try c.decode(PetShape.self, forKey: .shape)
        role = try c.decodeIfPresent(PetRole.self, forKey: .role) ?? .accent
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        w = try c.decode(Double.self, forKey: .w)
        h = try c.decode(Double.self, forKey: .h)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        color = try c.decode(String.self, forKey: .color)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0
    }
}

/// Питомец: имя и фигуры. `id` — пресет (`cat`, `robot`…) или `custom` для нарисованного
public struct PetSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var parts: [PetPart]

    public init(id: String, name: String, parts: [PetPart]) {
        self.id = id
        self.name = name
        self.parts = parts
    }

    public static let maxParts = 40
    public static let maxNameLength = 40

    /// Что не так с питомцем. Пусто — можно показывать и сохранять
    public var problems: [String] {
        var out: [String] = []
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > Self.maxNameLength { out.append("имя от 1 до \(Self.maxNameLength) знаков") }
        if parts.isEmpty { out.append("нет ни одной фигуры") }
        if parts.count > Self.maxParts { out.append("фигур больше \(Self.maxParts)") }
        if !parts.contains(where: { $0.role == .body }) { out.append("нет тела: нужна фигура с ролью body") }
        for (i, p) in parts.enumerated() {
            let n = i + 1
            if !(p.w > 0 && p.w <= 100 && p.h > 0 && p.h <= 100) { out.append("фигура \(n): размер больше 0 и до 100") }
            if !((-10...110).contains(p.x) && (-10...110).contains(p.y)) { out.append("фигура \(n): положение за полем") }
            if !p.rotation.isFinite || abs(p.rotation) > 360 { out.append("фигура \(n): поворот от -360 до 360") }
            if !(0...50).contains(p.radius) { out.append("фигура \(n): скругление от 0 до 50") }
            if !Self.isHex(p.color) { out.append("фигура \(n): цвет не в виде #RRGGBB") }
        }
        return out
    }

    /// Ответ модели → питомец. JSON ищем внутри текста: модель может обернуть его словами или ```
    public static func parse(_ text: String, id: String = "custom") -> Result<PetSpec, [String]> {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return .failure(["в ответе нет JSON"])
        }
        let draft: Draft
        do {
            draft = try JSONDecoder().decode(Draft.self, from: Data(text[start...end].utf8))
        } catch {
            return .failure(["JSON не по схеме: \(error.localizedDescription)"])
        }
        let spec = PetSpec(id: id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), parts: draft.parts)
        let found = spec.problems
        return found.isEmpty ? .success(spec) : .failure(found)
    }

    /// Правила для модели, которая рисует питомца (SkillModel и PetModel.draftPet)
    public static let authoringRules = """
    Поле 100×100, y сверху вниз. Фигуры: ellipse, rect (с radius для скругления), triangle (вершина сверху). \
    Роли: body — тело (обязательно), head — голова, eye — глаза (парами), ear — уши, tail — хвост, accent — деталь. \
    Цвета #RRGGBB, 3–5 цветов. 8–25 фигур. Персонаж простой и узнаваемый, без текста и букв. \
    Не копируй логотипы и маскоты брендов: придумай свой образ.
    """

    private struct Draft: Decodable {
        let name: String
        let parts: [PetPart]
    }

    private static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// Встроенные питомцы. Рисунки простые: тело, голова, глаза, уши, хвост
public enum PetPresets {
    public static let all: [PetSpec] = [cat, robot, dog, claude, codex]

    public static func named(_ id: String) -> PetSpec? { all.first { $0.id == id } }

    static let cat = PetSpec(id: "cat", name: "Кот", parts: [
        PetPart(shape: .ellipse, role: .tail, x: 72, y: 62, w: 22, h: 9, rotation: -30, color: "#E8914A"),
        PetPart(shape: .ellipse, role: .body, x: 20, y: 46, w: 60, h: 46, color: "#F2A65A"),
        PetPart(shape: .ellipse, role: .head, x: 22, y: 18, w: 56, h: 44, color: "#F2A65A"),
        PetPart(shape: .triangle, role: .ear, x: 24, y: 4, w: 18, h: 24, color: "#F2A65A"),
        PetPart(shape: .triangle, role: .ear, x: 58, y: 4, w: 18, h: 24, color: "#F2A65A"),
        PetPart(shape: .ellipse, role: .eye, x: 34, y: 36, w: 8, h: 10, color: "#2B1D16"),
        PetPart(shape: .ellipse, role: .eye, x: 58, y: 36, w: 8, h: 10, color: "#2B1D16"),
        PetPart(shape: .ellipse, role: .accent, x: 46, y: 50, w: 8, h: 5, color: "#D9643A"),
    ])

    static let robot = PetSpec(id: "robot", name: "Робот", parts: [
        PetPart(shape: .rect, role: .accent, x: 47, y: 2, w: 6, h: 12, color: "#9AA5B1"),
        PetPart(shape: .ellipse, role: .accent, x: 42, y: 0, w: 16, h: 12, color: "#F87171"),
        PetPart(shape: .rect, role: .body, x: 18, y: 32, w: 64, h: 52, radius: 14, color: "#9AA5B1"),
        PetPart(shape: .rect, role: .head, x: 24, y: 14, w: 52, h: 30, radius: 9, color: "#C9D1D9"),
        PetPart(shape: .ellipse, role: .eye, x: 33, y: 22, w: 13, h: 13, color: "#38BDF8"),
        PetPart(shape: .ellipse, role: .eye, x: 54, y: 22, w: 13, h: 13, color: "#38BDF8"),
        PetPart(shape: .rect, role: .accent, x: 38, y: 56, w: 24, h: 5, radius: 2, color: "#5B6670"),
    ])

    static let dog = PetSpec(id: "dog", name: "Собака", parts: [
        PetPart(shape: .ellipse, role: .tail, x: 76, y: 50, w: 9, h: 24, rotation: 25, color: "#C98B4B"),
        PetPart(shape: .ellipse, role: .body, x: 20, y: 50, w: 60, h: 42, color: "#C98B4B"),
        PetPart(shape: .ellipse, role: .head, x: 26, y: 16, w: 48, h: 42, color: "#D9A066"),
        PetPart(shape: .ellipse, role: .ear, x: 12, y: 22, w: 20, h: 36, rotation: 15, color: "#8B5A2B"),
        PetPart(shape: .ellipse, role: .ear, x: 68, y: 22, w: 20, h: 36, rotation: -15, color: "#8B5A2B"),
        PetPart(shape: .ellipse, role: .eye, x: 38, y: 34, w: 7, h: 8, color: "#1F1F1F"),
        PetPart(shape: .ellipse, role: .eye, x: 55, y: 34, w: 7, h: 8, color: "#1F1F1F"),
        PetPart(shape: .ellipse, role: .accent, x: 42, y: 46, w: 16, h: 12, color: "#F3E0C4"),
        PetPart(shape: .ellipse, role: .accent, x: 48, y: 46, w: 6, h: 4, color: "#1F1F1F"),
    ])

    static let claude = PetSpec(id: "claude", name: "Клод", parts: [
        PetPart(shape: .ellipse, role: .body, x: 16, y: 26, w: 68, h: 64, color: "#E9A07A"),
        PetPart(shape: .triangle, role: .ear, x: 42, y: 2, w: 16, h: 18, color: "#F6D365"),
        PetPart(shape: .ellipse, role: .eye, x: 34, y: 46, w: 8, h: 12, color: "#2B1D16"),
        PetPart(shape: .ellipse, role: .eye, x: 58, y: 46, w: 8, h: 12, color: "#2B1D16"),
        PetPart(shape: .ellipse, role: .accent, x: 24, y: 60, w: 12, h: 7, color: "#F5C2A8"),
        PetPart(shape: .ellipse, role: .accent, x: 64, y: 60, w: 12, h: 7, color: "#F5C2A8"),
    ])

    static let codex = PetSpec(id: "codex", name: "Кодекс", parts: [
        PetPart(shape: .rect, role: .body, x: 14, y: 22, w: 72, h: 60, radius: 14, color: "#1F2937"),
        PetPart(shape: .rect, role: .head, x: 22, y: 32, w: 56, h: 38, radius: 6, color: "#0F172A"),
        PetPart(shape: .triangle, role: .eye, x: 30, y: 42, w: 12, h: 14, rotation: 90, color: "#34D399"),
        PetPart(shape: .rect, role: .eye, x: 52, y: 58, w: 18, h: 5, radius: 2, color: "#34D399"),
    ])
}
