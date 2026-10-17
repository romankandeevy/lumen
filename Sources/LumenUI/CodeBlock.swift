import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Блок кода в ответе, как в Claude: сверху язык, справа «Скачать» и «Копировать»; код подсвечен.
struct CodeBlock: View {
    let code: String
    let lang: String?

    @Environment(\.palette) private var p
    @Environment(\.chatText) private var chatText
    @State private var copied = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text(Self.label(lang)).tw(12, lh: 16).foregroundStyle(p.mutedFg)
                Spacer(minLength: 8)
                IconButton(icon: "download", help: "Скачать как \(Self.fileName(lang))") { download() }
                IconButton(icon: copied ? "check" : "copy", help: copied ? "Скопировано" : "Копировать") { copy() }
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Highlighter.highlight(code, lang: lang, palette: p))
                    .font(.system(size: chatText.code, design: .monospaced)).lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 14)
            }
        }
        .background(p.card, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    /// Сохранить в файл: имя и расширение — по языку, папку выбирает человек
    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(lang)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data((code.hasSuffix("\n") ? code : code + "\n").utf8).write(to: url)
    }

    static func label(_ lang: String?) -> String {
        guard let l = lang?.trimmingCharacters(in: .whitespaces), !l.isEmpty else { return "код" }
        return l.lowercased()
    }

    static let extensions: [String: String] = [
        "python": "py", "py": "py", "swift": "swift", "javascript": "js", "js": "js", "typescript": "ts", "ts": "ts",
        "tsx": "tsx", "jsx": "jsx", "json": "json", "html": "html", "css": "css", "bash": "sh", "sh": "sh", "zsh": "sh",
        "shell": "sh", "console": "sh", "ruby": "rb", "go": "go", "rust": "rs", "java": "java", "kotlin": "kt", "c": "c",
        "cpp": "cpp", "c++": "cpp", "csharp": "cs", "cs": "cs", "php": "php", "sql": "sql", "yaml": "yml", "yml": "yml",
        "toml": "toml", "markdown": "md", "md": "md", "xml": "xml", "lua": "lua", "dart": "dart", "r": "r",
    ]

    static func fileName(_ lang: String?) -> String {
        "код." + (extensions[label(lang)] ?? "txt")
    }
}

/// Подсветка без зависимостей: строки, комментарии, числа, ключевые слова, вызовы и типы.
/// Цвета — от темы: на тёмной ярче, на светлой темнее, чтобы читались на фоне карточки.
enum Highlighter {
    struct Colors {
        let keyword, string, number, comment, call, type: Color
    }

    static func colors(_ p: Palette) -> Colors {
        p.isLight
            ? Colors(keyword: Color(hex: 0xA626A4), string: Color(hex: 0x3A8A2E), number: Color(hex: 0x0E7C86),
                     comment: Color(hex: 0x8A8A8A), call: Color(hex: 0x2F6FD0), type: Color(hex: 0xB0661A))
            : Colors(keyword: Color(hex: 0xC792EA), string: Color(hex: 0x9CD67A), number: Color(hex: 0x5FD4D6),
                     comment: Color(hex: 0x7A7F87), call: Color(hex: 0x6FB1FF), type: Color(hex: 0xF0B46A))
    }

    static let keywords: Set<String> = [
        // общие для Python, JS/TS, Swift, Go, Rust, Kotlin, C-подобных, Ruby, shell
        "import", "from", "as", "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
        "is", "with", "try", "except", "finally", "raise", "lambda", "yield", "pass", "break", "continue", "global",
        "async", "await", "True", "False", "None", "function", "const", "let", "var", "new", "this", "typeof", "instanceof",
        "export", "default", "extends", "implements", "interface", "type", "enum", "struct", "protocol", "extension", "func",
        "guard", "switch", "case", "throw", "throws", "catch", "do", "public", "private", "fileprivate", "internal",
        "static", "final", "override", "init", "self", "Self", "super", "nil", "null", "undefined", "true", "false", "some",
        "any", "where", "package", "fn", "pub", "mut", "impl", "use", "mod", "match", "loop", "go", "defer", "chan", "map",
        "select", "fun", "val", "when", "object", "void", "int", "float", "double", "bool", "char", "long", "unsigned",
        "end", "then", "fi", "done", "esac", "echo", "export", "local", "begin", "rescue", "module", "require", "of",
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "TABLE", "JOIN", "ON", "AND", "OR",
        "ORDER", "BY", "GROUP", "LIMIT", "VALUES", "SET", "AS", "NOT", "NULL",
    ]

