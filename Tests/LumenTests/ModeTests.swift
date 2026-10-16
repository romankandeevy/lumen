import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// Режимы агента (как в Claude Code): План, Спрашивать, Принимать правки, Авто, Обход.
// Вопросы «можно?» приходят в Lumen через stdio (docs/spikes.md, спайк режимов).

@Test func modeArgumentsAskHostOnlyWhenNeeded() {
    let folder = URL(fileURLWithPath: "/tmp")
    for m in AgentMode.allCases {
        let c = ClaudeSession.Config.agent(model: "claude-haiku-5-5", effort: "low", persona: "", folder: folder, sessionID: "s", resume: false, mode: m.rawValue)
        let a = c.arguments
        #expect(a.contains(m.rawValue))
        #expect(a.contains("--permission-prompt-tool") == (m != .bypassPermissions))
        // push запрещён в любом режиме, правка и команды не разрешены заранее
        #expect(c.disallowedTools.contains("Bash(git push:*)"))
        #expect(!c.allowedTools.contains("Edit") && !c.allowedTools.contains("Bash"))
    }
}

@Test func permissionRequestIsDecoded() {
    let line = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/x/a.txt","content":"ok"},"description":"a.txt"}}"#
    guard case .permission(let p)? = ClaudeEvent.decode(Data(line.utf8)) else { Issue.record("не разобран"); return }
    #expect(p.id == "r1" && p.tool == "Write" && p.input["content"] as? String == "ok")
    #expect(p.step.text == "Пишет a.txt")
}

private let live = ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"

@Suite(.serialized) struct LiveModeSuite {
    @MainActor func setup(_ mode: AgentMode) async throws -> (AppModel, URL, URL) {
        pointToMCP()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lumen-mode-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("proj")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = try AppModel(paths: AppPaths(root: root.appendingPathComponent("home")))
        await app.refreshClaude()
        app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
        app.tab = .agent
        app.agentFolder = folder
        app.chat.set(model: .haiku, effort: .low)
        app.chat.set(mode: mode)
        app.newAgentTask()
        return (app, root, folder)
    }

    /// Ждать, пока ход кончится или агент спросит разрешения
    @MainActor func wait(_ app: AppModel) async throws {
        for _ in 0..<600 {
            if !app.chat.busy || app.chat.pendingPermission != nil { return }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    @MainActor @Test(.enabled(if: live)) func liveManualAsksAndObeys() async throws {
        let (app, root, folder) = try await setup(.manual)
        defer { try? FileManager.default.removeItem(at: root) }
        app.chat.send("Создай файл a.txt со словом ok. Больше ничего.")
        try await wait(app)
        let ask = try #require(app.chat.pendingPermission)
        #expect(ask.request.tool == "Write")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
        app.chat.answerPermission(allow: true)
        try await wait(app)
        while app.chat.busy && app.chat.pendingPermission == nil { try await Task.sleep(for: .milliseconds(200)) }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))

        // отказ — файла нет
        app.chat.send("Теперь создай файл b.txt со словом no.")
        try await wait(app)
        if app.chat.pendingPermission != nil { app.chat.answerPermission(allow: false) }
        while app.chat.busy {
            if app.chat.pendingPermission != nil { app.chat.answerPermission(allow: false) }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("b.txt").path))
    }

    @MainActor @Test(.enabled(if: live)) func liveAcceptEditsWritesButAsksForCommands() async throws {
        let (app, root, folder) = try await setup(.acceptEdits)
        defer { try? FileManager.default.removeItem(at: root) }
        // простые файловые команды (touch, mkdir) Claude Code в этом режиме считает правками — проверяем запуск кода
        app.chat.send("Создай файл a.txt со словом ok, а потом выполни в терминале ровно эту команду: python3 -c \"open('b.txt','w').write('x')\"")
        var askedFor: [String] = []
        while app.chat.busy {
            if let p = app.chat.pendingPermission {
                askedFor.append(p.request.tool)
                app.chat.answerPermission(allow: false)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
        #expect(!askedFor.contains("Write") && askedFor.contains("Bash"))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("b.txt").path))
    }

    @MainActor @Test(.enabled(if: live)) func livePlanChangesNothingThenRuns() async throws {
        let (app, root, folder) = try await setup(.plan)
        defer { try? FileManager.default.removeItem(at: root) }
        app.chat.send("Нужно создать файл a.txt со словом ok. Составь план и предложи выполнить.")
        try await wait(app)
        let ask = try #require(app.chat.pendingPermission)
        #expect(ask.request.tool == "ExitPlanMode")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
        app.chat.answerPlan(run: .acceptEdits)
        #expect(app.chat.conversation?.mode == .acceptEdits)
        while app.chat.busy {
            if app.chat.pendingPermission != nil { app.chat.answerPermission(allow: true) }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
    }

    @MainActor @Test(.enabled(if: live)) func liveBypassAndAutoDoWithoutAsking() async throws {
        for mode in [AgentMode.bypassPermissions, .auto] {
            let (app, root, folder) = try await setup(mode)
            defer { try? FileManager.default.removeItem(at: root) }
            app.chat.send("Создай файл a.txt со словом ok. Больше ничего.")
            var asked = false
            while app.chat.busy {
                if app.chat.pendingPermission != nil { asked = true; app.chat.answerPermission(allow: true) }
                try await Task.sleep(for: .milliseconds(200))
            }
            let reply = try #require(app.chat.messages.last)
            #expect(reply.error == nil, "\(mode): \(reply.error ?? "")")
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path), "\(mode)")
            if mode == .bypassPermissions { #expect(!asked) }
        }
    }
}
