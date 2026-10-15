import AppKit
import Foundation
import LumenCore
import LumenStorage

/// Память в приложении: список фактов, правки со страницы и из плашки «Запомнил»,
/// файлы USER.md и MEMORY.md как вид на базу (§5.7, решение §18.10).
extension AppModel {
    func reloadMemories() {
        memories = (try? store.memories()) ?? []
        writeMemoryFiles()
        // системный промпт чата содержит закреплённые факты — пусть следующий ход возьмёт новые
        chat.memoryChanged()
    }

    @discardableResult
    func addMemory(_ text: String, kind: MemoryKind, pinned: Bool, source: String = "Добавлено вручную", conversationID: String? = nil) -> MemoryFact? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let f = try? store.save(MemoryFact(kind: kind, text: t, source: source, conversationID: conversationID, pinned: pinned))
        reloadMemories()
        flash()
        return f
    }

    func updateMemory(_ f: MemoryFact, _ change: (inout MemoryFact) -> Void) {
        var m = f
        change(&m)
        _ = try? store.save(m)
        reloadMemories()
    }

    func forget(_ f: MemoryFact) {
        guard let id = f.id else { return }
        try? store.deleteMemory(id)
        lastForgotten = f
        reloadMemories()
    }

    /// «Вернуть» забытое — с тем же текстом, видом и источником
    func restoreForgotten() {
        guard var f = lastForgotten else { return }
        f.id = nil
        _ = try? store.save(f)
        lastForgotten = nil
        reloadMemories()
    }

    func memory(_ id: Int64) -> MemoryFact? { memories.first { $0.id == id } }

    // MARK: файлы памяти

    var userFile: URL { paths.root.appendingPathComponent("USER.md") }
    var memoryFile: URL { paths.root.appendingPathComponent("MEMORY.md") }

    /// USER.md — кто ты и как с тобой говорить; MEMORY.md — проекты, решения, люди
    func memoryFileText(user: Bool) -> String {
        let kinds: Set<MemoryKind> = user ? [.you, .pref] : [.project, .decision, .people]
        let lines = memories.filter { kinds.contains($0.kind) }.map { "- " + $0.text + ($0.pinned ? " (закреплено)" : "") }
        let title = user ? "# Кто ты" : "# Проекты, решения и люди"
        return ([title, "", "Файл собирает Lumen из своей памяти. Править удобнее в приложении: правки здесь перезапишутся.", ""] + lines)
            .joined(separator: "\n") + "\n"
    }

    func writeMemoryFiles() {
        try? memoryFileText(user: true).write(to: userFile, atomically: true, encoding: .utf8)
        try? memoryFileText(user: false).write(to: memoryFile, atomically: true, encoding: .utf8)
    }

    func openInEditor(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// «1,2 тыс. знаков»
    func fileSize(_ text: String) -> String {
        let n = text.count
        if n < 1000 { return "\(n) " + Plural.form(n, "знак", "знака", "знаков") }
        return String(format: "%.1f", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") + " тыс. знаков"
    }
}
