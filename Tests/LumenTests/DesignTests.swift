import AppKit
import Foundation
import Testing
import WebKit
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// Макеты «как в Фигме»: OpenPencil в браузере сбоку, агент рисует через мост, человек выделяет и шлёт в чат.

@Test func designServerServesEditorAndKeepsFilesInsideTheFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-ds-\(UUID().uuidString.prefix(6))")
    let files = root.appendingPathComponent("designs")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    try "<!doctype html><title>Редактор</title>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try Data([0, 97, 115, 109]).write(to: root.appendingPathComponent("assets/a.wasm"))
    defer { try? FileManager.default.removeItem(at: root) }
    let server = try DesignServer(root: root, files: files, token: "t0k")
    try await server.start()
    defer { server.stop() }
    let base = "http://127.0.0.1:\(server.port)"

    let (page, r1) = try await URLSession.shared.data(from: URL(string: base + "/rooms/whatever")!)
    #expect((r1 as? HTTPURLResponse)?.statusCode == 200 && String(decoding: page, as: UTF8.self).contains("Редактор"), "неизвестный путь — страница редактора")
    let (_, r2) = try await URLSession.shared.data(from: URL(string: base + "/assets/a.wasm")!)
    #expect((r2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "application/wasm")
    #expect(((try await URLSession.shared.data(from: URL(string: base + "/sw.js")!)).1 as? HTTPURLResponse)?.statusCode == 404)

    // файлы: только с ключом и только в папке макетов
    var put = URLRequest(url: URL(string: base + "/files/%D0%9C%D0%B0%D0%BA%D0%B5%D1%82.fig")!)
    put.httpMethod = "PUT"
    put.httpBody = Data("fig".utf8)
    #expect(((try await URLSession.shared.data(for: put)).1 as? HTTPURLResponse)?.statusCode == 401)
    put.setValue("Bearer t0k", forHTTPHeaderField: "Authorization")
    #expect(((try await URLSession.shared.data(for: put)).1 as? HTTPURLResponse)?.statusCode == 200)
    #expect(FileManager.default.contents(atPath: files.appendingPathComponent("Макет.fig").path) == Data("fig".utf8))
    var escape = URLRequest(url: URL(string: base + "/files/..%2F..%2Fetc%2Fpasswd")!)
    escape.setValue("Bearer t0k", forHTTPHeaderField: "Authorization")
    let esc = (try await URLSession.shared.data(for: escape)).1 as? HTTPURLResponse
    #expect(esc?.statusCode == 403 || esc?.statusCode == 404)
    #expect(server.resolve("/etc/passwd") == nil)
    #expect(server.resolve("../x.fig") == nil)
    #expect(server.resolve("Лендинг.fig")?.path.hasSuffix("designs/Лендинг.fig") == true)
    #expect(BrowserModel.designFileName("../../Лендинг/кофейни.fig") == "-Лендинг-кофейни.fig" || BrowserModel.designFileName("../../Лендинг/кофейни.fig").hasSuffix("Лендинг-кофейни.fig"))
}

