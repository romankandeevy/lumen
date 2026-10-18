import Foundation
import SwiftUI
import Testing
@testable import LumenCore
@testable import LumenStorage
@testable import LumenUI

/// Настройки до 1.5 без питомца читаются: питомец выключен, кот, поверх окон, вместо точек
@Test func petPrefsDefaultWhenMissing() throws {
    let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"onboarded":true}"#.utf8))
    #expect(p.pet == PetPrefs())
    #expect(!p.pet.enabled && p.pet.kind == .cat && p.pet.floating && p.pet.inChat && p.pet.side == 64 && p.pet.alwaysInChat)
    // размер вне пределов — в пределы
    let big = try JSONDecoder().decode(PetPrefs.self, from: Data(#"{"side":900}"#.utf8))
    #expect(big.side == PetPrefs.sideRange.upperBound)
    var n = Preferences()
    n.pet.enabled = true; n.pet.kind = .blob; n.pet.blob = BlobLook(shape: .cloud, face: .happy, color: "#4a8df0")
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(n))
    #expect(back.pet == n.pet)
}

/// У бота без своей капли она собирается по оттенку и id, своя — хранится в базе
@Test func botLookDefaultsAndPersists() throws {
    let a = Bot(id: "tester", name: "Тестировщик", hue: 120)
    #expect(a.look == nil)
    #expect(a.blobLook == BlobLook.forBot(id: "tester", hue: 120))
    #expect(abs(BlobLook(color: a.blobLook.color).hue - 120) < 3)
    let store = try Store()
    var b = a
    b.look = BlobLook(shape: .hexagon, face: .curious, color: "#6cc8e8")
    try store.save(b)
    let read = try #require(try store.bots().first { $0.id == "tester" })
    #expect(read.look == b.look)
}

/// Пиксельные кадры: у каждого питомца в каждом состоянии есть что рисовать, кадр меняется со временем
@Test func pixelPetFramesDraw() {
    for kind in PetKind.allCases where kind.isPixel {
        for mood in PetMood.allCases {
            let f = PixelPet.frame(kind, mood, 7)
            #expect(f.count == 32 * 32 * 4)
            let opaque = stride(from: 3, to: f.count, by: 4).filter { f[$0] == 255 }.count
            #expect(opaque > 200, "\(kind) \(mood)")
        }
        #expect(PixelPet.frame(kind, .writing, 0) != PixelPet.frame(kind, .writing, 2))
    }
}

/// Капля перетекает к цели: через секунду форма — как у выбранной, а в «Думает» тело гаснет и видны точки
@Test func blobSimConverges() {
    let sim = BlobSim()
    let look = BlobLook(shape: .hexagon, face: .happy, color: "#4fcf9a")
    var now = 0.0
    for _ in 0..<60 { now += 1.0 / 30; sim.step(.idle, look: look, t: now, now: now, gaze: nil, snap: false) }
    let want = BlobGeo.forms["hexagon"]!.r
    #expect(zip(sim.r, want).allSatisfy { abs($0 - $1) < 1 })
    for _ in 0..<60 { now += 1.0 / 30; sim.step(.thinking, look: look, t: now, now: now, gaze: nil, snap: false) }
    #expect(sim.alpha < 0.05)
    #expect(sim.ea["dots", default: 0] > 0.95)
}

// MARK: снимки (LUMEN_SNAP=/папка swift test --filter Pet)

private let petSnapDir = ProcessInfo.processInfo.environment["LUMEN_SNAP"]

