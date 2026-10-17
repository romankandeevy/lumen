import Foundation
import Testing
@testable import LumenCore
@testable import LumenStorage
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

@MainActor @Test func savedPersonaGoesIntoChatAndAgentPrompts() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-persona-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    var p = Persona()
    p.always = ["Начинать ответ со слова ЙОХО"]
    app.savePersona(p)
    #expect(app.systemPrompt().contains("Начинать ответ со слова ЙОХО"))
    #expect(app.agentPrompt().contains("Начинать ответ со слова ЙОХО"))
    // после перезапуска приложения — тот же характер
    let again = try AppModel(paths: AppPaths(root: home))
    #expect(again.persona == p)
}