    /// Встроенные функции и имена — цветом вызова, даже без скобок
    static let builtins: Set<String> = ["print", "len", "range", "int", "str", "input", "list", "dict", "set", "open",
                                        "console", "Math", "JSON", "Object", "Array", "String", "Number", "Promise"]

    static func highlight(_ code: String, lang: String?, palette p: Palette) -> AttributedString {
        let c = colors(p)
        let hashComments = ["python", "py", "bash", "sh", "zsh", "shell", "ruby", "rb", "yaml", "yml", "toml", "r", "console"]
            .contains(lang?.lowercased() ?? "") || lang == nil
        let chars = Array(code)
        var out = AttributedString()
        var plain = ""
        func flush() {
            if !plain.isEmpty { var a = AttributedString(plain); a.foregroundColor = p.foreground.opacity(0.92); out += a; plain = "" }
        }
        func emit(_ s: String, _ color: Color, italic: Bool = false) {
            flush()
            var a = AttributedString(s)
            a.foregroundColor = color
            if italic { a.font = .system(size: 12.5, design: .monospaced).italic() }
            out += a
        }
        var i = 0
        let n = chars.count
        func peek(_ k: Int) -> Character? { i + k < n ? chars[i + k] : nil }
        while i < n {
            let ch = chars[i]
            // комментарии
            if (ch == "/" && peek(1) == "/") || (hashComments && ch == "#") || (ch == "-" && peek(1) == "-" && lang?.lowercased() == "sql") {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                emit(String(chars[i..<j]), c.comment, italic: true)
                i = j
                continue
            }
            if ch == "/" && peek(1) == "*" {
                var j = i + 2
                while j < n - 1 && !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(n, j + 2)
                emit(String(chars[i..<j]), c.comment, italic: true)
                i = j
                continue
            }
            // строки: "…", '…', `…` (и f"…" в Python — префикс подсвечивается вместе со строкой)
            if ch == "\"" || ch == "'" || ch == "`" {
                var j = i + 1
                while j < n && chars[j] != ch && !(ch != "`" && chars[j] == "\n") {
                    if chars[j] == "\\" { j += 1 }
                    j += 1
                }
                j = min(n, j + 1)
                emit(String(chars[i..<j]), c.string)
                i = j
                continue
            }
            // числа
            if ch.isNumber, i == 0 || !(chars[i - 1].isLetter || chars[i - 1] == "_") {
                var j = i
                while j < n && (chars[j].isNumber || chars[j] == "." || chars[j] == "_" || chars[j] == "x" || chars[j].isHexDigit) { j += 1 }
                emit(String(chars[i..<j]), c.number)
                i = j
                continue
            }
            // слова
            if ch.isLetter || ch == "_" || ch == "@" || ch == "$" {
                var j = i + 1
                while j < n && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                let word = String(chars[i..<j])
                // f"…", r"…", b"…" — префикс строки
                if j < n, chars[j] == "\"" || chars[j] == "'", ["f", "r", "b", "rb", "fr", "u"].contains(word.lowercased()) {
                    emit(word, c.string)
                    i = j
                    continue
                }
                if keywords.contains(word) {
                    emit(word, c.keyword)
                } else if (j < n && chars[j] == "(") || builtins.contains(word) {
                    emit(word, c.call)
                } else if word.first?.isUppercase == true && word.count > 1 {
                    emit(word, c.type)
                } else {
                    plain += word
                }
                i = j
                continue
            }
            plain.append(ch)
            i += 1
        }
        flush()
        return out
    }
}
