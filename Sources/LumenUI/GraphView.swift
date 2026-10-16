import AppKit
import LumenCore
import Observation
import SwiftUI

// Граф памяти (`components/memory-graph.tsx`) — как Graph View в Obsidian:
// физика раскладывает узлы, размер — по числу связей, наведение подсвечивает соседей,
// колесо и щипок — зум, фон тянется, узлы перетаскиваются, двойной щелчок — окрестность узла.
// Физика считает, только пока граф движется; успокоился — ни одного кадра.

@MainActor @Observable
final class GraphModel {
    private(set) var graph: MemoryGraph
    private(set) var layout: GraphLayout
    private(set) var neighbors: [Set<Int>]
    /// Меняется на каждом шаге физики — по нему холст перерисовывается
    private(set) var frame = 0
    var hidden: Set<MemoryGraph.Group> = []
    var local: Int?
    var selected: Int? = 0
    var hover: Int?
    var labels = false
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored var lessMotion = false

    init(graph: MemoryGraph) {
        self.graph = graph
        layout = GraphLayout(graph: graph)
        neighbors = graph.neighbors
    }

    /// Данные поменялись (новый факт) — новый граф, старые позиции не сохраняем: раскладка быстрая
    func update(_ g: MemoryGraph) {
        guard g != graph else { return }
        graph = g
        layout = GraphLayout(graph: g)
        neighbors = g.neighbors
        if let s = selected, s >= g.nodes.count { selected = nil }
        local = nil
        run()
    }

    /// Какие узлы видны: фильтры групп и окрестность
    var visible: Set<Int> {
        var keep = Set(graph.nodes.indices.filter { !hidden.contains(graph.nodes[$0].group) })
        if let local { keep.formIntersection(graph.around(local)) }
        keep.insert(0)
        return keep
    }

    func run() {
        runner?.cancel()
        if lessMotion {
            layout.settle()
            frame += 1
            return
        }
        runner = Task { [weak self] in
            while let self, !Task.isCancelled, !self.layout.settled {
                // несколько шагов на кадр: раскладка складывается быстро, но плавно
                for _ in 0..<2 { self.layout.tick() }
                self.frame += 1
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stop() { runner?.cancel() }

    // MARK: координаты

    func toGraph(_ p: CGPoint, in size: CGSize) -> SIMD2<Double> {
        SIMD2(Double((p.x - size.width / 2 - offset.width) / scale), Double((p.y - size.height / 2 - offset.height) / scale))
    }

    func toScreen(_ q: SIMD2<Double>, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(q.x) * scale + size.width / 2 + offset.width, y: CGFloat(q.y) * scale + size.height / 2 + offset.height)
    }

    func pick(_ p: CGPoint, in size: CGSize) -> Int? {
        guard let i = layout.node(at: toGraph(p, in: size), slop: 6 / Double(scale)) else { return nil }
        return visible.contains(i) ? i : nil
    }

    func zoom(by f: CGFloat, at p: CGPoint? = nil, in size: CGSize) {
        let k = min(4, max(0.35, scale * f))
        let m = p.map { CGPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2) } ?? .zero
        offset = CGSize(width: m.x - (m.x - offset.width) * k / scale, height: m.y - (m.y - offset.height) * k / scale)
        scale = k
    }

    func center(on i: Int? = nil) {
        if let i {
            let k = max(scale, 1.4)
            let q = layout.positions[i]
            offset = CGSize(width: -CGFloat(q.x) * k, height: -CGFloat(q.y) * k)
            scale = k
        } else {
            offset = .zero
            scale = 1
        }
    }

    func drag(_ i: Int, to p: SIMD2<Double>) {
        guard i != 0 else { return }
        layout.pinned[i] = p
        layout.positions[i] = p
        layout.reheat(0.25)
        if runner == nil || layout.settled || runner?.isCancelled == true { run() } else { frame += 1 }
    }

    func release(_ i: Int) {
        layout.pinned[i] = nil
        layout.reheat(0.1)
        run()
    }

    /// Факты выбранного узла: сам факт или все факты про сущность
    func facts(of i: Int) -> [MemoryFact] {
        if let f = graph.nodes[i].fact { return [f] }
        return neighbors[i].sorted().compactMap { graph.nodes[$0].fact }
    }

    func find(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty, let i = graph.nodes.indices.first(where: { visible.contains($0) && graph.nodes[$0].name.lowercased().contains(s) }) else { return }
        selected = i
        center(on: i)
    }
}

struct GraphView: View {
    @Bindable var app: AppModel
    let model: GraphModel

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion
    @State private var query = ""
    @State private var dragging: Int?
    @State private var panStart: CGSize?
    @State private var size: CGSize = .zero
    @State private var monitor: Any?
    @State private var inside = false

