import Foundation

/// Блочная разметка markdown в ответе: заголовки, абзацы, списки, цитаты, горизонтальная линия.
/// Строчную (жирный, курсив, `код`, ссылки) разбирает `RichText.markdown`. Таблицы и блоки кода вынесены раньше (RichText.parts).
enum MDBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    /// Пункт списка: отступ вложенности (0, 1, 2…) и текст
    case bullet(Int, String)
    /// Нумерованный пункт: отступ, номер как написан («1», «2»), текст
    case ordered(Int, String, String)
    /// Пункт-чекбокс «- [ ] …» / «- [x] …»: отступ, отмечен ли, текст
    case task(Int, Bool, String)
    /// Цитата: глубина («>» — 1, «> >» — 2) и текст
    case quote(Int, String)
    case rule

    var isListItem: Bool {
        switch self {
        case .bullet, .ordered, .task: true
        default: false
        }
    }
}

enum MarkdownBlocks {
    static func parse(_ source: String) -> [MDBlock] {
        var out: [MDBlock] = []
        // пока идёт абзац или цитата без пустой строки — строки клеятся к последнему блоку
        var open = false
        for raw in source.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { open = false; continue }
            if isRule(trimmed) { out.append(.rule); open = false; continue }
            if let h = heading(trimmed) { out.append(h); open = false; continue }
            let indent = line.prefix { $0 == " " }.count
            if let (_, text) = bullet(trimmed) {
                if let (done, rest) = task(text) { out.append(.task(indent / 2, done, rest)) } else { out.append(.bullet(indent / 2, text)) }
                open = true; continue
            }
            if let (num, text) = ordered(trimmed) {
                out.append(.ordered(indent / 2, num, text)); open = true; continue
            }
            if trimmed.hasPrefix(">") {
                // «> > текст» — цитата в цитате: глубина по числу «>» в начале
                var body = Substring(trimmed)
                var depth = 0
                while body.hasPrefix(">") {
                    depth += 1
                    body = body.dropFirst().drop { $0 == " " }
                }
                let text = String(body)
                if case .quote(let d, let q)? = out.last, open, d == depth { out[out.count - 1] = .quote(d, q + "\n" + text) } else { out.append(.quote(depth, text)) }
                open = true
                continue
            }
            // продолжение пункта (строка с отступом под ним) или абзаца
            if open, let last = out.last {
                switch last {
                case .paragraph(let p): out[out.count - 1] = .paragraph(p + "\n" + trimmed); continue
                case .bullet(let i, let p) where indent >= 2: out[out.count - 1] = .bullet(i, p + " " + trimmed); continue
                case .ordered(let i, let n, let p) where indent >= 2: out[out.count - 1] = .ordered(i, n, p + " " + trimmed); continue
                case .task(let i, let d, let p) where indent >= 2: out[out.count - 1] = .task(i, d, p + " " + trimmed); continue
                case .quote(let d, let q): out[out.count - 1] = .quote(d, q + "\n" + trimmed); continue
                default: break
                }
            }
            out.append(.paragraph(trimmed))
            open = true
        }
        return out
    }

    /// «---», «***», «___», «- - -»: три и больше одинаковых знака и ничего больше
    static func isRule(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.count >= 3, let c = t.first, "-*_".contains(c) else { return false }
        return t.allSatisfy { $0 == c }
    }

    private static func heading(_ s: String) -> MDBlock? {
        guard let r = s.range(of: #"^#{1,6}\s+"#, options: .regularExpression) else { return nil }
        let level = s[r].filter { $0 == "#" }.count
        var text = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        // закрывающие «##» в конце заголовка
        if let e = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(e) }
        return .heading(level, text)
    }

    private static func bullet(_ s: String) -> (String, String)? {
        guard let r = s.range(of: #"^[-*+•]\s+"#, options: .regularExpression) else { return nil }
        return (String(s[r]).trimmingCharacters(in: .whitespaces), String(s[r.upperBound...]))
    }

    /// «[ ] текст» / «[x] текст» в начале пункта: отмечен ли и что осталось
    static func task(_ s: String) -> (Bool, String)? {
        guard let r = s.range(of: #"^\[([ xX])\](\s+|$)"#, options: .regularExpression) else { return nil }
        return (s[r].contains { $0 == "x" || $0 == "X" }, String(s[r.upperBound...]))
    }

    private static func ordered(_ s: String) -> (String, String)? {
        guard let r = s.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) else { return nil }
        let num = String(s[r]).trimmingCharacters(in: .whitespaces).dropLast()
        return (String(num), String(s[r.upperBound...]))
    }
}
