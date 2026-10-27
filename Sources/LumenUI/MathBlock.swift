import Foundation

/// Формулы в ответе: «$$ … $$», «\[ … \]» и блок ```math рисуются KaTeX в той же живой картинке, что и ```visual
/// (библиотека — с cdn.jsdelivr.net, как Chart.js; без сети остаётся пустое место). Формулы в строке «$x$» остаются текстом.
enum MathBlock {
    static let langs: Set<String> = ["math", "latex", "tex", "katex"]

    static let version = "0.16.11"

    /// Абзац целиком из формулы в «$$ … $$» или «\[ … \]» — сама формула; иначе nil
    static func display(_ para: String) -> String? {
        let t = para.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]")] {
            guard t.hasPrefix(open), t.hasSuffix(close), t.count > open.count + close.count else { continue }
            let body = String(t.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty, !body.contains("$$") { return body }
        }
        return nil
    }

    /// Страница-вставка для `VisualBlock`: формула по центру, цвет букв — от темы
    static func html(_ tex: String) -> String {
        let data = (try? JSONEncoder().encode(tex)) ?? Data("\"\"".utf8)
        // </script> внутри формулы не должен закрыть тег
        let json = (String(data: data, encoding: .utf8) ?? "\"\"").replacingOccurrences(of: "</", with: "<\\/")
        return """
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@\(version)/dist/katex.min.css">
            <style>.katex{font-size:1.2em} #m{overflow-x:auto;overflow-y:hidden;padding:4px 0;text-align:center}</style>
            <div id="m"></div>
            <script src="https://cdn.jsdelivr.net/npm/katex@\(version)/dist/katex.min.js"></script>
            <script>try{katex.render(\(json),document.getElementById('m'),{displayMode:true,throwOnError:false})}catch(e){document.getElementById('m').textContent=\(json)}</script>
            """
    }
}
