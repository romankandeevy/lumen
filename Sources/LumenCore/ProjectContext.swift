import Foundation

/// PROJECT.md — контекст проекта в Markdown (Рома, 18.10): что это, где, стек, статус, решения, заметки и компакт каждого чата.
/// Разделы — «## …». Lumen дописывает их сам после ответов; то, что человек просит добавить, — в «Заметки»;
/// компакт чата — в «Чаты» под «### Название <!-- chat:id -->», так чаты проекта знают друг о друге.
public enum ProjectContext {
    /// Разделы, которые Lumen обновляет сам по разговорам
    public static let autoSections = ["Что это", "Где", "Стек и запуск", "Статус", "Решения"]
    /// Сюда — то, что человек попросил добавить в проект
    public static let notes = "Заметки"
    public static let chats = "Чаты"
    public static var sections: [String] { autoSections + [notes, chats] }
    /// Папка рядом с PROJECT.md, куда копируются добавленные файлы и картинки
    public static let filesFolder = "context"

    public static func template(name: String, folder: String?) -> String {
        var s = "# \(name)\n\nКонтекст проекта: что это, где лежит, что сделано и что решено. "
            + "Lumen ведёт этот файл сам и читает его в каждом чате проекта. Править можно и руками.\n"
        for sec in sections {
            s += "\n## \(sec)\n"
            if sec == "Где", let folder { s += "\nПапка: `\(folder)`\n" }
        }
        return s
    }

    /// Текст раздела без заголовка; раздела нет — nil
    public static func section(_ title: String, in doc: String) -> String? {
        let lines = doc.components(separatedBy: "\n")
        guard let h = heading(title, lines) else { return nil }
        return lines[(h + 1)..<end(after: h, lines)].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Заменить текст раздела; раздела нет — добавить (перед «Чатами», если они есть)
    public static func replacing(_ title: String, with text: String, in doc: String) -> String {
        var lines = doc.components(separatedBy: "\n")
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = body.isEmpty ? [""] : ["", body, ""]
        if let h = heading(title, lines) {
            lines.replaceSubrange((h + 1)..<end(after: h, lines), with: block)
        } else {
            let at = title == chats ? lines.count : (heading(chats, lines) ?? lines.count)
            lines.insert(contentsOf: ["", "## \(title)"] + block, at: at)
        }
        return tidy(lines.joined(separator: "\n"))
    }

    /// Дописать в конец раздела
    public static func appending(_ text: String, to title: String, in doc: String) -> String {
        let add = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !add.isEmpty else { return doc }
        let now = section(title, in: doc) ?? ""
        return replacing(title, with: now.isEmpty ? add : now + "\n\n" + add, in: doc)
    }

    /// Компакт чата в «Чатах»: заменяет прежний компакт этого чата или добавляет новый
    public static func settingChat(id: String, title: String, summary: String, in doc: String) -> String {
        let mark = marker(id)
        let entry = "### \(title.replacingOccurrences(of: "\n", with: " ")) \(mark)\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))"
        var lines = (section(chats, in: doc) ?? "").components(separatedBy: "\n")
        if let s = lines.firstIndex(where: { $0.hasPrefix("### ") && $0.contains(mark) }) {
            var e = s + 1
            while e < lines.count, !lines[e].hasPrefix("### ") { e += 1 }
            lines.replaceSubrange(s..<e, with: [entry, ""])
        } else {
            lines += ["", entry]
        }
        return replacing(chats, with: lines.joined(separator: "\n"), in: doc)
    }

    /// Прежний компакт чата; нет — nil
    public static func chatSummary(id: String, in doc: String) -> String? {
        let lines = (section(chats, in: doc) ?? "").components(separatedBy: "\n")
        guard let s = lines.firstIndex(where: { $0.hasPrefix("### ") && $0.contains(marker(id)) }) else { return nil }
        var e = s + 1
        while e < lines.count, !lines[e].hasPrefix("### ") { e += 1 }
        let text = lines[(s + 1)..<e].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func marker(_ id: String) -> String { "<!-- chat:\(id) -->" }

    private static func heading(_ title: String, _ lines: [String]) -> Int? {
        let want = "## " + title.lowercased()
        return lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == want }
    }

    /// Конец раздела: следующий «## » или конец файла («### » — это часть раздела)
    private static func end(after h: Int, _ lines: [String]) -> Int {
        var i = h + 1
        while i < lines.count, !lines[i].hasPrefix("## ") { i += 1 }
        return i
    }

    /// Не больше одной пустой строки подряд, в конце — перевод строки
    private static func tidy(_ s: String) -> String {
        var s = s
        while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
