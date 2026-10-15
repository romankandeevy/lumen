import Foundation
import LumenCore
import LumenProviders
import LumenStorage
import Observation

/// Ход чата (turn pipeline, §0 техплана): собрать системный промпт → движок → стрим → база.
/// Подписка — тёплый процесс `claude` на разговор, API — запрос со всей историей.
@MainActor @Observable
final class ChatController {
    private unowned let app: AppModel

    /// Открытый разговор и его сообщения
    private(set) var conversation: Conversation?
    private(set) var messages: [ChatMessage] = []
    /// Идёт ход: текст ответа копится здесь, в базу — по окончании
    private(set) var streaming: ChatMessage?
    private(set) var thinking = false

    @ObservationIgnored private var sessions: [String: ClaudeSession] = [:]
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false

    init(app: AppModel) {
        self.app = app
    }

    var busy: Bool { streaming != nil || thinking }

    // MARK: открыть / новый

    func open(_ c: Conversation) {
        guard conversation?.id != c.id else { return }
        stop()
        conversation = c
        messages = (try? app.store.messages(in: c.id)) ?? []
    }

    /// Новый чат ещё не в базе: появится в списке после первого сообщения
    func startNew() {
        stop()
        conversation = nil
        messages = []
    }

    /// Модель и «сколько думать» для следующего хода
    func set(model: ChatModel? = nil, effort: Effort? = nil) {
        app.update {
            if let model { $0.model = model }
            if let effort { $0.effort = effort }
        }
        guard var c = conversation else { return }
        if let model { c.model = model }
        if let effort { c.effort = effort }
        conversation = c
        try? app.store.save(c)
    }

