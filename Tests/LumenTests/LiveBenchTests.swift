import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI
@testable import LumenStorage

// Пять задач (tools/agent-bench) на агенте Lumen — тем же путём, что в приложении: правила, страж, план, присутствие.
//   LUMEN_BENCH=~/bench LUMEN_BENCH_MODEL=haiku swift test --filter liveBench
// Ответы целиком — в ~/bench/lumen/<задача>.answer.md

private let benchDir = ProcessInfo.processInfo.environment["LUMEN_BENCH"]

@MainActor @Test(.enabled(if: benchDir != nil), .timeLimit(.minutes(120))) func liveBench() async throws {
    pointToMCP()
    let root = URL(fileURLWithPath: try #require(benchDir))
    let model: ChatModel = ChatModel.claude.first { $0.name.lowercased().hasPrefix(ProcessInfo.processInfo.environment["LUMEN_BENCH_MODEL"] ?? "haiku") } ?? .haiku
    for task in ["01-bug", "02-rename", "03-explain", "04-feature", "05-spec"] {
        let dir = root.appendingPathComponent("lumen/\(task)")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-bench-\(task)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let app = try AppModel(paths: AppPaths(root: home))
        await app.refreshClaude()
        app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
        app.update { $0.agentModel = model; $0.agentEffort = .high; $0.agentMode = .bypassPermissions }
        app.tab = .agent
        app.agentFolder = dir
        app.newAgentTask()
        let text = try String(contentsOf: dir.appendingPathComponent("TASK.md"), encoding: .utf8)
        let start = Date()
        app.chat.send(text)
        // ход и всё, что Lumen запустит сам (сжатие, «реши сам»): ждём 8 с тишины
        var quietSince: Date?
        while Date().timeIntervalSince(start) < 25 * 60 {
            if app.chat.busy || !app.chat.openQueue.isEmpty { quietSince = nil } else { quietSince = quietSince ?? Date() }
            if let q = quietSince, Date().timeIntervalSince(q) > 8 { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        let secs = Int(Date().timeIntervalSince(start))
        let c = try #require(app.chat.conversation)
        let msgs = try app.store.messages(in: c.id)
        let steps = msgs.reduce(0) { $0 + $1.steps.count }
        var out = "# Lumen · \(task)\n\nВремя: \(secs / 60) мин \(secs % 60) с · шагов: \(steps) · модель: \(model.name)\n"
        for m in msgs {
            if m.role == .user {
                let who = m.via?.autoReason.map { "Lumen сам (\($0))" } ?? "Человек"
                out += "\n## \(who)\n\n\(m.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                continue
            }
            out += "\n## Агент\n\n"
            for piece in AnswerPiece.layout(text: NextStep.split(m.text).text, steps: m.steps) {
                switch piece {
                case .text(let t): out += t.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                case .steps(let s): out += s.map { "> шаг: \($0.text)" }.joined(separator: "\n") + "\n\n"
                }
            }
            if let n = m.next { out += "**Карточка «что дальше»:** \(n.recap)" + (n.ask.map { " · Вопрос: \($0)" } ?? "") + "\n\n" }
            if let note = m.note { out += "_\(note)_\n\n" }
            if let e = m.error { out += "**Ошибка:** \(e)\n\n" }
        }
        try out.write(to: root.appendingPathComponent("lumen/\(task).answer.md"), atomically: true, encoding: .utf8)
        // журнал Lumen — сколько раз страж возвращал агента и что Lumen делал сам
        let log = (try? String(contentsOf: home.appendingPathComponent("logs/lumen.log"), encoding: .utf8)) ?? ""
        try log.write(to: root.appendingPathComponent("lumen/\(task).lumen.log"), atomically: true, encoding: .utf8)
        print("lumen \(task): \(secs) с, сообщений \(msgs.count)")
    }
}
