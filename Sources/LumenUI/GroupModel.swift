import CryptoKit
import Foundation
import LumenCore

// Группы ботов (как в Hermes Agent): список, создание, разговор группы. Ходы — ChatController.runGroup.

extension AppModel {
    func reloadGroups() {
        groups = (try? store.groups()) ?? []
    }

    func group(_ id: String?) -> BotGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    func groupMembers(_ g: BotGroup) -> [Bot] {
        g.members.compactMap { bot($0) }
    }

    @discardableResult
    func saveGroup(_ g: BotGroup) -> BotGroup {
        var g = g
        g.members = Array(g.members.filter { bot($0) != nil }.prefix(BotGroup.maxMembers))
        try? store.save(g)
        // название в разговоре — как у группы
        if var c = conversations.first(where: { $0.kind == .group && $0.groupID == g.id }), c.title != g.name {
            c.title = g.name
            try? store.save(c)
        }
        reloadGroups()
        reloadConversations()
        return g
    }

    func deleteGroup(_ g: BotGroup) {
        if let c = conversations.first(where: { $0.kind == .group && $0.groupID == g.id }) { chat.forget(c.id) }
        try? store.deleteGroup(g.id)
        reloadGroups()
        reloadConversations()
        if case .group(let id) = page, id == g.id { page = .bots }
    }

    /// Один постоянный разговор группы
    func groupConversation(for g: BotGroup) -> Conversation {
        if let c = conversations.first(where: { $0.kind == .group && $0.groupID == g.id })
            ?? (try? store.conversations())?.first(where: { $0.kind == .group && $0.groupID == g.id }) {
            return c
        }
        var c = Conversation(title: g.name, kind: .group, backend: prefs.backend, model: .sonnet, effort: .medium)
        c.groupID = g.id
        try? store.save(c)
        reloadConversations()
        return c
    }

    func openGroup(_ id: String) {
        guard let g = group(id) else { page = .bots; return }
        let c = groupConversation(for: g)
        if chat.conversation?.id != c.id { chat.open(c) }
        tab = .bots
        page = .group(id)
        // участники видны справа сразу
        if !prefs.contextOpen { update { $0.contextOpen = true } }
    }

    /// Сессия участника в группе: свой процесс claude на пару «группа + бот», постоянный id —
    /// чтобы между ходами он помнил разговор (--resume)
    func memberConversation(_ c: Conversation, bot b: Bot) -> Conversation {
        let digest = Insecure.MD5.hash(data: Data("\(c.id)/\(b.id)".utf8))
        var bytes = Array(digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        var m = Conversation(id: "\(c.id)~\(b.id)", title: c.title, kind: .bot, folder: botFolder(b).path, backend: c.backend,
                             model: b.model, effort: b.effort, cliSessionID: uuid.uuidString.lowercased())
        m.botID = b.id
        return m
    }
}