    private let personColor = Color(hue: 200 / 360, saturation: 0.35, brightness: 0.9)

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                DotGrid().allowsHitTesting(false)
                canvas(g.size)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(g.size))
                    .onTapGesture(count: 2, coordinateSpace: .local) { loc in
                        if let i = model.pick(loc, in: g.size) { focusLocal(i) }
                    }
                    .onTapGesture(count: 1, coordinateSpace: .local) { loc in model.selected = model.pick(loc, in: g.size) }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let loc):
                            inside = true
                            let i = model.pick(loc, in: g.size)
                            if i != model.hover { model.hover = i }
                        case .ended:
                            inside = false
                            model.hover = nil
                        }
                    }
                // края темнее — как виньетка в макете
                RadialGradient(colors: [.clear, p.background.opacity(0.9)], center: .center, startRadius: min(g.size.width, g.size.height) * 0.35,
                               endRadius: max(g.size.width, g.size.height) * 0.75)
                    .allowsHitTesting(false)
                controls.padding(12)
                if let local = model.local { localBanner(local).frame(maxWidth: .infinity).padding(.top, 12) }
                if let s = model.selected, s < model.graph.nodes.count { card(s).frame(maxWidth: .infinity, alignment: .trailing).padding(12) }
                if let h = model.hover, let f = model.graph.nodes[h].fact, model.selected != h {
                    Text(f.text).tw(12, lh: 16).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(p.popover.opacity(0.92), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                        .frame(maxWidth: 420, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(12)
                        .allowsHitTesting(false)
                }
                Text("Колесо — зум · тяни фон или узел · двойной щелчок — окрестность")
                    .tw(11, lh: 14).foregroundStyle(p.mutedFg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
                    .allowsHitTesting(false)
            }
            .onAppear { size = g.size; frameOrigin = g.frame(in: .global).origin }
            .onChange(of: g.size) { _, s in size = s; frameOrigin = g.frame(in: .global).origin }
        }
        .background(Color.black.opacity(0.08))
        .background(p.background)
        .clipShape(RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.border))
        .onAppear {
            model.lessMotion = lessMotion
            model.run()
            installMonitor()
        }
        .onDisappear {
            model.stop()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    // MARK: рисование

    private func canvas(_ size: CGSize) -> some View {
        let _ = model.frame // перерисовка на каждом шаге физики
        let graph = model.graph
        let pos = model.layout.positions
        let radius = model.layout.radius
        let visible = model.visible
        let focus = model.hover
        let near = focus.map { model.neighbors[$0] } ?? []
        let selected = model.selected
        let k = model.scale
        let glow = p.glow, fg = p.foreground, bg = p.background, person = personColor
        let labels = model.labels
        let offset = model.offset
        return Canvas { ctx, sz in
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(pos[i].x) * k + sz.width / 2 + offset.width, y: CGFloat(pos[i].y) * k + sz.height / 2 + offset.height)
            }
            func lit(_ i: Int) -> Bool { focus == nil || i == focus || near.contains(i) }

            // рёбра
            for l in graph.links where visible.contains(l.a) && visible.contains(l.b) {
                var path = Path()
                path.move(to: pt(l.a))
                path.addLine(to: pt(l.b))
                let on = focus.map { l.a == $0 || l.b == $0 } ?? true
                let base: Double = switch l.kind { case .core: 0.28; case .own: 0.22; case .cross: 0.12 }
                let alpha = focus == nil ? base : (on ? 0.7 : 0.04)
                let color = l.kind == .cross ? person : glow
                ctx.stroke(path, with: .color(color.opacity(alpha)),
                           style: StrokeStyle(lineWidth: (on && focus != nil ? 1.4 : 1), dash: l.kind == .cross ? [3, 4] : []))
            }

            // узлы
            for i in graph.nodes.indices where visible.contains(i) {
                let n = graph.nodes[i]
                let c = pt(i)
                let r = CGFloat(radius[i]) * k
                let on = lit(i)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                switch n.group {
                case .me:
                    let halo = r * 3.2
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                             with: .radialGradient(Gradient(colors: [glow.opacity(on ? 0.35 : 0.08), .clear]), center: c, startRadius: 0, endRadius: halo))
                    ctx.fill(Path(ellipseIn: rect), with: .color(glow.opacity(on ? 1 : 0.2)))
                case .fact, .decision:
                    let color = n.group == .fact ? fg.opacity(0.55) : glow.opacity(0.85)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(on ? 1 : 0.12)))
                    if n.fact?.pinned == true {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(glow.opacity(on ? 0.9 : 0.1)), lineWidth: 1)
                    }
                default:
                    ctx.fill(Path(ellipseIn: rect), with: .color(bg.opacity(on ? 1 : 0.12)))
                    ctx.stroke(Path(ellipseIn: rect), with: .color((n.group == .person ? person : glow).opacity(on ? 1 : 0.12)), lineWidth: 2)
                }
                if i == selected {
                    ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(fg.opacity(0.9)), lineWidth: 1.2)
                }
            }

            // подписи: у сущностей всегда, у фактов — при приближении, наведении или «Подписи»
            for i in graph.nodes.indices where visible.contains(i) {
                let n = graph.nodes[i]
                let isFact = n.group == .fact || n.group == .decision
                guard !isFact || labels || k > 2.2 || i == focus else { continue }
                let on = lit(i)
                let size: CGFloat = isFact ? 10.5 : (n.group == .me ? 13.5 : 12.5)
                let name = isFact && n.name.count > 34 ? String(n.name.prefix(33)) + "…" : n.name
                let text = Text(name).font(.geist(size, isFact ? .regular : .medium)).foregroundColor(fg.opacity(on ? (isFact ? 0.75 : 0.95) : 0.1))
                let c = pt(i)
                ctx.draw(text, at: CGPoint(x: c.x, y: c.y + CGFloat(radius[i]) * k + 5), anchor: .top)
            }
        }
    }

    // MARK: мышь

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { v in
                if dragging == nil && panStart == nil {
                    if let i = model.pick(v.startLocation, in: size), i != 0 { dragging = i } else { panStart = model.offset }
                }
                if let i = dragging {
                    model.drag(i, to: model.toGraph(v.location, in: size))
                } else if let s = panStart {
                    model.offset = CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height)
                }
            }
            .onEnded { _ in
                if let i = dragging { model.release(i) }
                dragging = nil
                panStart = nil
            }
    }

    /// Колесо и щипок трекпада — только пока мышь над графом
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [model] e in
            guard MainActor.assumeIsolated({ inside }) else { return e }
            let point = e.window.flatMap { w -> CGPoint? in
                guard let v = w.contentView else { return nil }
                return v.convert(e.locationInWindow, from: nil)
            }
            MainActor.assumeIsolated {
                // точка под мышью остаётся на месте — как в макете
                let local = point.map { CGPoint(x: $0.x - frameOrigin.x, y: (e.window?.contentView?.bounds.height ?? 0) - $0.y - frameOrigin.y) }
                if e.type == .magnify {
                    model.zoom(by: 1 + e.magnification, at: local, in: size)
                } else {
                    model.zoom(by: CGFloat(exp(Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.004 : 0.04))), at: local, in: size)
                }
            }
            return nil
        }
    }

    /// Левый верхний угол графа в окне — для зума к точке под мышью
    @State private var frameOrigin: CGPoint = .zero

    private func focusLocal(_ i: Int) {
        model.local = i
        model.selected = i
        model.offset = .zero
        model.scale = 1.3
    }

    // MARK: панели

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Icon("search", 14).foregroundStyle(p.mutedFg)
                TextField("Найти узел", text: $query).textFieldStyle(.plain).font(.geist(13))
                    .onChange(of: query) { _, q in model.find(q) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(p.input.opacity(0.4), in: RoundedRectangle(cornerRadius: R.lg))
            FlowWrap(spacing: 4) {
                ForEach([MemoryGraph.Group.project, .person, .fact, .decision], id: \.self) { g in
                    let off = model.hidden.contains(g)
                    Button {
                        if off { model.hidden.remove(g) } else { model.hidden.insert(g) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(dot(g)).frame(width: 8, height: 8).opacity(off ? 0.3 : 1)
                            Text(name(g)).strikethrough(off)
                        }
                        .tw(12, lh: 16).foregroundStyle(off ? p.mutedFg.opacity(0.6) : p.foreground.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(p.border))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 2) {
                IconButton(icon: "minus", help: "Отдалить") { model.zoom(by: 1 / 1.25, in: size) }
                IconButton(icon: "plus", help: "Приблизить") { model.zoom(by: 1.25, in: size) }
                IconButton(icon: "crosshair", help: "По центру") { model.center() }
                Spacer()
                Button { model.labels.toggle() } label: {
                    HStack(spacing: 6) { Icon("tags", 13); Text("Подписи") }
                        .tw(12, lh: 16).padding(.horizontal, 8).frame(height: 24)
                        .background(model.labels ? p.secondary : .clear, in: RoundedRectangle(cornerRadius: R.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 256)
        .background(p.popover.opacity(0.88), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    private func localBanner(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text("Окрестность: \(String(model.graph.nodes[i].name.prefix(30)))").tw(12, lh: 16)
            Button { model.local = nil; model.center() } label: {
                Text("Весь граф").tw(12, lh: 16).padding(.horizontal, 10).frame(height: 24).background(p.secondary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
        .background(p.popover.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(p.border))
    }

    private func card(_ i: Int) -> some View {
        let n = model.graph.nodes[i]
        let facts = model.facts(of: i)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(n.group == .person ? personColor : p.glow).frame(width: 12, height: 12)
                    .shadow(color: p.glowSoft, radius: 5).padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(n.fact == nil ? n.name : "Факт").tw(14, .medium, lh: 20).lineLimit(2)
                    Text("\(kindName(n.group)) · \(Plural.links(model.neighbors[i].count))").tw(12, lh: 16).foregroundStyle(p.mutedFg)
                }
                Spacer(minLength: 0)
                IconButton(icon: "x", help: "Закрыть") { model.selected = nil }
            }
            .padding(14)
            .overlay(alignment: .bottom) { p.border.frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if facts.isEmpty { Text("Фактов пока нет").tw(12, lh: 16).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity).padding(.vertical, 24) }
                    ForEach(facts, id: \.id) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.text).tw(13, lh: 18).fixedSize(horizontal: false, vertical: true)
                            Button { if let id = f.conversationID, let c = app.conversations.first(where: { $0.id == id }) { app.openChat(c) } } label: {
                                Text("из «\(f.source)» · \(RelativeWhen.string(f.createdAt))").tw(11, lh: 14).foregroundStyle(p.mutedFg)
                            }
                            .buttonStyle(.plain)
                            .disabled(f.conversationID == nil)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.card.opacity(0.5), in: RoundedRectangle(cornerRadius: R.lg))
                        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
            HStack {
                LButton(title: "Окрестность", kind: .ghost, small: true) { focusLocal(i) }
                Spacer()
            }
            .padding(10)
            .overlay(alignment: .top) { p.border.frame(height: 1) }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.popover.opacity(0.92), in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .padding(.bottom, 28)
    }

    private func dot(_ g: MemoryGraph.Group) -> Color {
        switch g {
        case .person: personColor
        case .fact: p.foreground.opacity(0.55)
        default: p.glow
        }
    }

    private func name(_ g: MemoryGraph.Group) -> String {
        switch g {
        case .project: "Проекты"
        case .person: "Люди"
        case .fact: "Факты"
        case .decision: "Решения"
        case .me: "Ты"
        }
    }

    private func kindName(_ g: MemoryGraph.Group) -> String {
        switch g {
        case .me: "это ты"
        case .person: "человек"
        case .project: "проект"
        case .decision: "решение"
        case .fact: "факт"
        }
    }
}

/// Точечная сетка фона (22 pt), рисуется один раз на размер
private struct DotGrid: View {
    @Environment(\.palette) private var p

    var body: some View {
        Canvas { ctx, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            var y: CGFloat = 11
            while y < size.height {
                var x: CGFloat = 11
                while x < size.width {
                    ctx.fill(dot.offsetBy(dx: x, dy: y), with: .color(p.foreground.opacity(0.09)))
                    x += 22
                }
                y += 22
            }
        }
    }
}

/// Переносящийся ряд (чипы групп)
struct FlowWrap: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0 && x + d.width > width { x = 0; y += row + spacing; row = 0 }
            x += d.width + spacing
            maxX = max(maxX, x - spacing)
            row = max(row, d.height)
        }
        return CGSize(width: min(maxX, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + d.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing
            row = max(row, d.height)
        }
    }
}
