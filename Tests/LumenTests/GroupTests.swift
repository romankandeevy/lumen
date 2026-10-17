import Foundation
import Testing
@testable import LumenCore
@testable import LumenUI

// Группы ботов — как в Hermes Agent: кто отвечает, по очереди, «(pass)», что видит участник.

private let a = Bot(id: "designer", name: "Дизайнер")
private let b = Bot(id: "coder", name: "Кодер")
private let c = Bot(id: "tester", name: "Тестировщик")

private func msg(_ id: Int64, _ role: ChatMessage.Role, _ text: String, bot: String? = nil) -> ChatMessage {
    var m = ChatMessage(id: id, conversationID: "g", role: role, text: text)
    m.botID = bot
    return m
}

@Test func groupRoomPicksSpeakersLikeHermes() {
    let all = [a, b, c]
    // без упоминаний — все; с @ — только упомянутые; @все — все
    #expect(GroupRoom.responders(log: [msg(1, .user, "что думаете?")], members: all).map(\.id) == ["designer", "coder", "tester"])
    #expect(GroupRoom.responders(log: [msg(1, .user, "@coder сделай")], members: all).map(\.id) == ["coder"])
    #expect(GroupRoom.responders(log: [msg(1, .user, "@все привет")], members: all).count == 3)
    // бот позвал коллегу — тот подключается в следующем раунде
    let log = [msg(1, .user, "@coder сделай"), msg(2, .assistant, "готово, @tester проверь", bot: "coder")]
    #expect(Set(GroupRoom.responders(log: log, members: all).map(\.id)) == ["coder", "tester"])
    #expect(GroupRoom.addressed(log: log, members: all) == ["coder"])
    // первым каждый раунд говорит другой
    #expect(GroupRoom.rotate(all, round: 1).map(\.id) == ["coder", "tester", "designer"])
    #expect(GroupRoom.isPass("(pass)") && GroupRoom.isPass(" «(pass)». ") && GroupRoom.isPass("") && !GroupRoom.isPass("pass the salt"))
}

@Test func groupMemberSeesOnlyWhatIsNewWithRules() {
    let all = [a, b]
    let log = [msg(1, .user, "привет"), msg(2, .assistant, "привет от дизайнера", bot: "designer"), msg(3, .user, "@coder твоя очередь")]
    let delta = GroupRoom.delta(log, after: 1, viewer: a, userName: "Рома", members: all)
    #expect(delta == ["Дизайнер (@designer) (ты): привет от дизайнера", "Рома (человек): @coder твоя очередь"])
    let p = GroupRoom.prompt(group: BotGroup(name: "Команда", members: ["designer", "coder"]), viewer: b, members: all, delta: delta)
    #expect(p.contains("Ты — @coder") && p.contains("Дизайнер (@designer)") && p.contains("«(pass)»") && p.contains("привет от дизайнера"))
}

@MainActor @Test func groupIsStoredWithItsConversation() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-grp-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.saveBot(a); app.saveBot(b)
    let g = app.saveGroup(BotGroup(name: "Команда", members: ["designer", "coder", "ghost"]))
    #expect(g.members == ["designer", "coder"])          // несуществующий бот отброшен
    app.openGroup(g.id)
    #expect(app.page == .group(g.id) && app.chat.conversation?.kind == .group && app.chat.conversation?.groupID == g.id)
    // сессии участников — постоянные и разные
    let c1 = app.memberConversation(app.chat.conversation!, bot: a)
    #expect(c1.cliSessionID == app.memberConversation(app.chat.conversation!, bot: a).cliSessionID)
    #expect(c1.cliSessionID != app.memberConversation(app.chat.conversation!, bot: b).cliSessionID)
    #expect(UUID(uuidString: c1.cliSessionID ?? "") != nil)
    app.deleteGroup(g)
    #expect(app.groups.isEmpty && !app.conversations.contains { $0.kind == .group })
}

/// Живая: группа из двух ботов отвечает по очереди, лишний молчит
@Suite(.serialized) struct LiveGroupSuite {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1")) func liveGroupTakesTurns() async throws {
        pointToMCP()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-livegrp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(paths: AppPaths(root: root))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.saveBot(Bot(id: "red", name: "Красный", role: "Любит красный цвет", instructions: "Ты любишь красный. Отвечай очень коротко.", model: .haiku, effort: .low))
        app.saveBot(Bot(id: "blue", name: "Синий", role: "Любит синий цвет", instructions: "Ты любишь синий. Отвечай очень коротко.", model: .haiku, effort: .low))
        let g = app.saveGroup(BotGroup(name: "Цвета", members: ["red", "blue"]))
        app.openGroup(g.id)
        app.chat.send("Каждый назовите свой любимый цвет одним словом.")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let replies = app.chat.messages.filter { $0.role == .assistant }
        print("DBG", replies.map { "\($0.botID ?? "?"): \($0.text.prefix(60))" })
        #expect(Set(replies.compactMap(\.botID)) == ["red", "blue"])
        #expect(!replies.contains { GroupRoom.isPass($0.text) })
        #expect(replies.count <= BotGroup.maxMessages)
        // только к одному
        app.chat.send("@blue а теперь ещё раз, одним словом")
        while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
        let last = app.chat.messages.last
        #expect(last?.botID == "blue", "\(app.chat.messages.suffix(3).map(\.text))")
    }
}