@MainActor @Test(.enabled(if: BrowserModel.designAvailable)) func agentBuildsAScreenAndHumanSendsItToChat() async throws {
    let designs = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-designs-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: designs) }
    let browser = BrowserModel()
    browser.designsDir = designs
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
    browser.webView.frame = window.contentView!.bounds
    window.contentView!.addSubview(browser.webView)
    // холст редактора рисует WebGL только в показанном окне (как панель у человека); ставим его за край экрана
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    func call(_ tool: String, _ args: [String: Any] = [:]) async -> BrowserTools.Reply {
        await browser.handle(tool: tool, args: args, who: "@designer")
    }

    let opened = await call("design_open", ["name": "Кофейня"])
    #expect(!opened.error, "\(opened.text.prefix(400))")
    #expect(opened.text.contains("render"), "в первый раз приходит список инструментов и справочник")
    let tab = try #require(browser.designTab)
    #expect(browser.wantsFull > 0, "макет разворачивает браузер на всё окно")
    // внутри Lumen у редактора нет своего приветствия «настройте ИИ» и плашки про файлы
    let chrome = try await tab.webView.callAsyncJavaScript("return [document.querySelectorAll('[role=dialog]').length, document.body.innerText.includes('File System') || document.body.innerText.includes('локальных файлов')]", contentWorld: .page) as? [Any]
    #expect((chrome?.first as? Int) == 0, "\(String(describing: chrome))")
    #expect((chrome?.last as? Bool) == false)
    #expect(browser.designDocs[tab.id] == "Кофейня.fig")
    // в редакторе — сам макет под своим названием и его «Домой»; лишних пустых документов нет
    let docs = await browser.designCall("list_documents", [:], in: tab)
    #expect(docs.text.contains("\"name\":\"Кофейня\""), "\(docs.text.prefix(500))")
    #expect(docs.text.components(separatedBy: "Untitled").count <= 2, "\(docs.text.prefix(500))")

    let jsx = """
    <Frame name="Главная" w={390} h={844} bg="#FFF8F0" flex="col" gap={16} p={24}>
      <Text name="Заголовок" size={32} weight="bold" color="#2B1A10">Кофе с собой</Text>
      <Frame name="Кнопка" bg="#6B3E26" rounded={12} px={20} py={14}><Text color="#FFFFFF" size={17}>Заказать</Text></Frame>
    </Frame>
    """
    let drawn = await call("design", ["tool": "render", "args": ["jsx": jsx]])
    #expect(!drawn.error, "\(drawn.text.prefix(600))")
    let tree = await call("design", ["tool": "find_nodes", "args": ["name": "Кнопка"]])
    #expect(tree.text.contains("Кнопка"), "\(tree.text.prefix(400))")

    let shot = await call("design_shot")
    #expect(!shot.error, "\(shot.text)")
    #expect((shot.image?.count ?? 0) > 2000)

    // сохраняется в файл макета
    #expect(!(await call("design_save")).error)
    #expect(FileManager.default.fileExists(atPath: designs.appendingPathComponent("Кофейня.fig").path))

    // человек выделил кнопку — она уходит в чат с картинкой и id
    let found = try JSONSerialization.jsonObject(with: Data(tree.text.utf8)) as? [String: Any]
    func firstID(_ any: Any?) -> String? {
        if let d = any as? [String: Any] {
            if d["name"] as? String == "Кнопка", let id = d["id"] as? String { return id }
            for v in d.values { if let x = firstID(v) { return x } }
        } else if let a = any as? [Any] { for v in a { if let x = firstID(v) { return x } } }
        return nil
    }
    let id = try #require(firstID(found), "\(tree.text.prefix(500))")
    // человек сам выделяет слой (без агента) — как кликом на холсте
    _ = try await tab.webView.callAsyncJavaScript("window.openPencil.getStore().select([id])", arguments: ["id": id], in: nil, contentWorld: .page)
    browser.select(tab.id)
    let pick = try #require(await browser.designSelection(), "выделение читается")
    #expect(pick.file == "Кофейня")
    #expect(pick.lines.first?.contains("Кнопка") == true, "\(pick.lines)")
    #expect(pick.image != nil)

    // тот же макет второй раз открывается в той же вкладке
    let again = await call("design_open", ["name": "Кофейня"])
    #expect(!again.error)
    #expect(browser.tabs.filter { browser.designDocs[$0.id] != nil }.count == 1)
    #expect(!again.text.contains("Как рисовать"), "справочник — один раз")

    // правка и сразу закрыли вкладку — макет всё равно сохраняется
    let fig = designs.appendingPathComponent("Кофейня.fig")
    let before = try Data(contentsOf: fig)
    _ = await call("design", ["tool": "render", "args": ["jsx": "<Frame name=\"Второй экран\" w={390} h={844} bg=\"#222\"><Text color=\"#FFF\" size={24}>Меню</Text></Frame>", "x": 500]])
    browser.close(tab.id)
    for _ in 0..<50 { if (try? Data(contentsOf: fig)) != before { break }; try await Task.sleep(for: .milliseconds(100)) }
    #expect(try Data(contentsOf: fig) != before, "последняя правка не потерялась при закрытии")
    #expect(tab.web?.superview == nil, "закрытая вкладка не живёт за кулисами")
}
