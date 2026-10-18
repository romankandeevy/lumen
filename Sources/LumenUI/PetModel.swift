import AppKit
import Foundation
import LumenCore

/// Питомец: выбор, включение, место на экране и рисование своего (PetController.swift, PetView.swift)
extension AppModel {
    enum PetDraftError: Error {
        case noAnswer
        case invalid([String])
    }

    /// Питомец, который сейчас на экране: свой, если выбран, иначе пресет
    var petSpec: PetSpec {
        if prefs.petID == "custom", let customPet { return customPet }
        return PetPresets.named(prefs.petID) ?? PetPresets.all[0]
    }

    /// Питомец включается при запуске, если был включён
    func startPetIfNeeded() {
        if prefs.petEnabled { showPet() }
    }

    func setPetEnabled(_ on: Bool) {
        update { $0.petEnabled = on }
        if on { showPet() } else { hidePet() }
    }

    func choosePet(_ id: String) {
        update { $0.petID = id }
        pet?.refresh()
    }

    /// Нарисованный питомец: сохраняется отдельно, выбирается и включается сразу
    func setCustomPet(_ spec: PetSpec) {
        customPet = spec
        try? store.set("pet.custom", spec)
        update {
            $0.petID = "custom"
            $0.petEnabled = true
        }
        showPet()
    }

    func savePetPlace(_ origin: NSPoint) {
        update {
            $0.petX = Double(origin.x)
            $0.petY = Double(origin.y)
        }
    }

    func resetPetPlace() {
        update {
            $0.petX = nil
            $0.petY = nil
        }
        pet?.moveToCorner()
    }

    private func showPet() {
        if let pet {
            pet.refresh()
        } else {
            pet = PetController(app: self)
        }
    }

    private func hidePet() {
        pet?.close()
        pet = nil
    }

    /// Питомец по описанию: модель рисует его из фигур по схеме PetSpec. Ошибки проверки — второй круг с подсказкой
    func draftPet(_ request: String) async -> Result<PetSpec, PetDraftError> {
        let system = """
        Ты рисуешь маленького питомца для Lumen из простых фигур. \(PetSpec.authoringRules)
        Отвечай строго JSON без markdown вокруг: {"name": "…", "parts": [{"shape": "ellipse", "role": "body", "x": 20, "y": 40, "w": 60, "h": 50, "rotation": 0, "radius": 0, "color": "#F2A65A"}]}
        """
        var ask = "Нужен питомец: \(request)"
        var problems: [String] = []
        for _ in 0..<2 {
            guard let answer = await quickAsk(ask, system: system, model: .sonnet, effort: .medium) else { return .failure(.noAnswer) }
            switch PetSpec.parse(answer) {
            case .success(let spec):
                return .success(spec)
            case .failure(let found):
                problems = found
                ask = "Нужен питомец: \(request)\n\nПрошлый ответ не прошёл проверку: \(found.joined(separator: "; ")). Исправь и верни полный JSON.\n\n\(answer.prefix(4000))"
            }
        }
        return .failure(.invalid(problems))
    }
}
