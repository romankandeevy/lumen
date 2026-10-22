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
        // экран новой задачи при открытом браузере: колонка не должна выходить за свою область
        let browserWasOpenForHome = browserOpen
        shots.insert(("agent-new-browser", { [self] in tab = .agent; newAgentTask(); browserOpen = true }), at: 3)
        shots.insert(("agent-new-browser-restore", { [self] in browserOpen = browserWasOpenForHome }), at: 4)
        // браузер сбоку: адрес наверху у крестика, вкладки под ним
        let browserWasOpen = browserOpen
        shots.append(("browser", { [self] in
            searchOpen = false; page = .chat; browserOpen = true
            if let u = URL(string: "https://example.com") { browser.open(u) }
            browser.newTab(configuration: nil)
            if let u = URL(string: "https://www.wikipedia.org") { browser.open(u) }
        }))
        shots.append(("browser-restore", { [self] in browserOpen = browserWasOpen }))
        // правая панель блоками
        let panelWasOpen = prefs.contextOpen
        shots.append(("chat-panel", { [self] in update { $0.contextOpen = true }; tab = .chat; if let c = conversations.first(where: { $0.kind == .chat }) { openChat(c) } }))
        shots.append(("chat-panel-restore", { [self] in update { $0.contextOpen = panelWasOpen } }))
        // темы: свет и своя тема — чат и «Тема»; в конце вернуть как было
        let was = (prefs.themeID, prefs.appearance, prefs.userThemes)
        let firstChat = conversations.first(where: { $0.kind == .chat })
        shots.append(("theme-light-new", { [self] in update { $0.themeID = "lumen"; $0.appearance = .light }; tab = .chat; newChat() }))
        shots.append(("theme-light-chat", { [self] in update { $0.themeID = "lumen"; $0.appearance = .light }; tab = .chat; if let firstChat { openChat(firstChat) } }))
        shots.append(("theme-light-settings", { [self] in page = .settings(.theme) }))
        shots.append(("theme-custom-chat", { [self] in
            update { $0.userThemes.append(UserTheme(id: "user-shot", name: "Проба", hue: 245, tint: 0.7)); $0.themeID = "user-shot"; $0.appearance = .dark }
            page = .chat; if let firstChat { openChat(firstChat) }
        }))
        shots.append(("theme-custom-light-settings", { [self] in update { $0.appearance = .light }; page = .settings(.theme) }))
        shots.append(("theme-restore", { [self] in update { $0.themeID = was.0; $0.appearance = was.1; $0.userThemes = was.2 } }))
        for s in SettingsView.Section.visible(self) {
            shots.append(("settings-\(s)", { [self] in searchOpen = false; page = .settings(s) }))
        }
        // поле ввода с чипом бота и длинным текстом: через тот же запрос «@id», что и щелчок по участнику группы
        shots.insert(("composer-chip", { [self] in
            tab = .chat; newChat()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                chat.mentionRequest = "@designer привет, как дела? Это длинный текст, чтобы проверить перенос строки под чипом и поведение поля ввода при росте текста вниз, а потом стереть всё ⌫"
            }
        }), at: 0)
        // стартовый экран с текстом в поле: знак «горячий»
        shots.append(("chat-new-hot", { [self] in
            tab = .chat; newChat()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                chat.mentionRequest = "привет"
            }
        }))
        // LUMEN_SELFSHOT_ONLY=имя,имя — только эти снимки
        if let only = ProcessInfo.processInfo.environment["LUMEN_SELFSHOT_ONLY"] {
            let names = Set(only.split(separator: ",").map(String.init))
            shots = shots.filter { names.contains($0.0) }
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