@MainActor @Test(.enabled(if: petSnapDir != nil)) func snapshotPets() async throws {
    Snap.registerFonts()
    let pixel = VStack(alignment: .leading, spacing: 8) {
        ForEach(PetKind.allCases.filter(\.isPixel), id: \.self) { k in
            HStack(spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { m in PixelPetView(kind: k, mood: m, size: 96, animated: false) }
            }
        }
    }
    .padding(16).background(Color(red: 0.1, green: 0.09, blue: 0.08))
    try await Snap.save(pixel, "pets-pixel", size: CGSize(width: 560, height: 560))

    let colors = BlobLook.palette.map(\.hex)
    let blobs = VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
            ForEach(Array(BlobShape.allCases.enumerated()), id: \.offset) { i, s in
                BlobView(look: BlobLook(shape: s, face: .attentive, color: colors[i]), size: 110, animated: false)
            }
        }
        HStack(spacing: 4) {
            ForEach(Array(BlobFace.allCases.prefix(8).enumerated()), id: \.offset) { i, f in
                BlobView(look: BlobLook(shape: .circle, face: f, color: colors[(i + 3) % colors.count]), size: 110, animated: false)
            }
        }
        HStack(spacing: 4) {
            ForEach(Array(BlobAnim.allCases.prefix(7)), id: \.self) { a in
                BlobView(look: BlobLook(), anim: a, size: 110, animated: false)
            }
        }
        HStack(spacing: 4) {
            ForEach(Array(BlobAnim.allCases.suffix(7)), id: \.self) { a in
                BlobView(look: BlobLook(shape: .cloud, face: .curious, color: "#6cc8e8"), anim: a, size: 110, animated: false)
            }
        }
    }
    .padding(16).background(Color(red: 0.1, green: 0.09, blue: 0.08))
    try await Snap.save(blobs, "pets-blob", size: CGSize(width: 940, height: 500))
}

/// Экраны: настройки питомца (зверёк и капля), боты с каплями, конструктор бота, питомец вместо точек
@MainActor @Test(.enabled(if: petSnapDir != nil)) func snapshotPetScreens() async throws {
    Snap.registerFonts()
    let app = try Snap.app()
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    app.update { $0.pet.enabled = true; $0.pet.floating = false; $0.pet.kind = .cat }
    app.page = .settings(.pet)
    try await Snap.save(RootView(app: app), "pet-settings-cat", size: CGSize(width: 1180, height: 1500))
    app.update { $0.pet.kind = .blob; $0.pet.blob = BlobLook(shape: .cloud, face: .happy, color: "#6cc8e8") }
    try await Snap.save(RootView(app: app), "pet-settings-blob", size: CGSize(width: 1180, height: 2000))

    app.saveBot(Bot(id: "tester", name: "Тестировщик", icon: "flask-conical", hue: 160, role: "Проверяет приложения и правки — и только",
                    capabilities: [.read, .run, .memory]))
    app.saveBot(Bot(id: "coder", name: "Кодер prog", icon: "code-xml", hue: 235, role: "Пишет и чинит код Mac-приложений",
                    capabilities: [.read, .write, .run, .git, .memory], model: .opus,
                    look: BlobLook(shape: .hexagon, face: .curious, color: "#4a8df0")))
    app.saveBot(Bot(id: "writer", name: "Тексты для сайта", icon: "pen-line", hue: 200, role: "Тексты для kandeev.com",
                    capabilities: [.read, .web], look: BlobLook(shape: .droplet, face: .happy, color: "#e86fa5")))
    app.page = .bots
    try await Snap.save(RootView(app: app), "pet-bots")
    app.page = .botEditor("coder")
    try await Snap.save(RootView(app: app), "pet-bot-editor", size: CGSize(width: 1180, height: 1700))

    let marks = VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) { DotsSpinner(color: .orange); Text("Думает…").foregroundStyle(.white) }
        HStack(spacing: 10) { DotsSpinner(color: .orange, mood: .writing); Text("Читает ChatView.swift").foregroundStyle(.white) }
        HStack(spacing: 10) {
            DotsSpinner(color: .blue, bot: app.bot("coder"))
            Text("Кодер prog работает…").foregroundStyle(.white)
        }
    }
    .padding(30)
    .background(Palette.of(.lumen).background)
    try await Snap.save(marks.environment(\.petMark, app.prefs.pet), "pet-marks-blob", size: CGSize(width: 420, height: 200))
    var cat = app.prefs.pet
    cat.kind = .cat
    try await Snap.save(marks.environment(\.petMark, cat), "pet-marks-cat", size: CGSize(width: 420, height: 200))

    // питомец всегда в переписке: в конце, справа, когда ничего не происходит
    app.update { $0.pet.kind = .cat }
    let c = Conversation(title: "Про питомца", backend: .subscription, model: .sonnet, effort: .medium)
    try app.store.save(c)
    try app.store.save(ChatMessage(conversationID: c.id, role: .user, text: "Привет! Как дела?"))
    try app.store.save(ChatMessage(conversationID: c.id, role: .assistant, text: "Привет, Рома! Всё хорошо: собрал 1.5, питомец сидит рядом."))
    app.reloadConversations()
    app.openChat(c)
    try await Snap.save(RootView(app: app), "pet-in-chat")
}
