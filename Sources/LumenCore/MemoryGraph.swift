import Foundation

/// Граф памяти (техплан §5.8): узлы — ты, проекты, люди и факты; рёбра — «факт про это».
/// Сущности не хранятся отдельно: проекты берутся из проектов Lumen и папок агента,
/// люди — из фактов о людях («Папа — …», «Лёша …»), связи — по упоминанию имени в тексте факта
/// с русскими окончаниями («Shelf» ↔ «в Shelf», «Лёша» ↔ «Лёше»).
public struct MemoryGraph: Sendable, Equatable {
    public enum Group: String, Sendable, CaseIterable { case me, project, person, fact, decision }

    public struct Node: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let group: Group
        /// Для узлов-фактов
        public let fact: MemoryFact?
        public var degree = 0
    }

    public struct Link: Sendable, Equatable {
        /// core — ты ↔ сущность, own — факт у своей главной сущности, cross — факт про ещё одну
        public enum Kind: Sendable { case core, own, cross }
        public let a: Int
        public let b: Int
        public let kind: Kind
    }

    public private(set) var nodes: [Node] = []
    public private(set) var links: [Link] = []

    public static let meID = "me"

    /// - Parameters:
    ///   - projects: названия проектов и папок, о которых знает Lumen
    public init(facts: [MemoryFact], me: String, projects: [String]) {
        var nodes = [Node(id: Self.meID, name: me.isEmpty ? "Ты" : me, group: .me, fact: nil)]
        var entities: [(index: Int, keys: [String])] = []

        func addEntity(_ name: String, _ group: Group) {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 2 else { return }
            let keys = Self.keys(clean)
            guard !keys.isEmpty,
                  !entities.contains(where: { $0.keys == keys }) else { return }
            nodes.append(Node(id: "\(group.rawValue):\(clean.lowercased())", name: clean, group: group, fact: nil))
            entities.append((nodes.count - 1, keys))
        }
        for p in projects { addEntity(p, .project) }
        for f in facts where f.kind == .people {
            if let name = Self.personName(f.text) { addEntity(name, .person) }
        }

        var links: [Link] = []
        for e in entities { links.append(Link(a: 0, b: e.index, kind: .core)) }
        let meKeys = Self.keys(me)
        for f in facts {
            let words = Self.words(f.text)
            var about = entities.filter { e in e.keys.allSatisfy { k in words.contains { $0.hasPrefix(k) } } }.map(\.index)
            // о тебе, твои привычки, упоминание твоего имени и всё, что ни к чему не привязалось, — у тебя
            let mentionsMe = !meKeys.isEmpty && meKeys.allSatisfy { k in words.contains { $0.hasPrefix(k) } }
            if about.isEmpty || f.kind == .you || f.kind == .pref || mentionsMe { about.insert(0, at: 0) }
            // факт о человеке — прежде всего у этого человека
            if f.kind == .people, let i = about.firstIndex(where: { nodes[$0].group == .person }) { about.swapAt(0, i) }
            nodes.append(Node(id: "fact:\(f.id ?? Int64(nodes.count))", name: f.text,
                              group: f.kind == .decision || f.kind == .pref ? .decision : .fact, fact: f))
            let fi = nodes.count - 1
            links.append(Link(a: about[0], b: fi, kind: .own))
            for other in about.dropFirst() { links.append(Link(a: fi, b: other, kind: .cross)) }
        }
        for l in links {
            nodes[l.a].degree += 1
            nodes[l.b].degree += 1
        }
        self.nodes = nodes
        self.links = links
    }

    /// Соседи каждого узла — для подсветки и «окрестности»
    public var neighbors: [Set<Int>] {
        var out = Array(repeating: Set<Int>(), count: nodes.count)
        for l in links {
            out[l.a].insert(l.b)
            out[l.b].insert(l.a)
        }
        return out
    }

    /// Узлы в пределах двух шагов от узла (локальный граф)
    public func around(_ i: Int, hops: Int = 2) -> Set<Int> {
        let n = neighbors
        var near: Set<Int> = [i]
        for _ in 0..<hops { near.formUnion(near.flatMap { n[$0] }) }
        return near
    }

    // MARK: имена

    /// «Папа — хозяин сайта» → «Папа»; «Лёша работает в …» → «Лёша»
    static func personName(_ text: String) -> String? {
        let head = text.components(separatedBy: CharacterSet(charactersIn: "—–-:,(")).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let words = head.split(separator: " ").map(String.init)
        // имя — первые слова с заглавной (до двух: «Анна Петровна»)
        let name = words.prefix { $0.first?.isUppercase == true }.prefix(2).joined(separator: " ")
        guard !name.isEmpty, name.count <= 30 else { return nil }
        return name
    }

    /// Ключи для поиска упоминаний: основы слов без окончаний (как в поиске по памяти)
    static func keys(_ name: String) -> [String] {
        words(name).map { w in
            // «Lumen» ищем как «lumen», «Лёша» — как «лёш»: последние гласные отбрасываем, но слово не короче 3 букв
            var s = w
            let vowels = Set("аеёиоуыэюяйь")
            while s.count > 3, let last = s.last, vowels.contains(last) { s.removeLast() }
            return s
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".")))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { $0.count >= 2 }
    }
}
