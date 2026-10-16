import AppKit
import SwiftUI

/// Снимки настоящего окна для проверки без доступа к экрану: `open build/Lumen.app --env LUMEN_SELFSHOT=/папка`.
/// Lumen по очереди открывает главные страницы и сохраняет PNG своего окна (рисует сам, разрешение
/// «Запись экрана» не нужно). Данные — настоящие, ничего не меняется, кроме открытой страницы.
extension AppModel {
    func selfShotIfAsked() async {
        guard let dir = ProcessInfo.processInfo.environment["LUMEN_SELFSHOT"], !dir.isEmpty else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        var shots: [(String, () -> Void)] = [
            ("chat", { [self] in tab = .chat; if let c = conversations.first(where: { $0.kind == .chat }) { openChat(c) } else { newChat() } }),
            ("chat-new", { [self] in tab = .chat; newChat() }),
            ("agent-new", { [self] in tab = .agent; newAgentTask() }),
            ("bots", { [self] in page = .bots }),
            ("skills", { [self] in skillsMode = .mine; page = .skills }),
            ("skills-catalog", { [self] in skillsMode = .catalog; page = .skills }),
            ("memory", { [self] in memoryMode = .facts; page = .memory }),
            ("memory-graph", { [self] in memoryMode = .graph; page = .memory }),
            ("search", { [self] in page = .chat; searchOpen = true }),
        ]
        if let c = conversations.first(where: { $0.kind == .agent }) {
            shots.insert(("agent", { [self] in openChat(c) }), at: 3)
        }
        for s in SettingsView.Section.visible(self) {
            shots.append(("settings-\(s)", { [self] in searchOpen = false; page = .settings(s) }))
        }
        for (name, go) in shots {
            go()
            // каталог тянется из сети — ему дольше
            try? await Task.sleep(for: .seconds(name == "skills-catalog" ? 5 : 1.5))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
        }
        searchOpen = false
        // вернуть окно как было: «Чат» с новым разговором, а не открытой задачей агента
        switchTab(.chat)
        newChat()
        try? "done".write(to: out.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}
