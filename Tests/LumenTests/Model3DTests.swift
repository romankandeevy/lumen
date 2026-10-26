import AppKit
import Foundation
import Testing
import WebKit
@testable import LumenCore
@testable import LumenProviders
@testable import LumenUI

// 3D в браузере сбоку (1.7.1): редактор three.js, агент строит кодом, человек правит и шлёт деталь в чат, файлы .three.json и .glb.

@MainActor @Test(.enabled(if: BrowserModel.model3DAvailable)) func agentBuildsAChairHumanPicksAPartAndItIsSaved() async throws {
    let models = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-models-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: models) }
    let browser = BrowserModel()
    browser.modelsDir = models
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
    browser.webView.frame = window.contentView!.bounds
    window.contentView!.addSubview(browser.webView)
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    func call(_ tool: String, _ args: [String: Any] = [:]) async -> BrowserTools.Reply {
        await browser.handle(tool: tool, args: args, who: "@designer")
    }

    let opened = await call("model3d_open", ["name": "Стул"])
    #expect(!opened.error, "\(opened.text.prefix(500))")
    #expect(opened.text.contains("model3d_run"), "справочник в первый раз")
    let tab = try #require(browser.modelTab)
    #expect(browser.modelDocs[tab.id] == "Стул")
    #expect(browser.wantsFull > 0)
    // интерфейс по-русски
    let ui = try await tab.webView.callAsyncJavaScript("return document.body.innerText", contentWorld: .page) as? String ?? ""
    #expect(ui.contains("Сцена") || ui.contains("Файл"), "\(ui.prefix(300))")

    let code = """
    const chair = new THREE.Group(); chair.name = 'Стул';
    const wood = new THREE.MeshStandardMaterial({ color: '#8B5A2B', roughness: 0.7 });
    const seat = new THREE.Mesh(new RoundedBoxGeometry(0.45, 0.05, 0.45, 4, 0.01), wood); seat.name = 'Сиденье'; seat.position.y = 0.45; chair.add(seat);
    for (const [x, z] of [[-0.2, -0.2], [0.2, -0.2], [-0.2, 0.2], [0.2, 0.2]]) {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.45, 24), wood); leg.name = 'Ножка'; leg.position.set(x, 0.225, z); chair.add(leg);
    }
    const back = new THREE.Mesh(new RoundedBoxGeometry(0.45, 0.45, 0.04, 4, 0.01), wood); back.name = 'Спинка'; back.position.set(0, 0.7, -0.205); chair.add(back);
    add(chair);
    return chair.children.length;
    """
    let built = await call("model3d_run", ["code": code])
    #expect(!built.error, "\(built.text)")
    #expect(built.text.contains("6"), "\(built.text)")

    // ошибка в коде — понятный ответ, сцена не ломается
    let broken = await call("model3d_run", ["code": "add(new THREE.Mesh(nope))"])
    #expect(broken.error)
    #expect(broken.text.contains("nope"))

    // правая панель сворачивается (клавиша N, «Вид → Боковая панель», ручка) — вид на всю ширину
    let folded = try await tab.webView.callAsyncJavaScript("editor.signals.sidebarToggled.dispatch(); return [getComputedStyle(document.getElementById('sidebar')).display, document.getElementById('viewport').style.right]", contentWorld: .page) as? [String]
    #expect(folded == ["none", "0px"], "\(String(describing: folded))")
    let unfolded = try await tab.webView.callAsyncJavaScript("editor.signals.sidebarToggled.dispatch(); return getComputedStyle(document.getElementById('sidebar')).display", contentWorld: .page) as? String
    #expect(unfolded != "none")

    // камера на трекпаде плавная: щипок — чуть ближе, два пальца — вращение без скачка расстояния, колесо мыши — заметный, но не 10 % за событие шаг
    let cam = try await tab.webView.callAsyncJavaScript("""
    const v = document.querySelector('#viewport canvas') || document.getElementById('viewport'), c = editor.viewportCamera, d = () => c.position.length();
    const frame = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    const fire = (o) => v.dispatchEvent(new WheelEvent('wheel', Object.assign({bubbles: true, cancelable: true, deltaMode: 0}, o)));
    const d0 = d(); fire({deltaY: 4, ctrlKey: true}); await frame(); const pinch = d() / d0;
    const p0 = c.position.clone(), d1 = d(); fire({deltaX: 6, deltaY: 1}); fire({deltaX: 6, deltaY: 2}); await frame(); const orbitMoved = c.position.distanceTo(p0), orbitDist = d() / d1;
    const d2 = d(); fire({deltaY: 100}); await frame(); const wheel = d() / d2;
    return [pinch, orbitMoved, orbitDist, wheel];
    """, contentWorld: .page) as? [Double] ?? []
    #expect(cam.count == 4, "\(cam)")
    if cam.count == 4 {
        #expect(cam[0] > 1 && cam[0] < 1.06, "щипок на 4 px — чуть дальше, без рывка: \(cam)")
        #expect(cam[1] > 0 && abs(cam[2] - 1) < 0.001, "два пальца вращают, расстояние то же: \(cam)")
        #expect(cam[3] > 1.1 && cam[3] < 1.4, "колесо мыши — плавный шаг: \(cam[3])")
    }

    let tree = await call("model3d_tree")
    #expect(tree.text.contains("Сиденье") && tree.text.contains("Спинка"), "\(tree.text.prefix(500))")

    let shot = await call("model3d_shot", ["view": "all"])
    #expect(!shot.error, "\(shot.text)")
    #expect((shot.image?.count ?? 0) > 5000)
    let part = await call("model3d_shot", ["target": "Спинка", "view": "front"])
    #expect(!part.error && (part.image?.count ?? 0) > 2000)

    // человек выделяет спинку — она уходит в чат картинкой с uuid
    #expect(!(await call("model3d_select", ["target": "Спинка"])).error)
    browser.select(tab.id)
    let pick = try #require(await browser.modelSelection())
    #expect(pick.model == "Стул")
    #expect(pick.line.contains("Спинка"))
    #expect(pick.image != nil)

    // одно действие агента — один шаг ⌘Z у человека
    let undos = try await tab.webView.callAsyncJavaScript("return editor.history.undos.length", contentWorld: .page) as? Int
    #expect((undos ?? 0) >= 2, "свет и стул — отдельные шаги")

    // файлы: проект и GLB
    #expect(!(await call("model3d_save")).error)
    let project = models.appendingPathComponent("Стул.three.json"), glb = models.appendingPathComponent("Стул.glb")
    #expect(FileManager.default.fileExists(atPath: project.path))
    let glbData = try Data(contentsOf: glb)
    #expect(glbData.prefix(4) == Data("glTF".utf8), "настоящий GLB")

    // правка и сразу закрыли — сохраняется; открыли снова — модель на месте
    _ = await call("model3d_run", ["code": "find('Сиденье').material.color.set('#C0392B'); return true"])
    let before = try Data(contentsOf: project)
    browser.close(tab.id)
    for _ in 0..<60 { if (try? Data(contentsOf: project)) != before { break }; try await Task.sleep(for: .milliseconds(100)) }
    #expect(try Data(contentsOf: project) != before, "правка перед закрытием сохранилась")
    let again = await call("model3d_open", ["name": "Стул"])
    #expect(!again.error)
    #expect(!again.text.contains("Как строить"), "справочник — один раз")
    let reopened = await call("model3d_tree")
    #expect(reopened.text.contains("Спинка") && reopened.text.contains("c0392b"), "\(reopened.text.prefix(600))")

    // после перезапуска Lumen вкладка с моделью возвращается и открывает модель, когда на неё переходят
    let saved = browser.savedState()
    #expect(saved.tabs.contains { $0.kind == "model3d" && $0.title == "Стул" }, "\(saved)")
    let next = BrowserModel()
    next.modelsDir = models
    let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
    w2.setFrameOrigin(NSPoint(x: -4000, y: -4000)); w2.orderFrontRegardless()
    defer { w2.orderOut(nil) }
    next.restore(BrowserModel.SavedState(tabs: [BrowserModel.SavedTab(url: "https://example.com/", title: "Пример", file: nil, kind: nil)] + saved.tabs.filter { $0.kind == "model3d" }, active: 0))
    let restored = try #require(next.tabs.first { $0.title == "Стул" })
    #expect(next.pendingEditors[restored.id]?.kind == "model3d")
    next.select(restored.id)
    restored.webView.frame = w2.contentView!.bounds
    w2.contentView!.addSubview(restored.webView)
    for _ in 0..<100 where next.modelDocs[restored.id] == nil { try await Task.sleep(for: .milliseconds(100)) }
    #expect(next.modelDocs[restored.id] == "Стул")
    let back = await next.handle(tool: "model3d_tree", args: [:], who: "@designer")
    #expect(back.text.contains("Спинка"), "\(back.text.prefix(300))")
}
