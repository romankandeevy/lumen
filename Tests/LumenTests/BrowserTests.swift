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
    let server = BrowserServer(path: sock) { tool, args, who, _ in
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

private let lab = """
<!doctype html><html><head><meta charset="utf-8"><title>Лаборатория</title>
<style>#hov:hover{color:red} #drop{width:200px;height:80px;border:1px solid}</style></head><body>
<button id="b">Кнопка</button>
<div id="hov">Наведи</div>
<input id="t" value="старое">
<input type="file" id="f">
<div id="drop">Сюда</div>
<input type="range" id="r" min="0" max="100" value="0" style="width:300px">
<a href="#" id="pop">Окно</a>
<button id="ask">Спросить</button>
<div id="log"></div>
<script>
const log = s => { document.getElementById('log').textContent += s + ';'; };
const b = document.getElementById('b');
b.addEventListener('click', e => log('click:' + e.isTrusted + ':' + (e.metaKey ? 'cmd' : '')));
b.addEventListener('dblclick', () => log('dbl'));
b.addEventListener('contextmenu', e => { e.preventDefault(); log('ctx'); });
document.getElementById('hov').addEventListener('mouseover', () => log('hover'));
document.getElementById('f').addEventListener('change', e => log('file:' + e.target.files[0].name + ':' + e.target.files[0].size));
document.getElementById('pop').addEventListener('click', e => { e.preventDefault(); window.open('about:blank#second'); });
document.getElementById('ask').addEventListener('click', () => log('confirm:' + confirm('Удалить всё?')));
console.warn('предупреждение страницы');
console.error('ошибка страницы');
fetch('/data.json').then(r => r.json()).then(j => log('json:' + j.ok));
</script></body></html>
"""

@MainActor @Test func browserDoesWhatClaudeBrowserDoes() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-lab-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try lab.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try #"{"ok": true}"#.write(to: dir.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
    try "привет".write(to: dir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
    // настоящий http — для fetch и журнала сети
    let port = Int.random(in: 20000...40000)
    let http = Process()
    http.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    http.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", dir.path]
    http.standardOutput = FileHandle.nullDevice
    http.standardError = FileHandle.nullDevice
    try http.run()
    defer { http.terminate() }
    try await Task.sleep(for: .milliseconds(700))

    let browser = BrowserModel()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
    func mount() {
        browser.webView.frame = window.contentView!.bounds
        if browser.webView.superview !== window.contentView { window.contentView!.addSubview(browser.webView) }
    }
    mount()
    func call(_ tool: String, _ args: [String: Any] = [:]) async -> BrowserTools.Reply {
        await browser.handle(tool: tool, args: args, who: "@tester")
    }
    func ref(_ text: String, _ label: String) -> String? {
        text.split(separator: "\n").first { $0.contains(label) }.flatMap { line in
            line.range(of: #"\[e\d+\]"#, options: .regularExpression).map { String(line[$0].dropFirst().dropLast()) }
        }
    }
    func logText() async -> String { (await call("browser_js", ["code": "document.getElementById('log').textContent"])).text }

    let page = await call("browser_navigate", ["url": "http://127.0.0.1:\(port)/index.html"])
    #expect(page.text.contains("Лаборатория"), "\(page.text)")
    let all = await call("browser_read_page", ["filter": "all"])
    let b = try #require(ref(all.text, "\"Кнопка\""))

    // настоящий клик: страница видит его как действие человека
    _ = await call("browser_click", ["ref": b, "modifiers": "cmd"])
    _ = await call("browser_click", ["ref": b, "clicks": 2])
    _ = await call("browser_click", ["ref": b, "button": "right"])
    let afterClicks = await logText()
    #expect(afterClicks.contains("click:true:cmd"), "\(afterClicks)")
    #expect(afterClicks.contains("dbl"))
    #expect(afterClicks.contains("ctx"))

    let hov = try #require(ref((await call("browser_find", ["query": "Наведи"])).text, "Наведи"))
    _ = await call("browser_hover", ["ref": hov])
    #expect(await logText().contains("hover"))

    // сочетание и последовательность клавиш
    let t = try #require(ref(all.text, "textbox"))
    _ = await call("browser_click", ["ref": t])
    _ = await call("browser_key", ["key": "cmd+a"])
    _ = await call("browser_key", ["key": "Backspace"])
    _ = await call("browser_type", ["text": "новое", "clear": false])
    _ = await call("browser_key", ["key": "Backspace", "repeat": 2])
    #expect((await call("browser_js", ["code": "document.getElementById('t').value"])).text == "нов")

    // ползунок перетаскиванием
    let range = try #require(ref(all.text, "slider"))
    let r = await call("browser_drag", ["from_ref": range, "to_x": 400, "to_y": 1])
    #expect(!r.error, "\(r.text)")

    // загрузка файла
    let f = try #require(ref(all.text, "browser_upload"))
    let up = await call("browser_upload", ["ref": f, "paths": [dir.appendingPathComponent("note.txt").path]])
    #expect(up.text.contains("Загружено"), "\(up.text)")
    #expect(await logText().contains("file:note.txt:12"))
    #expect((await call("browser_upload", ["ref": f, "paths": ["/tmp/.env"]])).error)

    // консоль и сеть
    let console = await call("browser_console")
    #expect(console.text.contains("[warn] предупреждение страницы") && console.text.contains("[error] ошибка страницы"), "\(console.text)")
    #expect((await call("browser_console")).text.contains("Новых сообщений в консоли нет"))
    let net = await call("browser_network")
    #expect(net.text.contains("GET 200") && net.text.contains("data.json"), "\(net.text)")

    // окно страницы не вешает агента: confirm — «Отмена», агент узнаёт об этом
    let ask = try #require(ref(all.text, "\"Спросить\""))
    let asked = await call("browser_click", ["ref": ask])
    #expect(asked.text.contains("Удалить всё?") && asked.text.contains("Отмена"), "\(asked.text)")
    #expect(await logText().contains("confirm:false"))

    // страница открыла окно — новая вкладка; переключение и закрытие
    let pop = try #require(ref(all.text, "\"Окно\""))
    let popped = await call("browser_click", ["ref": pop])
    #expect(popped.text.contains("новую вкладку"), "\(popped.text)")
    #expect(browser.tabs.count == 2)
    let first = browser.tabs[0].id
    _ = await call("browser_tabs", ["action": "switch", "tab": first])
    #expect(browser.activeID == first)
    let closed = await call("browser_tabs", ["action": "close", "tab": browser.tabs[1].id])
    #expect(browser.tabs.count == 1 && !closed.text.contains("second"))
    mount()

    // пачка действий и увеличенный снимок
    let batch = await call("browser_batch", ["actions": [["tool": "scroll", "args": ["direction": "down"]], ["tool": "find", "args": ["query": "Кнопка"]]]])
    #expect(batch.text.contains("1. browser_scroll") && batch.text.contains("2. browser_find"), "\(batch.text)")
    let failed = await call("browser_batch", ["actions": [["tool": "click", "args": ["ref": "e99999"]], ["tool": "find", "args": ["query": "x"]]]])
    #expect(failed.error && failed.text.contains("Остальное не выполнено"))
    let zoom = await call("browser_zoom", ["region": [0, 0, 200, 100]])
    #expect((zoom.image?.count ?? 0) > 500, "\(zoom.text)")

    // вид телефона и тёмная тема
    let phone = await call("browser_resize", ["preset": "mobile", "color_scheme": "dark"])
    #expect(phone.text.contains("390×844") && phone.text.contains("тёмная"))
    #expect((await call("browser_js", ["code": "navigator.userAgent"])).text.contains("iPhone"))
    #expect((await call("browser_js", ["code": "matchMedia('(prefers-color-scheme: dark)').matches"])).text == "true")
}

@Test func localServersAreFoundAndSystemOnesSkipped() {
    let out = "p955\ncrapportd\nf11\nn*:51089\np1213\ncControlCenter\nf11\nn*:7000\np34568\ncPython\nf5\nn*:5181\np4000\ncnode\nf3\nn127.0.0.1:5173\nf4\nn[::1]:5173\np5000\ncnode\nn*:80\n"
    let list = LocalServers.parse(out)
    #expect(list.map(\.port) == [5173, 5181]) // AirPlay, Handoff и порты ниже 1024 — нет; 5173 один раз
    #expect(list.first?.process == "node")
    #expect(AgentStep.from(tool: "mcp__lumen__browser_servers", input: [:]).text == "Смотрит запущенные localhost")
}
