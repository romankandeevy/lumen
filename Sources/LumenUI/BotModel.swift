import AppKit
import Foundation
import LumenCore
import LumenProviders
import LumenStorage

/// Боты в приложении: список, постоянный разговор каждого, вызов через @id, правила для модели.
extension AppModel {
    func bot(_ id: String?) -> Bot? {
        guard let id else { return nil }
        return bots.first { $0.id == id }
    }

    /// Старые сообщения в разговорах ботов были простынёй «Тебя позвали через @… Задача: …» —
    /// переделать в обычное сообщение с пометкой «из чата …» (один раз, при запуске)
    func fixDelegatedMessages() {
        for c in conversations where c.kind == .bot {
            for var m in (try? store.messages(in: c.id)) ?? [] where m.role == .user && m.via == nil {
                let t = m.text
                var title: String?
                var task: String?
                if t.hasPrefix("Тебя позвали через @"), let r = t.range(of: "\n\nЗадача:\n") {
                    task = String(t[r.upperBound...])
                    if let a = t.range(of: "разговора — «"), let b = t[a.upperBound...].range(of: "»") { title = String(t[a.upperBound..<b.lowerBound]) }
                } else if t.hasPrefix("Задача из чата «"), let b = t.range(of: "»:\n") {
                    title = String(t[t.index(t.startIndex, offsetBy: 16)..<b.lowerBound])
                    task = String(t[b.upperBound...])
                } else if t.hasPrefix("Задача от @"), let nl = t.firstIndex(of: "\n") {
                    title = String(t.dropFirst(11).prefix { $0 != " " }).isEmpty ? nil : "@" + String(t.dropFirst(11).prefix { $0 != " " })
                    task = String(t[t.index(after: nl)...])
                }
                guard let task, let title else { continue }
                m.text = task
                m.via = Via(conversationID: conversations.first { $0.title == title && $0.kind != .bot }?.id, title: title)
                _ = try? store.save(m)
            }
        }
    }

    func reloadBots() {
        bots = (try? store.bots()) ?? []
    }

    /// Сохранить бота из конструктора. Сменился @id — разговор и ответы остаются за ним.
    func saveBot(_ b: Bot, replacing oldID: String? = nil) {
        var b = b
        b.updatedAt = Date()
        if let oldID, oldID != b.id {
            try? store.save(b)
            if var c = conversations.first(where: { $0.kind == .bot && $0.botID == oldID }) {
                c.botID = b.id
                try? store.save(c)
            }
            try? store.deleteBot(oldID)
        } else {
            try? store.save(b)
        }
        // процесс бота перезапустится с новыми правами и правилами
        if let c = conversations.first(where: { $0.kind == .bot && $0.botID == b.id }) { chat.restart(c.id) }
        reloadBots()
        reloadConversations()
    }

    func deleteBot(_ b: Bot) {
        if let c = conversations.first(where: { $0.kind == .bot && $0.botID == b.id }) { chat.forget(c.id) }
        try? store.deleteBot(b.id)
        reloadBots()
        reloadConversations()
        page = .bots
    }

    /// Единственный разговор бота: создаётся при первом открытии
    func botConversation(for b: Bot) -> Conversation {
        // разговор мог создать lumen-mcp (Lumen позвал бота сам) — тогда он есть в базе, но не в списке
        if var c = conversations.first(where: { $0.kind == .bot && $0.botID == b.id })
            ?? (try? store.conversations())?.first(where: { $0.kind == .bot && $0.botID == b.id }) {
            // модель и папка — как в паспорте бота сейчас
            if c.model != b.model || c.effort != b.effort || c.folder != botFolder(b).path || c.title != b.name {
                c.model = b.model
                c.effort = b.effort
                c.folder = botFolder(b).path
                c.title = b.name
                try? store.save(c)
            }
            return c
        }
        var c = Conversation(title: b.name, kind: .bot, folder: botFolder(b).path, backend: prefs.backend, model: b.model, effort: b.effort,
                             cliSessionID: UUID().uuidString.lowercased())
        c.botID = b.id
        try? store.save(c)
        reloadConversations()
        return c
    }

    func openBot(_ id: String) {
        guard let b = bot(id) else { page = .bots; return }
        let c = botConversation(for: b)
        if chat.conversation?.id != c.id { chat.open(c) }
        tab = .bots
        page = .bot(id)
    }

    /// Папка бота: своя рабочая или пустая личная (бот без папки не видит чужих файлов)
    func botFolder(_ b: Bot) -> URL {
        if let f = b.folder, FileManager.default.fileExists(atPath: f) { return URL(fileURLWithPath: f) }
        let dir = paths.run.appendingPathComponent("bots/\(b.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// «@tester проверь сборку» → бот и задача. Только известные боты и только в начале сообщения.
    func mention(in text: String) -> (Bot, String)? {
        guard text.hasPrefix("@") else { return nil }
        let rest = text.dropFirst()
        let id = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased()
        guard let b = bot(id) else { return nil }
        // «@designer» без задачи тоже к боту: он сам спросит, чем помочь
        let task = rest.dropFirst(id.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return (b, task)
    }

    /// Правила бота (Bot.rules) с его навыками и списком других ботов
    func botPrompt(_ b: Bot) -> String {
        let skills = SkillLibrary.promptBlock(skillLibrary.enabled(only: Set(b.skills)))
        return b.rules(handoff: b.handoff.flatMap { bot($0) }, userName: profile.name, ty: profile.address == .ty, skills: skills, bots: bots)
    }

    /// Меню бота — как у разговоров
    func showBotMenu(_ b: Bot, at point: CGPoint) {
        menu = MenuState(items: [
            MenuItem(title: "Изменить", key: "e") { [weak self] in self?.page = .botEditor(b.id) },
            MenuItem(title: "Скопировать @\(b.id)", key: "c") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("@\(b.id) ", forType: .string)
            },
            MenuItem(title: "Удалить бота", key: "d", destructive: true, separated: true) { [weak self] in self?.deleteBot(b) },
        ], anchor: point)
    }
}