    // MARK: ход

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        var c = conversation ?? Conversation(title: Self.title(from: text), backend: app.prefs.backend,
                                             model: app.prefs.model, effort: app.prefs.effort)
        let isNew = conversation == nil
        if c.backend == .subscription && c.cliSessionID == nil { c.cliSessionID = UUID().uuidString.lowercased() }
        do {
            try app.store.save(c)
            let user = try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: text))
            conversation = c
            messages.append(user)
        } catch {
            return
        }
        if isNew { app.reloadConversations() }

        stopRequested = false
        thinking = true
        app.orb = .thinking
        let history = messages
        turnTask = Task { [weak self] in
            guard let self else { return }
            if c.backend == .subscription {
                await self.runCLI(c, text: text, hadTurnsBefore: history.contains { $0.role == .assistant && $0.error == nil })
            } else {
                await self.runAPI(c, history: history)
            }
            self.thinking = false
            self.app.orb = .idle
            self.turnTask = nil
            self.app.reloadConversations()
        }
    }

    /// «Стоп»: подписка — сообщение `interrupt` процессу, API — обрыв соединения
    func stop() {
        guard busy else { return }
        stopRequested = true
        if let id = conversation?.id { sessions[id]?.interrupt() }
        if conversation?.backend == .api { turnTask?.cancel() }
    }

    private func runCLI(_ c: Conversation, text: String, hadTurnsBefore: Bool) async {
        guard let cli = app.cli else {
            finish(c, text: "", error: "Claude Code не найден. Поставь его и войди в Настройках → Модели и оплата.")
            return
        }
        do {
            let session = try cliSession(for: c, cli: cli, resume: hadTurnsBefore)
            var answer = ""
            var result: ClaudeEvent.TurnResult?
            for await ev in try session.send(text) {
                switch ev {
                case .textDelta(let t):
                    answer += t
                    appendStreaming(t, c)
                case .finished(let r):
                    result = r
                default: break
                }
            }
            guard let result else {
                sessions[c.id] = nil
                finish(c, text: answer, error: Self.cliError(session.errorOutput))
                return
            }
            if stopRequested {
                finish(c, text: answer, stopped: true)
            } else if result.ok {
                finish(c, text: answer.isEmpty ? result.text : answer)
            } else {
                finish(c, text: answer, error: Self.cliError(result.text))
            }
        } catch {
            finish(c, text: "", error: error.localizedDescription)
        }
    }

    /// Тёплый процесс на разговор. Если сменились модель или effort — перезапуск с `--resume`.
    private func cliSession(for c: Conversation, cli: ClaudeCLI, resume: Bool) throws -> ClaudeSession {
        if let s = sessions[c.id], s.isRunning, s.config.model == c.model.rawValue, s.config.effort == c.effort.rawValue {
            return s
        }
        sessions[c.id]?.close()
        // не больше трёх живых процессов: старые гасим, их ход продолжится через --resume
        if sessions.count >= 3, let oldest = sessions.keys.first(where: { $0 != c.id }) {
            sessions[oldest]?.close()
            sessions[oldest] = nil
        }
        let s = try ClaudeSession(cli: cli, config: .init(
            model: c.model.rawValue, effort: c.effort.rawValue, systemPrompt: app.systemPrompt(),
            tools: [], userSettings: false, sessionID: c.cliSessionID ?? UUID().uuidString.lowercased(), resume: resume))
        sessions[c.id] = s
        return s
    }

    private func runAPI(_ c: Conversation, history: [ChatMessage]) async {
        guard let key = app.keychain.read(Keychain.anthropicKey) else {
            finish(c, text: "", error: APIChatError.noKey.localizedDescription)
            return
        }
        let request = AnthropicChatRequest(model: c.model, effort: c.effort, system: app.systemPrompt(),
                                           messages: AnthropicChatRequest.history(history))
        var answer = ""
        do {
            for try await ev in AnthropicAPI(key: key).chat(request) {
                switch ev {
                case .textDelta(let t):
                    answer += t
                    appendStreaming(t, c)
                case .finished(let reason, let content, _):
                    if reason == "refusal" {
                        finish(c, text: answer, error: "Модель отказалась отвечать на это сообщение.")
                    } else {
                        finish(c, text: answer, apiContent: content)
                    }
                    return
                }
            }
            // поток кончился без конца ответа — значит, нажали «Стоп»
            finish(c, text: answer, stopped: true)
        } catch {
            finish(c, text: answer, stopped: stopRequested, error: stopRequested ? nil : error.localizedDescription)
        }
    }

    private func appendStreaming(_ t: String, _ c: Conversation) {
        if thinking {
            thinking = false
            app.orb = .idle
        }
        if streaming == nil { streaming = ChatMessage(conversationID: c.id, role: .assistant, text: "", model: c.model) }
        streaming?.text += t
    }

    private func finish(_ c: Conversation, text: String, apiContent: String? = nil, stopped: Bool = false, error: String? = nil) {
        streaming = nil
        let m = ChatMessage(conversationID: c.id, role: .assistant, text: text, apiContent: apiContent,
                            model: c.model, stopped: stopped, error: error)
        if let saved = try? app.store.save(m), conversation?.id == c.id { messages.append(saved) }
    }

    // MARK: мелочи

    /// Заголовок — начало первого сообщения
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 48 ? String(line.prefix(46)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// Ошибки `claude` — человеческими словами (docs/spikes.md: старая версия для Opus 5.5)
    static func cliError(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("or newer is required") {
            return "Для этой модели нужен Claude Code новее. Обнови в терминале: claude update"
        }
        if s.localizedCaseInsensitiveContains("rate limit") || s.contains("429") {
            return "Лимит подписки на сейчас исчерпан. Подожди сброса или переключи новый чат на API в Настройках."
        }
        if s.isEmpty || s.hasPrefix("[claude-code:unrecognized_model]") {
            return "Claude Code завершился без ответа. Отправь ещё раз."
        }
        return s
    }
}

extension AppModel {
    /// Системный промпт Lumen (SOUL v0): кто он, с кем говорит, закреплённые факты.
    /// Детерминированный — одинаковый от хода к ходу, поэтому кэшируется.
    func systemPrompt() -> String {
        var lines = ["Ты — Lumen, личный помощник на Маке. Отвечай по-русски, если тебя не попросили иначе. Пиши по делу, без воды."]
        if !profile.name.isEmpty { lines.append("Собеседника зовут \(profile.name).") }
        lines.append(profile.address == .ty ? "Обращайся к нему на «ты»." : "Обращайся к нему на «вы».")
        let pinned = ((try? store.memories()) ?? []).filter(\.pinned).map(\.text)
        if !pinned.isEmpty {
            lines.append("Что ты знаешь о нём:")
            lines += pinned.map { "- \($0)" }
        }
        lines.append("Это чат: у тебя нет доступа к файлам и командам этого Мака.")
        return lines.joined(separator: "\n")
    }
}
