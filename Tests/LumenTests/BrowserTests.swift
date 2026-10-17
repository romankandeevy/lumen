import AppKit
import Foundation
import Testing
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// Встроенный браузер: настоящий WebKit, настоящий сокет, тот же клиент, что у lumen-mcp.

@Test func everyBotGetsBrowser() {
    for b in [Bot(id: "talk", name: "Собеседник", capabilities: []), Bot(id: "x", name: "x", capabilities: [.read])] {
        let p = BrowserTools.names.map { "mcp__lumen__\($0)" }
        #expect(p.allSatisfy(BotPermissions(b).allowed.contains))
        #expect(b.rules(handoff: nil, userName: "", ty: true, skills: nil).contains("браузер"))
    }
    #expect(BrowserModel.address("kandeev.com")?.absoluteString == "https://kandeev.com")
    #expect(BrowserModel.address("localhost:3000")?.absoluteString == "http://localhost:3000")
    #expect(BrowserModel.address("/tmp/a.png")?.isFileURL == true)
    #expect(BrowserModel.address("погода в москве")?.host == "duckduckgo.com")
}

private let page = """
<!doctype html><html><head><meta charset="utf-8"><title>Вход</title></head><body>
<h1>Войти в кабинет</h1>
<p>Обычный текст абзаца.</p>
<form id="f"><input id="email" placeholder="Почта"><select id="plan"><option value="a">Базовый</option><option value="b">Про</option></select>
<label><input type="checkbox" id="agree"> Согласен</label>
<button type="button" id="go">Продолжить</button></form>
<div id="out"></div>
<a href="page2.html">Дальше</a>
<script>
// как у React: значение читается из события input, нажатие — через pointer/click
let typed = '';
document.getElementById('email').addEventListener('input', e => { typed = e.target.value; });
document.getElementById('go').addEventListener('click', () => {
  document.getElementById('out').textContent = 'Отправлено: ' + typed + ' / ' + document.getElementById('plan').value + ' / ' + document.getElementById('agree').checked;
});
document.getElementById('f').addEventListener('submit', e => { e.preventDefault(); document.getElementById('out').textContent = 'Форма по Enter: ' + typed; });
</script></body></html>
"""

@MainActor @Test func browserWorksEndToEndOverSocket() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-browser-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try page.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try "<!doctype html><meta charset=\"utf-8\"><title>Вторая</title><h1>Вторая страница</h1>".write(to: dir.appendingPathComponent("page2.html"), atomically: true, encoding: .utf8)

    let browser = BrowserModel()
    // окно, как у панели: без него WebKit не рисует и снимок пустой
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
    browser.webView.frame = window.contentView!.bounds
    window.contentView!.addSubview(browser.webView)

    let sock = "/tmp/lumen-test-\(UUID().uuidString.prefix(8)).sock"
    let server = BrowserServer(path: sock) { tool, args, who in
        nonisolated(unsafe) let a = args
        return await browser.handle(tool: tool, args: a, who: who)
    }
    try server.start()
    defer { server.stop() }

    func call(_ tool: String, _ args: [String: Any] = [:]) async -> BrowserTools.Reply {
        nonisolated(unsafe) let a = args
        return await Task.detached { BrowserClient.call(socket: sock, tool: tool, args: a, who: "@tester") }.value
    }

    let opened = await call("browser_navigate", ["url": dir.appendingPathComponent("index.html").path])
    #expect(!opened.error, "\(opened.text)")
    #expect(opened.text.contains("Страница: Вход"))
    #expect(opened.text.contains("textbox \"Почта\""))
    #expect(browser.activity?.hasPrefix("@tester") == true)
    #expect(browser.wantsOpen > 0)

    let all = await call("browser_read_page", ["filter": "all"])
    #expect(all.text.contains("heading \"Войти в кабинет\""))
    #expect(all.text.contains("Обычный текст абзаца"))

    func ref(_ text: String, _ label: String) -> String? {
        text.split(separator: "\n").first { $0.contains(label) }.flatMap { line in
            line.range(of: #"\[e\d+\]"#, options: .regularExpression).map { String(line[$0].dropFirst().dropLast()) }
        }
    }
    let email = try #require(ref(all.text, "\"Почта\""))
    let plan = try #require(ref(all.text, "combobox"))
    let agree = try #require(ref(all.text, "checkbox"))
    let go = try #require(ref(all.text, "\"Продолжить\""))

    #expect(!(await call("browser_type", ["ref": email, "text": "roma@example.com"])).error)
    let picked = await call("browser_select", ["ref": plan, "value": "Про"])
    #expect(picked.text.contains("Выбрано «Про»"))
    #expect((await call("browser_select", ["ref": agree, "value": "true"])).text.contains("Отмечено"))
    let clicked = await call("browser_click", ["ref": go])
    #expect(clicked.text.contains("Нажато"))
    let text = await call("browser_text")
    #expect(text.text.contains("Отправлено: roma@example.com / b / true"))

    // Enter в поле отправляет форму
    _ = await call("browser_type", ["ref": email, "text": "второй", "submit": true])
    #expect((await call("browser_text")).text.contains("Форма по Enter: второй"))

    let found = await call("browser_find", ["query": "дальше"])
    let next = try #require(ref(found.text, "Дальше"))
    let moved = await call("browser_click", ["ref": next])
    #expect(moved.text.contains("Страница: Вторая"), "\(moved.text)")
    #expect((await call("browser_click", ["ref": go])).error) // метки старой страницы больше нет

    let shot = await call("browser_screenshot")
    #expect(!shot.error, "\(shot.text)")
    #expect((shot.image?.count ?? 0) > 1000)

    let js = await call("browser_js", ["code": "document.title + ' ' + (1 + 1)"])
    #expect(js.text == "Вторая 2", "\(js.text)")

    // показать макет-картинку
    let png = dir.appendingPathComponent("mockup.png")
    try shot.image?.write(to: png)
    let shown = await call("browser_show", ["path": png.path])
    #expect(shown.text.contains("Открыто в браузере сбоку"))
    #expect(browser.url.hasSuffix("mockup.png"))
    #expect((await call("browser_show", ["path": "/нет/такого.png"])).error)
}
