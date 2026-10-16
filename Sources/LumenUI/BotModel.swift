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
        if var c = conversations.first(where: { $0.kind == .bot && $0.botID == b.id }) {
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
        let task = rest.dropFirst(id.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return task.isEmpty ? nil : (b, task)
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
