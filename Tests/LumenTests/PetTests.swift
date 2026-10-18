import Foundation
import Testing
@testable import LumenCore

// Питомец: пресеты проходят проверку, ответ модели разбирается, плохие ответы отклоняются, старые настройки читаются.

/// Проблемы, которые нашли в ответе модели; пусто — ответ принят
private func failures(_ text: String) -> [String] {
    if case .failure(let found) = PetSpec.parse(text) { return found }
    return []
}

private func part(_ color: String = "#F2A65A", role: String = "body", w: Double = 60) -> String {
    #"{"shape": "ellipse", "role": "\#(role)", "x": 20, "y": 40, "w": \#(w), "h": 40, "color": "\#(color)"}"#
}

private func answer(_ parts: [String], name: String = "Лис") -> String {
    #"{"name": "\#(name)", "parts": [\#(parts.joined(separator: ", "))]}"#
}

@Test func everyPresetPassesCheck() {
    for pet in PetPresets.all {
        #expect(pet.problems.isEmpty, "\(pet.name): \(pet.problems)")
    }
}

@Test func presetIdsAreUniqueAndFindable() {
    let ids = PetPresets.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(PetPresets.named("robot")?.name == "Робот")
    #expect(PetPresets.named("nope") == nil)
}

@Test func parseTakesJSONOutOfWordsAndFences() {
    let text = """
    Вот питомец:
    ```json
    \(answer([part()], name: "  Лис  "))
    ```
    """
    guard case .success(let spec) = PetSpec.parse(text) else {
        Issue.record("ответ с словами и ``` не разобрался")
        return
    }
    #expect(spec.name == "Лис")
    #expect(spec.id == "custom")
    // поворот и скругление модель может не написать — берём 0
    #expect(spec.parts.first?.rotation == 0)
    #expect(spec.parts.first?.radius == 0)
}

@Test func parseRejectsAnswerWithoutJSON() {
    #expect(failures("просто текст") == ["в ответе нет JSON"])
}

@Test func parseRejectsUnknownShape() {
    let text = #"{"name": "Х", "parts": [{"shape": "star", "role": "body", "x": 0, "y": 0, "w": 10, "h": 10, "color": "#000000"}]}"#
    #expect(failures(text).first?.hasPrefix("JSON не по схеме") == true)
}

@Test func petNeedsBody() {
    let found = failures(answer([part(role: "eye")]))
    #expect(found.contains { $0.hasPrefix("нет тела") })
}

@Test func colorMustBeHex() {
    let found = failures(answer([part("red")]))
    #expect(found.contains { $0.hasPrefix("фигура 1: цвет") })
}

@Test func sizeStaysInsideField() {
    let found = failures(answer([part(w: 150)]))
    #expect(found.contains { $0.hasPrefix("фигура 1: размер") })
}

@Test func partCountIsLimited() {
    let found = failures(answer(Array(repeating: part(), count: PetSpec.maxParts + 1)))
    #expect(found.contains { $0.hasPrefix("фигур больше") })
}

@Test func emptyNameIsRejected() {
    let found = failures(answer([part()], name: "   "))
    #expect(found.contains { $0.hasPrefix("имя") })
}

@Test func oldPreferencesReadWithPetOff() throws {
    // настройки до питомца: поля нет — питомца нет
    let prefs = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(prefs.petEnabled == false)
    #expect(prefs.petID == "cat")
    #expect(prefs.petX == nil)
    #expect(prefs.petY == nil)
}
