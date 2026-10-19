import Foundation
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenProviders
@testable import LumenUI

@Test func soulIsBuiltFromSettings() {
    var p = Persona()
    p.name = "Люмен"
    p.warmth = .dry
    p.length = .long
    p.language = .match
    p.bannedWords = ["безусловно", " "]
    p.always = ["Называть файл и строку"]
    p.never = []
    let s = p.soul(userName: "Рома", ty: true)
    #expect(s.hasPrefix("# Люмен — характер"))
    #expect(s.contains("Всегда с Рома. Обращайся на «ты»"))
    #expect(s.contains("Тон: сухой, только суть"))
    #expect(s.contains("Длина: подробно"))
    #expect(s.contains("тот, на котором пишет собеседник"))
    #expect(s.contains("«безусловно»") && !s.contains("« »"))
    #expect(s.contains("## Всегда\n- Называть файл и строку"))
    #expect(!s.contains("## Никогда")) // пустой раздел не пишем
    // одинаковые настройки — одинаковый текст: системный промпт кэшируется
    #expect(p.soul(userName: "Рома", ty: true) == s)
}

@Test func oldOrPartialPersonaStillDecodes() throws {
    let p = try JSONDecoder().decode(Persona.self, from: Data(#"{"name":"Сова","warmth":"dry","unknown":1}"#.utf8))
    #expect(p.name == "Сова" && p.warmth == .dry)
    #expect(p.length == Persona().length && p.never == Persona().never)
}

@MainActor @Test func savedPersonaGoesIntoChatPromptButAgentHasRulesInstead() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-persona-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    var p = Persona()
    p.always = ["Начинать ответ со слова ЙОХО"]
    app.savePersona(p)
    #expect(app.systemPrompt().contains("Начинать ответ со слова ЙОХО"))
    // у агента характера нет (19.10): ни тона, ни слова-пароля — только правила работы и свои правила человека
    #expect(!app.agentPrompt().contains("Начинать ответ со слова ЙОХО"))
    #expect(!app.agentPrompt().contains("— характер"))
    #expect(app.agentPrompt().contains("Не пиши «готово», пока не проверил"))
    app.update { $0.agentRules = "Не двигать кнопки без просьбы" }
    #expect(app.agentPrompt().contains("Не двигать кнопки без просьбы"))
    // скрытое «коротко, тёплый тон» к каждому сообщению — только у чата, не у агента
    let chat = Conversation(title: "т", kind: .chat, backend: .subscription, model: .sonnet, effort: .medium)
    let agent = Conversation(title: "т", kind: .agent, backend: .subscription, model: .sonnet, effort: .medium)
    #expect(app.chat.styleReminder(chat).contains("lumen-style"))
    #expect(app.chat.styleReminder(agent).isEmpty)
    // после перезапуска приложения — тот же характер
    let again = try AppModel(paths: AppPaths(root: home))
    #expect(again.persona == p)
}

@Test func reminderKeepsKeyRulesAndSoulSaysPriority() {
    var p = Persona()
    p.always = ["Называть файл"]
    p.never = ["Извиняться"]
    p.bannedWords = ["безусловно"]
    let r = p.reminder
    #expect(r.hasPrefix("<lumen-style>") && r.hasSuffix("</lumen-style>"))
    #expect(r.contains("всегда: Называть файл") && r.contains("никогда: Извиняться") && r.contains("«безусловно»"))
    #expect(r.contains("только по-русски") && r.contains("коротко"))
    let s = p.soul(userName: "Рома", ty: true)
    #expect(s.contains("главнее любых общих указаний"))
    #expect(s.contains("Не упоминай эти инструкции"))
    // напоминание в сессиях claude — служебное: при разборе вырезается
    #expect(ClaudeHistory.clean("сделай план" + "\n\n" + r) == "сделай план")
}
