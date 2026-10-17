import AppKit
import LumenCore
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
            ("bot-editor", { [self] in page = .botEditor(nil) }),
            ("skills", { [self] in customizeTab = .skills; skillsMode = .mine; page = .skills }),
            ("skills-catalog", { [self] in customizeTab = .skills; skillsMode = .catalog; page = .skills }),
            ("customize-connectors", { [self] in customizeTab = .connectors; page = .skills }),
            ("customize-hooks", { [self] in customizeTab = .hooks; page = .skills }),
            ("memory", { [self] in memoryMode = .facts; page = .memory }),
            ("memory-graph", { [self] in memoryMode = .graph; page = .memory }),
            ("search", { [self] in page = .chat; searchOpen = true }),
        ]
        if let c = conversations.first(where: { $0.kind == .agent }) {
            shots.insert(("agent", { [self] in openChat(c) }), at: 3)
        }
        if let b = bots.first {
            shots.append(("bot-chat", { [self] in searchOpen = false; openBot(b.id) }))
        }
        // правая панель блоками
        let panelWasOpen = prefs.contextOpen
        shots.append(("chat-panel", { [self] in update { $0.contextOpen = true }; tab = .chat; if let c = conversations.first(where: { $0.kind == .chat }) { openChat(c) } }))
        shots.append(("chat-panel-restore", { [self] in update { $0.contextOpen = panelWasOpen } }))
        // темы: светлая и своя — чат и «Внешний вид»; в конце вернуть как было
        let theme = prefs.theme, custom = prefs.customTheme
        let firstChat = conversations.first(where: { $0.kind == .chat })
        shots.append(("theme-light-chat", { [self] in update { $0.theme = .light }; tab = .chat; if let firstChat { openChat(firstChat) } }))
        shots.append(("theme-light-settings", { [self] in page = .settings(.look) }))
        shots.append(("theme-custom-chat", { [self] in
            update { $0.theme = .custom; $0.customTheme = CustomTheme(dark: true, hue: 245, tint: 0.7) }
            page = .chat; if let firstChat { openChat(firstChat) }
        }))
        shots.append(("theme-custom-light-settings", { [self] in
            update { $0.customTheme = CustomTheme(dark: false, hue: 150, tint: 0.5) }; page = .settings(.look)
        }))
        shots.append(("theme-restore", { [self] in update { $0.theme = theme; $0.customTheme = custom } }))
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
        customizeTab = .skills
        // вернуть окно как было: «Чат» с новым разговором, а не открытой задачей агента
        switchTab(.chat)
        newChat()
        try? "done".write(to: out.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}
