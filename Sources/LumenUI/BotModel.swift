import AppKit
import Foundation
import LumenCore
import LumenProviders

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

    /// Правила бота: роль, что ему доступно и что отрезано, кому передавать чужое
    func botPrompt(_ b: Bot) -> String {
        var lines = ["Ты — бот «\(b.name)» (@\(b.id)) в Lumen, приложении на Маке. Твоя роль: \(b.role)."]
        if !b.instructions.isEmpty { lines.append(b.instructions) }
        let granted = BotCapability.allCases.filter { b.capabilities.contains($0) }.map(\.name)
        lines.append("Тебе доступно: \(granted.isEmpty ? "только разговор" : granted.joined(separator: ", ")). "
            + "Отрезано в коде: \(BotPermissions.blocked(b).joined(separator: ", ")). Этих инструментов у тебя нет — не пытайся обойти.")
        if b.capabilities.contains(.run) && !b.capabilities.contains(.write) && !b.commands.isEmpty {
            lines.append("Команды можно запускать только такие: \(b.commands.joined(separator: ", ")).")
        }
        let handoff = b.handoff.flatMap { bot($0) }.map { "@\($0.id) (\($0.name))" } ?? "Lumen"
        lines.append("Если просят то, что не по роли, — коротко откажись и предложи передать это \(handoff). Не делай чужую работу наполовину.")
        lines.append("Push, публикацию и выкатку не делай: это только человек.")
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name), обращайся на \(profile.address == .ty ? "«ты»" : "«вы»").") }
        lines.append("Отвечай по-русски, коротко и по делу: что сделал, что нашёл, что дальше.")
        return lines.joined(separator: "\n")
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
