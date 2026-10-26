import AppKit
import Foundation
import LumenCore
import LumenProviders
import WebKit

/// 3D «как Blender, только в браузере сбоку» (Рома, 26.10, 1.7.1). Редактор — three.js editor (MIT, mrdoob/three.js),
/// взятый tools/model3d/build.sh с мостом `window.lumen3D` и русским интерфейсом. Агент строит модели кодом three.js
/// (каждое его действие — один шаг ⌘Z), снимает их с любой стороны и сохраняет; человек сам двигает, крутит,
/// красит, добавляет фигуры и свет, выделяет деталь и отправляет её в чат. Файлы — в папке моделей Lumen:
/// `<имя>.three.json` (проект, правится дальше) и `<имя>.glb` (Blender, игры, Quick Look).
extension BrowserModel {
    nonisolated static func model3DRoot() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["LUMEN_MODEL3D_DIR"], !env.isEmpty { candidates.append(URL(fileURLWithPath: env)) }
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Model3D")) }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../build/model3d").standardized)
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("editor/index.html").path) }
    }

    nonisolated static var model3DAvailable: Bool { model3DRoot() != nil }

    func modelServerReady() async throws -> DesignServer {
        if let modelServer { return modelServer }
        if let modelServerTask { return try await modelServerTask.value }
        guard let root = Self.model3DRoot() else {
            throw DesignError("3D-редактор не собран: запусти tools/model3d/build.sh и пересобери Lumen.")
        }
        let files = modelsDir
        let task = Task { @MainActor () throws -> DesignServer in
            let s = try DesignServer(root: root, files: files, port: DesignServer.preferredPort + 1, entry: "editor/", spa: false)
            try await s.start()
            return s
        }
        modelServerTask = task
        do {
            let s = try await task.value
            modelServer = s
            return s
        } catch {
            modelServerTask = nil
            throw error
        }
    }

    func isModel(_ tab: Tab) -> Bool {
        guard let s = modelServer, s.port != 0, let u = URL(string: tab.url.isEmpty ? (tab.pending ?? "") : tab.url) else { return false }
        return u.host == "127.0.0.1" && u.port == Int(s.port)
    }

    var modelTab: Tab? {
        if let t = tabs.first(where: { $0.id == agentTabID }), isModel(t) { return t }
        if isModel(active) { return active }
        return tabs.last { isModel($0) }
    }

    /// «Стул для кухни» → «Стул для кухни» (без слэшей и точек в начале)
    nonisolated static func modelName(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for ext in [".three.json", ".glb", ".json"] where n.lowercased().hasSuffix(ext) { n = String(n.dropLast(ext.count)) }
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "Модель" : String(n.prefix(80))
    }

    func modelProjectURL(_ name: String) -> URL { modelsDir.appendingPathComponent(name + ".three.json") }
    func modelGLBURL(_ name: String) -> URL { modelsDir.appendingPathComponent(name + ".glb") }

    /// Модели в папке — для пустой вкладки
    func modelFiles() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.lastPathComponent.hasSuffix(".three.json") }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.map { String($0.lastPathComponent.dropLast(".three.json".count)) }
    }

    // MARK: мост

    func waitModelReady(_ tab: Tab, seconds: Double = 25) async -> Bool {
        let limit = Date().addingTimeInterval(seconds)
        while Date() < limit {
            if let w = tab.web, !w.isLoading,
               (try? await w.callAsyncJavaScript("return !!(window.lumen3D && window.lumen3D.ready && window.editor)", contentWorld: .page)) as? Bool == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Выполнить в редакторе: тело async-функции с `m` = window.lumen3D; ответ — JSON строкой или ошибка
    func model3D(_ body: String, _ args: [String: Any] = [:], in tab: Tab) async -> (ok: Bool, text: String, json: Any?) {
        guard let w = tab.web else { return (false, "3D-модель не открыта.", nil) }
        let js = """
        const m = window.lumen3D;
        if (!m) return JSON.stringify({ok: false, error: '3D-редактор ещё не загрузился'});
        try { const r = await (async () => { \(body) })(); return JSON.stringify({ok: true, result: r === undefined ? null : r}); }
        catch (e) { return JSON.stringify({ok: false, error: String(e && e.stack ? (e.message + '\\n' + e.stack.split('\\n').slice(0, 3).join('\\n')) : e)}); }
        """
        do {
            let raw = try await w.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page) as? String ?? "{}"
            let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
            if obj?["ok"] as? Bool == false { return (false, obj?["error"] as? String ?? "Не вышло.", obj) }
            return (true, raw, obj?["result"])
        } catch {
            return (false, "Ошибка 3D-редактора: \(error.localizedDescription)", nil)
        }
    }

    // MARK: открыть, сохранить

    func openModel(name raw: String, in given: Tab?, select: Bool) async throws -> Tab {
        let server = try await modelServerReady()
        let name = Self.modelName(raw)
        if let t = tabs.first(where: { modelDocs[$0.id] == name }) {
            if select { self.select(t.id); wantsFull += 1 }
            return t
        }
        let tab: Tab
        if let given, given.file == nil, designDocs[given.id] == nil, modelDocs[given.id] == nil, (given.url.isEmpty || given.url == "about:blank") {
            tab = given
            tab.webView.load(URLRequest(url: server.editorURL))
        } else {
            tab = newTab(configuration: nil, select: select)
            tab.webView.load(URLRequest(url: server.editorURL))
        }
        if select { self.select(tab.id); wantsFull += 1 }
        BrowserStage.keepRendering(tab.webView)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        guard await waitModelReady(tab) else { throw DesignError("3D-редактор не загрузился за 25 секунд.") }
        let project = modelProjectURL(name)
        let r: (ok: Bool, text: String, json: Any?)
        if let json = try? String(contentsOf: project, encoding: .utf8) {
            r = await model3D("return await m.load(json, name)", ["json": json, "name": name], in: tab)
        } else {
            r = await model3D("return await m.fresh(name)", ["name": name], in: tab)
        }
        guard r.ok else { throw DesignError(r.text) }
        modelDocs[tab.id] = name
        tab.title = name
        modelMarks[tab.id] = -1
        startModelAutosave()
        onTabsChange?()
        return tab
    }

    /// Проект и GLB — в файлы, если что-то поменялось (или force)
    @discardableResult
    func saveModel(_ tab: Tab, name given: String? = nil, force: Bool = false) async -> Bool {
        guard let name = given ?? modelDocs[tab.id] else { return false }
        let mark = await model3D("return m.changes()", in: tab)
        let now = (mark.json as? Int) ?? -2
        if !force, now == modelMarks[tab.id] { return true }
        let proj = await model3D("return m.project()", in: tab)
        guard proj.ok, let json = proj.json as? String else { return false }
        do {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            try json.write(to: modelProjectURL(name), atomically: true, encoding: .utf8)
            let glb = await model3D("return await m.glb()", in: tab)
            if glb.ok, let b64 = glb.json as? String, let data = Data(base64Encoded: b64) { try data.write(to: modelGLBURL(name), options: .atomic) }
            modelMarks[tab.id] = now
            return true
        } catch {
            return false
        }
    }

    func startModelAutosave() {
        guard modelAutosave == nil else { return }
        modelAutosave = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self else { return }
                for t in self.tabs where self.modelDocs[t.id] != nil && t.isLoaded { await self.saveModel(t) }
            }
        }
    }

    // MARK: выделенное — в чат

    struct ModelPick {
        var model: String
        var line: String
        var image: NSImage?
    }

    func modelSelection() async -> ModelPick? {
        let tab = active
        guard isModel(tab), let name = modelDocs[tab.id] else { return nil }
        let r = await model3D("return m.selection()", in: tab)
        guard r.ok, let o = r.json as? [String: Any] else { return nil }
        let title = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (o["type"] as? String ?? "объект")
        let image = (o["image"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { NSImage(data: $0) }
        return ModelPick(model: name, line: "«\(title)» (\(o["type"] as? String ?? ""), uuid \(o["uuid"] as? String ?? ""))", image: image)
    }

    // MARK: инструменты агента (model3d_*)

    func performModel3D(tool: String, args: [String: Any], who: String) async -> BrowserTools.Reply {
        func s(_ k: String) -> String { (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch tool {
        case "model3d_open":
            let name = Self.modelName(s("name"))
            show(who, "Открывает 3D «\(name)»")
            do {
                let tab = try await openModel(name: name, in: workTab, select: true)
                adoptForAgent(tab, who: who)
                let tree = await model3D("return m.tree(2)", in: tab)
                var text = "3D-модель «\(name)» открыта в браузере сбоку (проект \(modelProjectURL(name).path), GLB \(modelGLBURL(name).path)). Человек видит редактор и может сам двигать, крутить, красить и добавлять; всё сохраняется само.\nСцена сейчас: \(Self.clip(tree.text, 3000))"
                if !model3DGuideSent.contains(who) {
                    model3DGuideSent.insert(who)
                    text += "\n\n" + Self.model3DGuide
                }
                return .init(text: text)
            } catch {
                return .init(text: error.localizedDescription, error: true)
            }
        case "model3d_run":
            guard let tab = modelTab else { return .init(text: "Сначала открой модель: model3d_open.", error: true) }
            show(who, "Строит 3D")
            let r = await model3D("return await m.run(code)", ["code": args["code"] as? String ?? ""], in: tab)
            if !r.ok { return .init(text: "Код не выполнился: \(r.text)\nИсправь и запусти снова — то, что успело добавиться до ошибки, не добавлено.", error: true) }
            let count = await model3D("let n = 0; editor.scene.traverse(o => { if (o.isMesh) n++ }); return n", in: tab)
            return .init(text: "Готово. Ответ кода: \(Self.clip(r.text, 6000))\nМешей в сцене: \(count.json ?? "?"). Посмотри, что вышло: model3d_shot.")
        case "model3d_tree":
            guard let tab = modelTab else { return .init(text: "Сначала открой модель: model3d_open.", error: true) }
            show(who, "Смотрит сцену")
            let depth = (args["depth"] as? Int) ?? Int(args["depth"] as? Double ?? 6)
            let r = await model3D("return m.tree(depth)", ["depth": depth], in: tab)
            return .init(text: Self.clip(r.text, 14_000), error: !r.ok)
        case "model3d_shot":
            guard let tab = modelTab else { return .init(text: "Сначала открой модель: model3d_open.", error: true) }
            show(who, "Смотрит на модель")
            let target = s("target")
            let view = s("view").isEmpty ? "iso" : s("view")
            if view == "all" {
                // четыре стороны одной картинкой: сразу видно и форму, и пропорции
                var shots: [NSImage] = []
                for v in ["iso", "front", "right", "top"] {
                    let r = await model3D("return m.shot({view: v, width: 640, height: 480, target: t || undefined})", ["v": v, "t": target], in: tab)
                    if let b = r.json as? String, let d = Data(base64Encoded: b), let img = NSImage(data: d) { shots.append(img) }
                }
                guard shots.count == 4, let grid = Self.grid(shots, labels: ["3/4", "спереди", "справа", "сверху"]), let (png, _) = Self.png(grid, maxWidth: 1280) else {
                    return .init(text: "Картинка не получилась.", error: true)
                }
                return .init(text: "Модель с четырёх сторон: 3/4, спереди, справа, сверху. Человек видит картинку в чате.", image: png)
            }
            let r = await model3D("return m.shot({view: v, width: 1280, height: 960, target: t || undefined})", ["v": view, "t": target], in: tab)
            guard r.ok, let b = r.json as? String, let data = Data(base64Encoded: b), let img = NSImage(data: data), let (png, _) = Self.png(img, maxWidth: 1280) else {
                return .init(text: "Картинка не получилась: \(r.text)", error: true)
            }
            return .init(text: "Модель (\(view)\(target.isEmpty ? "" : ", только «\(target)»")). Человек видит картинку в чате.", image: png)
        case "model3d_select":
            guard let tab = modelTab else { return .init(text: "Сначала открой модель: model3d_open.", error: true) }
            let r = await model3D("return m.select(t)", ["t": s("target")], in: tab)
            return .init(text: (r.json as? Bool) == true ? "Выделено и показано человеку: \(s("target"))." : "Нет такого объекта: \(s("target")).", error: (r.json as? Bool) != true)
        case "model3d_save":
            guard let tab = modelTab, let name = modelDocs[tab.id] else { return .init(text: "3D-модель не открыта.", error: true) }
            show(who, "Сохраняет модель")
            let ok = await saveModel(tab, force: true)
            return .init(text: ok ? "Сохранено: \(modelProjectURL(name).path) и \(modelGLBURL(name).path) (GLB открывается в Blender, играх и Quick Look; показать человеку — show_in_chat)." : "Сохранить не вышло.", error: !ok)
        default:
            return .init(text: "Нет такого действия: \(tool)", error: true)
        }
    }

    /// Четыре картинки сеткой 2×2 с подписями
    nonisolated static func grid(_ images: [NSImage], labels: [String]) -> NSImage? {
        guard images.count == 4 else { return nil }
        let w = images[0].size.width, h = images[0].size.height
        let out = NSImage(size: NSSize(width: w * 2, height: h * 2))
        out.lockFocus()
        for (i, img) in images.enumerated() {
            let x = CGFloat(i % 2) * w, y = CGFloat(1 - i / 2) * h
            img.draw(in: NSRect(x: x, y: y, width: w, height: h))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white]
            NSString(string: labels[i]).draw(at: NSPoint(x: x + 16, y: y + h - 38), withAttributes: attrs)
        }
        out.unlockFocus()
        return out
    }

    nonisolated static let model3DGuide = """
        Как строить в этом 3D-редакторе (three.js r186):
        - model3d_run выполняет твой JavaScript (тело async-функции). Внутри: THREE, scene, editor, add(object, parent?) — добавить \
        (все add и remove одного вызова — один шаг ⌘Z у человека), remove(имяИлиUuid), find(имяИлиUuid), select(имяИлиUuid), lights() — \
        поставить свет, если его нет, utils (BufferGeometryUtils: mergeGeometries, mergeVertices), RoundedBoxGeometry, ConvexGeometry. \
        Остальное — await import('three/addons/…'): geometries/ParametricGeometry.js, geometries/DecalGeometry.js, modifiers/SimplifyModifier.js, \
        modifiers/TessellateModifier.js, math/ConvexHull.js, curves/NURBSCurve.js. return — что вернуть себе (числа, имена; объекты превратятся в {name, uuid}).
        - Метры, ось Y вверх, пол на y = 0, модель стоит на полу. Каждой детали — понятное имя по-русски (mesh.name = 'Ножка'): человек видит \
        их в списке и выделяет. Детали одной вещи — в THREE.Group с её названием (add(group), потом group.add(деталь) до add или add(деталь, group)).
        - Материалы — MeshStandardMaterial (color, roughness, metalness); стекло — MeshPhysicalMaterial (transmission, roughness: 0). \
        Гладкость: у цилиндров и сфер 32–64 сегмента; скругления — RoundedBoxGeometry; сложные формы — LatheGeometry (тела вращения), \
        ExtrudeGeometry из THREE.Shape (с bevelEnabled), TubeGeometry по CatmullRomCurve3.
        - Строй по частям: один вызов — одна часть, после — model3d_shot (view: all — четыре стороны) и исправляй. Поменять существующее: \
        const o = find('Ножка'); o.scale.set(…); o.material.color.set('#…') — такие правки тоже видны сразу; удалить — remove('Ножка').
        - Человек правит сам и присылает выделенную деталь в чат (с uuid) — меняй именно её. model3d_save — файлы (.three.json и .glb).
        """
}
