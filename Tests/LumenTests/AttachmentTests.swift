import AppKit
import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenStorage
@testable import LumenUI

// Вложения: что уходит модели, как принимаются картинки и файлы, какие режимы видны.

/// Картинка нужного размера с цветным кругом
func makeImage(_ w: Int, _ h: Int, color: NSColor, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    color.setFill(); NSBezierPath(ovalIn: NSRect(x: w / 4, y: h / 4, width: w / 2, height: h / 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor @Test func attachmentsAreImportedAndSentAsBlocks() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-att-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    let src = home.appendingPathComponent("src")
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)

    // маленькая PNG — как есть; большая — JPEG с длинной стороной 1568
    try makeImage(400, 300, color: .red, to: src.appendingPathComponent("small.png"))
    try makeImage(4000, 3000, color: .blue, to: src.appendingPathComponent("big.png"))
    let small = try #require(app.importAttachment(src.appendingPathComponent("small.png")))
    #expect(small.kind == .image && small.mime == "image/png" && small.width == 400)
    let big = try #require(app.importAttachment(src.appendingPathComponent("big.png")))
    #expect(big.mime == "image/jpeg" && max(big.width ?? 0, big.height ?? 0) == 1568 && big.name == "big.jpg")
    #expect(big.path.hasPrefix(app.paths.attachments.path))

    try "let x = 1\n".write(to: src.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
    let code = try #require(app.importAttachment(src.appendingPathComponent("a.swift")))
    #expect(code.kind == .text)
    try Data([0, 1, 2, 3]).write(to: src.appendingPathComponent("blob.bin"))
    let blob = try #require(app.importAttachment(src.appendingPathComponent("blob.bin")))
    #expect(blob.kind == .file)

    let blocks = Attachment.userContent(text: "Что на картинке?", attachments: [small, code, blob], agent: true)
    #expect(blocks.map { $0["type"] as? String } == ["image", "text", "text", "text"])
    #expect((blocks[1]["text"] as? String)?.contains("let x = 1") == true)
    #expect((blocks.last?["text"] as? String)?.contains("Вложения сохранены") == true)

    // в истории API — те же блоки
    var m = ChatMessage(conversationID: "c", role: .user, text: "Что тут?")
    m.attachments = [small]
    let hist = AnthropicChatRequest.history([m])
    #expect((hist.first?["content"] as? JSONBox) != nil)

    // сообщение с вложением хранится и читается обратно
    let c = Conversation(title: "t", backend: .subscription, model: .sonnet, effort: .low)
    try app.store.save(c)
    var u = ChatMessage(conversationID: c.id, role: .user, text: "")
    u.attachments = [small, blob]
    _ = try app.store.save(u)
    #expect(try app.store.messages(in: c.id).first?.attachments == [small, blob])
}

@Test func visibleModesNeverEmpty() {
    var p = Preferences()
    #expect(p.visibleModes == AgentMode.allCases)
    p.hiddenModes = [.bypassPermissions, .plan]
    #expect(p.visibleModes == [.manual, .acceptEdits, .auto])
    p.hiddenModes = AgentMode.allCases
    #expect(p.visibleModes == [.auto])
}

/// Живая: Claude по подписке видит картинку
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LUMEN_LIVE"] == "1"))
func liveClaudeSeesImage() async throws {
    pointToMCP()
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-liveimg-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    await app.refreshClaude()
    app.finishOnboarding(name: "Тест", address: .ty, backend: .subscription, theme: .lumen)
    let src = home.appendingPathComponent("circle.png")
    try makeImage(600, 600, color: .systemGreen, to: src)
    let a = try #require(app.importAttachment(src))
    app.newChat()
    app.chat.set(model: .haiku, effort: .low)
    app.chat.send("Какого цвета круг на картинке? Ответь одним словом.", attachments: [a])
    while app.chat.busy { try await Task.sleep(for: .milliseconds(200)) }
    let reply = try #require(app.chat.messages.last)
    #expect(reply.error == nil, "\(reply.error ?? "")")
    #expect(reply.text.lowercased().contains("зел"), "ответ: \(reply.text)")
    #expect(app.chat.messages.first?.attachments.count == 1)
}
