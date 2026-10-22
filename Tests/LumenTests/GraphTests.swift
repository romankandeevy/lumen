import Foundation
import Testing
@testable import LumenCore

// Граф памяти: факты привязываются к проектам и людям по упоминанию с окончаниями;
// раскладка 1000 фактов успокаивается быстро (ступень 1.1: «граф не тормозит на 1000 фактах»).

private func fact(_ id: Int64, _ kind: MemoryKind, _ text: String) -> MemoryFact {
    MemoryFact(id: id, kind: kind, text: text, source: "Тест")
}

@Test func graphLinksFactsToProjectsAndPeople() {
    let facts = [
        fact(1, .you, "Рома делает Mac-приложения на Swift"),
        fact(2, .people, "Папа — хозяин kandeev.com; на сайте без цен"),
        fact(3, .project, "В Shelf вкладку «Полка» убрали, файлы идут в Буфер"),
        fact(4, .decision, "Интерфейс Shelf и Island — только SwiftUI"),
        fact(5, .people, "Лёша помогает с дизайном"),
        fact(6, .project, "Скинуть Лёше макет Shelf"),
        fact(7, .project, "Купить новый монитор"),
    ]
    let g = MemoryGraph(facts: facts, me: "Рома", projects: ["Shelf", "Island", "kandeev.com"])
    let names = g.nodes.map(\.name)
    #expect(names.contains("Папа") && names.contains("Лёша"))
    func node(_ name: String) -> Int { g.nodes.firstIndex { $0.name == name }! }
    func factNode(_ id: Int64) -> Int { g.nodes.firstIndex { $0.fact?.id == id }! }
    let n = g.neighbors
    #expect(n[node("Shelf")].contains(factNode(3)))
    #expect(n[node("Shelf")].contains(factNode(4)) && n[node("Island")].contains(factNode(4)))
    // «Лёше» находит Лёшу, «kandeev.com» — проект
    #expect(n[node("Лёша")].contains(factNode(6)))
    #expect(n[node("kandeev.com")].contains(factNode(2)))
    // факт о человеке — прежде всего у человека
    #expect(g.links.contains { $0.kind == .own && $0.a == node("Папа") && $0.b == factNode(2) })
    // ни к чему не привязанное и «о тебе» — в теме своего вида, а тема — у тебя (не сотня лучей из одной точки)
    func topicOf(_ id: Int64) -> Int? { n[factNode(id)].first { g.nodes[$0].group == .topic } }
    #expect(topicOf(7) != nil && topicOf(1) != nil && topicOf(1) != topicOf(7))
    #expect(n[0].contains(topicOf(7)!) && n[0].contains(topicOf(1)!))
    #expect(!n[0].contains(factNode(7)) && !n[0].contains(factNode(1)))
    #expect(g.nodes[factNode(4)].group == .decision)
    // окрестность Лёши — он, его факты и через них Shelf
    #expect(g.around(node("Лёша")).contains(node("Shelf")))
}

@Test func thousandFactsSettleQuickly() {
    let projects = (0..<12).map { "Проект\($0)" }
    let facts = (0..<1000).map { i in fact(Int64(i), i % 5 == 0 ? .decision : .project, "Заметка \(i) про Проект\(i % 12) и Проект\((i * 7) % 12)") }
    let g = MemoryGraph(facts: facts, me: "Рома", projects: projects)
    #expect(g.nodes.count == 1 + 12 + 1000)
    var layout = GraphLayout(graph: g)
    let t0 = Date()
    layout.settle()
    let spent = Date().timeIntervalSince(t0)
    #expect(layout.settled)
    // в приложении (release) — 0,06 с на Mac M-серии; отладочная сборка тестов в ~60 раз медленнее
    #if DEBUG
    #expect(spent < 8, "раскладка заняла \(spent) с")
    #else
    #expect(spent < 0.5, "раскладка заняла \(spent) с")
    #endif
    // узлы не слиплись в точку и не улетели
    let far = layout.positions.map { ($0 * $0).sum().squareRoot() }.max() ?? 0
    #expect(far > 150 && far < 5000)
    #expect(layout.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
}
