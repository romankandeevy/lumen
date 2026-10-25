import Foundation

/// Вложение-карточка внутри текста поля ввода: в черновике это метка «\u{E000}id\u{E001}», поле рисует на её месте чип,
/// а при отправке метка становится «[Файл: имя]» — по нему человек и модель видят, к чему относится правка.
public enum FileMarks {
    public static let open: Character = "\u{E000}"
    public static let close: Character = "\u{E001}"

    public static func marker(_ id: String) -> String { "\(open)\(id)\(close)" }

    /// Куски текста и метки по порядку
    public enum Piece: Equatable { case text(String), mark(String) }

    public static func pieces(_ text: String) -> [Piece] {
        var out: [Piece] = []
        var run = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == open, let end = text[i...].firstIndex(of: close) {
                if !run.isEmpty { out.append(.text(run)); run = "" }
                out.append(.mark(String(text[text.index(after: i)..<end])))
                i = text.index(after: end)
            } else {
                run.append(text[i])
                i = text.index(after: i)
            }
        }
        if !run.isEmpty { out.append(.text(run)) }
        return out
    }

    public static func ids(in text: String) -> [String] {
        pieces(text).compactMap { if case .mark(let id) = $0 { return id } else { return nil } }
    }

    /// Оставляет только метки известных вложений
    public static func strip(_ text: String, keeping known: Set<String>) -> String {
        pieces(text).map {
            switch $0 {
            case .text(let t): return t
            case .mark(let id): return known.contains(id) ? marker(id) : ""
            }
        }.joined()
    }

    /// Метки → «[Файл: имя]» на своей строке
    public static func readable(_ text: String, names: [String: String]) -> String {
        var out = ""
        for piece in pieces(text) {
            switch piece {
            case .text(let t): out += t
            case .mark(let id):
                guard let name = names[id] else { continue }
                if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                out += "[Файл: \(name)]\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Сообщение, разобранное на «карточка файла» и «правка к ней»
    public enum Segment: Equatable { case text(String), file(String) }

    public static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var run = ""
        func flush() {
            let t = run.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
            run = ""
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("[Файл: "), line.hasSuffix("]") {
                flush()
                out.append(.file(String(line.dropFirst(7).dropLast())))
            } else {
                run += (run.isEmpty ? "" : "\n") + line
            }
        }
        flush()
        return out
    }

    /// Есть ли в тексте хоть одна карточка
    public static func hasFiles(_ text: String) -> Bool { segments(text).contains { if case .file = $0 { return true } else { return false } } }
}
