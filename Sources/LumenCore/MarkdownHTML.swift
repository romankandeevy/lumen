import Foundation

/// Просмотр файлов-вложений в браузере сбоку: Markdown — оформленным текстом, код и текст — моноширинным.
/// Свой маленький перевод в HTML: без сети и сторонних библиотек.
public enum MarkdownHTML {
    /// Готовая страница для просмотра файла `name` с содержимым `text`
    /// `raw` — показать исходный текст (у Markdown: переключатель «код»), с номерами строк, как у Claude
    public static func page(name: String, text: String, raw: Bool = false) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let isMarkdown = ["md", "markdown"].contains(ext)
        let body = isMarkdown && !raw ? render(text) : numbered(text)
        return """
            <!doctype html><html><head><meta charset="utf-8"><title>\(escape(name))</title>
            <style>
            :root { color-scheme: light dark; }
            body { font: 15px/1.6 -apple-system, system-ui; max-width: 760px; margin: 32px auto; padding: 0 24px; color: #1d1d1f; background: #fff; }
            @media (prefers-color-scheme: dark) { body { color: #e8e6e3; background: #141414; } code, pre { background: #1f1f1f !important; } blockquote { color: #a8a29e; border-color: #3a3a3a !important; } th, td { border-color: #333 !important; } }
            h1, h2, h3, h4 { line-height: 1.25; margin: 1.4em 0 .5em; } h1 { font-size: 1.8em; } h2 { font-size: 1.4em; } h3 { font-size: 1.15em; }
            code { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; background: #f3f3f3; padding: .1em .35em; border-radius: 4px; }
            pre { background: #f6f6f6; padding: 14px 16px; border-radius: 8px; overflow: auto; } pre code { background: none !important; padding: 0; }
            blockquote { margin: 1em 0; padding: 0 1em; color: #6e6e73; border-left: 3px solid #ddd; }
            table { border-collapse: collapse; } th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
            a { color: #d97706; } hr { border: none; border-top: 1px solid #8884; margin: 2em 0; }
            .file { font: 12px ui-monospace, Menlo, monospace; opacity: .55; margin-bottom: 1.5em; }
            .code { font: 13px/1.65 ui-monospace, SFMono-Regular, Menlo, monospace; padding: 4px 0; }
            .code .l { display: flex; } .code .n { flex: none; width: 3.2em; padding-right: 1.1em; text-align: right; opacity: .45; user-select: none; }
            .code .t { white-space: pre-wrap; word-break: break-word; min-width: 0; }
            body.codeview { max-width: none; margin: 0; padding: 12px 20px 40px 8px; }
            </style></head><body class="\(isMarkdown && !raw ? "" : "codeview")">
            \(body)
            </body></html>
            """
    }

    /// Текст с номерами строк
    static func numbered(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let shown = lines.last == "" && lines.count > 1 ? Array(lines.dropLast()) : lines
        return "<div class=\"code\">" + shown.enumerated().map { "<div class=\"l\"><span class=\"n\">\($0.offset + 1)</span><span class=\"t\">\(escape($0.element))</span></div>" }.joined() + "</div>"
    }

    /// Markdown → HTML: заголовки, абзацы, списки, код (```), цитаты, таблицы, черта, **жирный**, *курсив*, `код`, [ссылки](…)
    public static func render(_ md: String) -> String {
        var out: [String] = []
        var para: [String] = []
        var list: (ordered: Bool, items: [String])?
        var code: [String]?
        var quote: [String] = []
        var table: [[String]] = []

        func flushPara() { if !para.isEmpty { out.append("<p>" + inline(para.joined(separator: " ")) + "</p>"); para = [] } }
        func flushList() {
            if let l = list {
                let tag = l.ordered ? "ol" : "ul"
                out.append("<\(tag)>" + l.items.map { "<li>" + inline($0) + "</li>" }.joined() + "</\(tag)>")
                list = nil
            }
        }
        func flushQuote() { if !quote.isEmpty { out.append("<blockquote>" + render(quote.joined(separator: "\n")) + "</blockquote>"); quote = [] } }
        func flushTable() {
            guard !table.isEmpty else { return }
            var rows = table
            let head = rows.removeFirst()
            if let sep = rows.first, sep.allSatisfy({ $0.allSatisfy { "-:| ".contains($0) } }) { rows.removeFirst() }
            out.append("<table><tr>" + head.map { "<th>" + inline($0) + "</th>" }.joined() + "</tr>"
                       + rows.map { "<tr>" + $0.map { "<td>" + inline($0) + "</td>" }.joined() + "</tr>" }.joined() + "</table>")
            table = []
        }
        func flushAll() { flushPara(); flushList(); flushQuote(); flushTable() }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var c = code {
                if line.hasPrefix("```") { out.append("<pre><code>" + escape(c.joined(separator: "\n")) + "</code></pre>"); code = nil } else { c.append(raw); code = c }
                continue
            }
            if line.hasPrefix("```") { flushAll(); code = []; continue }
            if line.isEmpty { flushAll(); continue }
            if line.hasPrefix(">") { flushPara(); flushList(); flushTable(); quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)); continue }
            if line.hasPrefix("|") {
                flushPara(); flushList(); flushQuote()
                table.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            if let h = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[h] == " " {
                flushAll()
                let level = min(6, line.distance(from: line.startIndex, to: h))
                out.append("<h\(level)>" + inline(String(line[h...]).trimmingCharacters(in: .whitespaces)) + "</h\(level)>")
                continue
            }
            if line == "---" || line == "***" { flushAll(); out.append("<hr>"); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushPara(); flushQuote(); flushTable()
                if list?.ordered == true { flushList() }
                list = (false, (list?.items ?? []) + [String(line.dropFirst(2))])
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                flushPara(); flushQuote(); flushTable()
                if list?.ordered == false { flushList() }
                list = (true, (list?.items ?? []) + [String(line[line.index(dot, offsetBy: 2)...])])
                continue
            }
            flushList(); flushQuote(); flushTable()
            para.append(line)
        }
        if let c = code { out.append("<pre><code>" + escape(c.joined(separator: "\n")) + "</code></pre>") }
        flushAll()
        return out.joined(separator: "\n")
    }

    /// Внутри строки: `код`, **жирный**, *курсив*, [ссылка](адрес)
    static func inline(_ s: String) -> String {
        var t = escape(s)
        t = t.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?<![*\\w])\\*([^*]+)\\*(?![*\\w])", with: "<em>$1</em>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return t
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
