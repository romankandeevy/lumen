import Foundation

/// Раскладка графа физикой, как d3-force в макете: связи тянут, узлы отталкиваются, всё стягивается к центру,
/// «ты» закреплён в середине. Отталкивание считается только между соседями по сетке — так 1000 фактов
/// раскладываются за доли секунды. Когда движение затихает (`alpha` падает), счёт останавливается.
public struct GraphLayout: Sendable {
    public var positions: [SIMD2<Double>]
    private var velocity: [SIMD2<Double>]
    public private(set) var alpha = 1.0
    public var radius: [Double]
    /// Узлы, которые держит рука (перетаскивание) — их не двигает физика
    public var pinned: [Int: SIMD2<Double>] = [:]

    private let links: [MemoryGraph.Link]
    private let charge: [Double]
    private let isEntity: [Bool]
    private let entityIndices: [Int]

    public init(graph: MemoryGraph) {
        let n = graph.nodes.count
        links = graph.links
        radius = graph.nodes.map { node in
            switch node.group {
            case .me: 15
            case .fact, .decision: 3.5 + Double(min(node.degree, 4)) * 0.6
            default: 6 + Double(min(node.degree, 10)) * 0.7
            }
        }
        charge = graph.nodes.map { node in
            switch node.group {
            case .me: -700
            case .fact, .decision: -90
            default: -280
            }
        }
        let ent = graph.nodes.map { $0.group != .fact && $0.group != .decision }
        isEntity = ent
        entityIndices = ent.indices.filter { ent[$0] }
        // начальная раскладка — подсолнух: без случайности, одинаково при каждом открытии
        positions = (0..<n).map { i in
            guard i > 0 else { return .zero }
            let r = 10 * sqrt(Double(i)) * 3
            let a = Double(i) * 2.399963
            return SIMD2(r * cos(a), r * sin(a))
        }
        velocity = Array(repeating: .zero, count: n)
    }

    public var settled: Bool { alpha < 0.005 }

    /// Разбудить после перетаскивания или смены данных
    public mutating func reheat(_ to: Double = 0.3) { alpha = max(alpha, to) }

    /// Один шаг. `decay` как у d3 (0.025 → ~300 шагов до покоя)
    public mutating func tick(decay: Double = 0.025) {
        let n = positions.count
        guard n > 1 else { alpha = 0; return }

        // связи: пружины своей длины и жёсткости
        for l in links {
            let (dist, strength): (Double, Double) = switch l.kind {
            case .core: (170, 0.35)
            case .own: (l.a == 0 ? 95 : 52, 0.9)
            case .cross: (130, 0.05)
            }
            var d = positions[l.b] + velocity[l.b] - positions[l.a] - velocity[l.a]
            var len = (d * d).sum().squareRoot()
            if len < 1e-6 { d = SIMD2(0.01, 0.01); len = 0.014 }
            let k = (len - dist) / len * alpha * strength
            let move = d * k
            // лёгкий конец двигается сильнее (как bias в d3: по числу связей)
            velocity[l.b] -= move * 0.5
            velocity[l.a] += move * 0.5
        }

        // отталкивание: плоская сетка (сортировка подсчётом), считаем только соседние клетки
        let cell = 64.0
        var minP = positions[0], maxP = positions[0]
        for q in positions { minP = pointwiseMin(minP, q); maxP = pointwiseMax(maxP, q) }
        let gw = min(512, Int((maxP.x - minP.x) / cell) + 1), gh = min(512, Int((maxP.y - minP.y) / cell) + 1)
        var cellOf = [Int](repeating: 0, count: n)
        var start = [Int](repeating: 0, count: gw * gh + 1)
        for i in 0..<n {
            let cx = min(gw - 1, Int((positions[i].x - minP.x) / cell)), cy = min(gh - 1, Int((positions[i].y - minP.y) / cell))
            cellOf[i] = cy * gw + cx
            start[cellOf[i] + 1] += 1
        }
        for c in 0..<(gw * gh) { start[c + 1] += start[c] }
        var fill = start
        var items = [Int](repeating: 0, count: n)
        for i in 0..<n { items[fill[cellOf[i]]] = i; fill[cellOf[i]] += 1 }

        // сущностей мало (проекты, люди) — между ними отталкивание на любом расстоянии, чтобы разошлись по кругу
        let ents = entityIndices
        for i in ents { for j in ents where j != i {
            var d = positions[i] - positions[j]
            var l2 = (d * d).sum()
            if l2 < 1e-6 { d = SIMD2(Double(i - j) * 0.01, 0.01); l2 = 1e-4 }
            velocity[i] += d * (-charge[j] * alpha / l2)
            let minD = radius[i] + radius[j] + 16
            let len = l2.squareRoot()
            if len < minD { velocity[i] += d * ((minD - len) / len * 0.5) }
        } }

        // каждая пара встречается дважды (от i и от j) — каждый раз двигаем только i
        positions.withUnsafeBufferPointer { pos in
        radius.withUnsafeBufferPointer { rad in
        velocity.withUnsafeMutableBufferPointer { vel in
            for i in 0..<n {
                let c = cellOf[i], cx = c % gw, cy = c / gw
                let pi = pos[i], ri = rad[i], ent = isEntity[i]
                var v = SIMD2<Double>.zero
                for yy in max(0, cy - 1)...min(gh - 1, cy + 1) {
                    for xx in max(0, cx - 1)...min(gw - 1, cx + 1) {
                        let cc = yy * gw + xx
                        for t in start[cc]..<start[cc + 1] {
                            let j = items[t]
                            if j == i || (ent && isEntity[j]) { continue }
                            var d = pi - pos[j]
                            var l2 = d.x * d.x + d.y * d.y
                            if l2 < 1e-6 { d = SIMD2(Double(i - j) * 0.01, 0.01); l2 = 1e-4 }
                            // отталкивание как у d3: заряд / расстояние²
                            v += d * (-charge[j] * alpha / l2)
                            // столкновение: не налезать друг на друга
                            let minD = ri + rad[j] + 12
                            if l2 < minD * minD {
                                let len = l2.squareRoot()
                                v += d * ((minD - len) / len * 0.5)
                            }
                        }
                    }
                }
                vel[i] += v
            }
        } } }

        // к центру и шаг с трением
        for i in 0..<n {
            velocity[i] -= positions[i] * SIMD2(0.03, 0.04) * alpha
            if i == 0 { positions[0] = .zero; velocity[0] = .zero; continue }
            if let p = pinned[i] { positions[i] = p; velocity[i] = .zero; continue }
            velocity[i] *= 0.6
            positions[i] += velocity[i]
        }
        alpha += (0 - alpha) * decay
    }

    /// Сразу до покоя — для «Меньше движения» и тестов
    public mutating func settle(maxTicks: Int = 400) {
        var t = 0
        while !settled && t < maxTicks { tick(); t += 1 }
    }

    /// Ближайший узел к точке (в координатах графа)
    public func node(at p: SIMD2<Double>, slop: Double) -> Int? {
        var best: Int?
        var bestD = Double.infinity
        for (i, q) in positions.enumerated() {
            let d = ((q - p) * (q - p)).sum().squareRoot()
            if d < radius[i] + slop && d < bestD { best = i; bestD = d }
        }
        return best
    }
}
