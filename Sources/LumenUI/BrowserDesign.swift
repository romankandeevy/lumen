import AppKit
import Foundation
import LumenCore
import LumenProviders
import WebKit

/// Макеты «как в Фигме» прямо в браузере сбоку (Рома, 26.10). Редактор — OpenPencil (MIT, open-pencil/open-pencil),
/// собранный tools/design/build.sh с мостом `window.lumenDesign`: те же 100+ команд, что у его MCP-сервера.
/// Агент собирает экраны (render JSX, фреймы, текст, автолейаут), человек сам двигает, правит тексты и цвета,
/// выделяет слой и одной кнопкой отправляет его в чат с просьбой, что поменять. Файлы .fig — в папке макетов Lumen.
extension BrowserModel {
    /// Где лежит собранный редактор: в Lumen.app, в LUMEN_DESIGN_DIR или в build/design рядом с исходниками
    nonisolated static func designRoot() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["LUMEN_DESIGN_DIR"], !env.isEmpty { candidates.append(URL(fileURLWithPath: env)) }
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Design")) }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../build/design").standardized)
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }

    nonisolated static var designAvailable: Bool { designRoot() != nil }

    /// Сервер редактора поднимается при первом макете
    func designServerReady() async throws -> DesignServer {
        if let designServer { return designServer }
        // человек и агент могут попросить макет одновременно — сервер всё равно один
        if let designServerTask { return try await designServerTask.value }
        guard let root = Self.designRoot() else {
            throw DesignError("Редактор макетов не собран: запусти tools/design/build.sh и пересобери Lumen.")
        }
        let files = designsDir
        let task = Task { @MainActor () throws -> DesignServer in
            let s = try DesignServer(root: root, files: files)
            try await s.start()
            return s
        }
        designServerTask = task
        do {
            let s = try await task.value
            designServer = s
            return s
        } catch {
            designServerTask = nil
            throw error
        }
    }

    struct DesignError: Error, LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    func isDesign(_ tab: Tab) -> Bool {
        guard let s = designServer, s.port != 0, let u = URL(string: tab.url.isEmpty ? (tab.pending ?? "") : tab.url) else { return false }
        return u.host == "127.0.0.1" && u.port == Int(s.port)
    }

    /// Вкладка с макетом, в которой работать агенту: своя, открытая или любая с редактором
    var designTab: Tab? {
        if let t = tabs.first(where: { $0.id == agentTabID }), isDesign(t) { return t }
        if isDesign(active) { return active }
        return tabs.last { isDesign($0) }
    }

    /// «Лендинг для кофейни» → «Лендинг для кофейни.fig» (без слэшей и точек в начале)
    nonisolated static func designFileName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.lowercased().hasSuffix(".fig") { n = String(n.dropLast(4)) }
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        if n.isEmpty { n = "Макет" }
        return String(n.prefix(80)) + ".fig"
    }

    /// Готовые макеты в папке — для пустой вкладки
    func designFiles() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: designsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "fig" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    // MARK: мост

    /// Дождаться, пока редактор загрузится и поднимет мост
    func waitDesignReady(_ tab: Tab, seconds: Double = 25) async -> Bool {
        let limit = Date().addingTimeInterval(seconds)
        while Date() < limit {
            if let w = tab.web, !w.isLoading,
               (try? await w.callAsyncJavaScript("return !!(window.lumenDesign && window.lumenDesign.ready && window.openPencil && window.openPencil.getStore && (() => { try { return !!window.openPencil.getStore() } catch (e) { return false } })())",
                                                 contentWorld: .page)) as? Bool == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Любая команда моста: JSON-ответ строкой; ошибка — текстом
    func designCall(_ command: String, _ args: [String: Any], in tab: Tab) async -> (ok: Bool, text: String, json: Any?) {
        guard let w = tab.web else { return (false, "Макет не открыт.", nil) }
        let js = """
        const d = window.lumenDesign;
        if (!d) return JSON.stringify({ok: false, error: 'Редактор ещё не загрузился'});
        try { const r = await d.call(command, args); return JSON.stringify(r ?? {ok: true}); }
        catch (e) { return JSON.stringify({ok: false, error: String(e && e.message || e)}); }
        """
        do {
            let raw = try await w.callAsyncJavaScript(js, arguments: ["command": command, "args": args], in: nil, contentWorld: .page) as? String ?? "{}"
            let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8))
            if let d = obj as? [String: Any], d["ok"] as? Bool == false {
                return (false, d["error"] as? String ?? "Не вышло.", obj)
            }
            return (true, raw, obj)
        } catch {
            return (false, "Ошибка редактора: \(error.localizedDescription)", nil)
        }
    }

    /// Один инструмент дизайна; в редакторе агент виден своим курсором и рамкой на слоях
    func designTool(_ name: String, _ args: [String: Any], who: String, in tab: Tab) async -> (ok: Bool, text: String) {
        guard let w = tab.web else { return (false, "Макет не открыт.") }
        let js = """
        const d = window.lumenDesign;
        if (!d) return JSON.stringify({ok: false, error: 'Редактор ещё не загрузился'});
        try { const r = await d.tool(name, args, who); return JSON.stringify(r ?? {ok: true}); }
        catch (e) { return JSON.stringify({ok: false, error: String(e && e.message || e)}); }
        """
        do {
            let raw = try await w.callAsyncJavaScript(js, arguments: ["name": name, "args": args, "who": who], in: nil, contentWorld: .page) as? String ?? "{}"
            if let d = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], d["ok"] as? Bool == false {
                return (false, d["error"] as? String ?? "Не вышло.")
            }
            return (true, raw)
        } catch {
            return (false, "Ошибка редактора: \(error.localizedDescription)")
        }
    }

    /// Справочник «как рисовать» и список инструментов — из самого редактора
    func designGuide(_ tab: Tab) async -> String {
        let r = try? await tab.web?.callAsyncJavaScript("return window.lumenDesign ? window.lumenDesign.guide() : ''", contentWorld: .page)
        return r as? String ?? ""
    }

    func designToolList(_ tab: Tab) async -> [[String: Any]] {
        let raw = try? await tab.web?.callAsyncJavaScript("return window.lumenDesign ? JSON.stringify(window.lumenDesign.tools()) : '[]'", contentWorld: .page)
        guard let s = raw as? String, let list = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [[String: Any]] else { return [] }
        return list
    }

    // MARK: открыть, сохранить

    /// Открыть (или создать) макет в браузере: вкладка агента или новая. Возвращает вкладку
    func openDesign(name: String, in given: Tab?, select: Bool) async throws -> Tab {
        let server = try await designServerReady()
        let file = Self.designFileName(name)
        if let t = tabs.first(where: { designDocs[$0.id] == file }) {
            if select { self.select(t.id) }
            return t
        }
        let tab: Tab
        // один макет — одна вкладка: в вкладку с другим макетом новый не кладём
        if let given, given.file == nil, given.isLoaded, isDesign(given), designDocs[given.id] == nil, modelDocs[given.id] == nil {
            tab = given
        } else if let given, given.file == nil, designDocs[given.id] == nil, modelDocs[given.id] == nil, (given.url.isEmpty || given.url == "about:blank") {
            tab = given
            tab.webView.load(URLRequest(url: server.editorURL))
        } else {
            tab = newTab(configuration: nil, select: select)
            tab.webView.load(URLRequest(url: server.editorURL))
        }
        if select { self.select(tab.id); wantsFull += 1 }
        BrowserStage.keepRendering(tab.webView)
        try? FileManager.default.createDirectory(at: designsDir, withIntermediateDirectories: true)
        guard await waitDesignReady(tab) else { throw DesignError("Редактор макетов не загрузился за 25 секунд.") }
        let exists = FileManager.default.fileExists(atPath: designsDir.appendingPathComponent(file).path)
        let r = await designCall(exists ? "open_file" : "new_document", ["path": file], in: tab)
        guard r.ok else { throw DesignError(r.text) }
        if let o = r.json as? [String: Any], let target = o["target"] as? [String: Any], let doc = target["documentId"] as? String {
            designDocIDs[tab.id] = doc
        }
        designDocs[tab.id] = file
        tab.title = String(file.dropLast(4))
        await tidyDesignTabs(tab, title: tab.title)
        startDesignAutosave()
        onTabsChange?()
        return tab
    }

    /// В редакторе остаётся один документ — этот макет, под своим названием (пустой «Untitled» при запуске закрывается)
    private func tidyDesignTabs(_ tab: Tab, title: String) async {
        _ = try? await tab.web?.callAsyncJavaScript("try { window.openPencil.getStore().state.documentName = t } catch (e) {}", arguments: ["t": title], in: nil, contentWorld: .page)
        let list = await designCall("list_documents", [:], in: tab)
        guard let o = list.json as? [String: Any], let res = o["result"] as? [String: Any], let docs = res["documents"] as? [[String: Any]] else { return }
        for d in docs where d["active"] as? Bool != true && d["path"] == nil {
            if let id = d["id"] as? String {
                // «Домой» редактора не закрывается — и не надо: это его стартовый экран
                _ = await designCall("close_file", ["document_id": id, "unsaved": "discard"], in: tab)
            }
        }
    }

    /// Сохранить макет вкладки в его файл (если есть несохранённое)
    @discardableResult
    func saveDesign(_ tab: Tab, force: Bool = false) async -> Bool {
        guard let file = designDocs[tab.id] else { return false }
        return await saveDesign(tab, file: file, document: designDocIDs[tab.id], force: force)
    }

    /// Сохраняется именно документ этого макета (по id), даже если в редакторе сейчас открыт другой
    @discardableResult
    func saveDesign(_ tab: Tab, file: String, document: String?, force: Bool) async -> Bool {
        guard let w = tab.web else { return false }
        if !force {
            let dirty = (try? await w.callAsyncJavaScript("try { return window.openPencil.getStore().hasUnsavedChanges() } catch (e) { return true }", contentWorld: .page)) as? Bool ?? true
            guard dirty else { return true }
        }
        var args: [String: Any] = ["path": file]
        if let document { args["document_id"] = document }
        return await designCall("save_file", args, in: tab).ok
    }

    /// Правки человека и агента сохраняются сами: раз в несколько секунд, если что-то поменялось
    func startDesignAutosave() {
        guard designAutosave == nil else { return }
        designAutosave = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self else { return }
                let open = self.tabs.filter { self.designDocs[$0.id] != nil && $0.isLoaded }
                if open.isEmpty { continue }
                for t in open { await self.saveDesign(t) }
            }
        }
    }

    // MARK: выделенное — в чат

    struct DesignPick {
        var file: String
        var lines: [String]
        var image: NSImage?
    }

    /// Что выделено в открытом макете: названия, типы, размеры и картинка выделенного
    func designSelection() async -> DesignPick? {
        let tab = active
        guard isDesign(tab), let file = designDocs[tab.id] ?? Optional(tab.title + ".fig") else { return nil }
        let sel = await designCall("selection", [:], in: tab)
        guard sel.ok, let obj = sel.json as? [String: Any], let nodes = obj["result"] as? [[String: Any]], !nodes.isEmpty else { return nil }
        let lines = nodes.prefix(12).map { n -> String in
            let name = n["name"] as? String ?? "слой"
            let type = (n["type"] as? String ?? "").lowercased()
            let w = n["width"] as? Int ?? 0, h = n["height"] as? Int ?? 0
            return "«\(name)» (\(type) \(w)×\(h), id \(n["id"] as? String ?? ""))"
        }
        var image: NSImage?
        let ids = nodes.compactMap { $0["id"] as? String }
        let exp = await designCall("export", ["nodeIds": ids, "scale": 2, "format": "PNG"], in: tab)
        if exp.ok, let o = exp.json as? [String: Any], let res = o["result"] as? [String: Any], let b64 = res["base64"] as? String,
           let data = Data(base64Encoded: b64) { image = NSImage(data: data) }
        return DesignPick(file: String(file.dropLast(4)), lines: lines, image: image)
    }
}

extension BrowserModel {
    /// Инструменты агента для макетов (design_*)
    func performDesign(tool: String, args: [String: Any], who: String) async -> BrowserTools.Reply {
        func s(_ k: String) -> String { (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = Self.shortWho(who)
        switch tool {
        case "design_open":
            let title = s("name").isEmpty ? "Макет" : s("name")
            show(who, "Открывает макет «\(title)»")
            do {
                let tab = try await openDesign(name: title, in: workTab, select: true)
                adoptForAgent(tab, who: who)
                var text = "Макет «\(title)» открыт в браузере сбоку (файл \(designsDir.appendingPathComponent(Self.designFileName(title)).path)). Человек видит редактор и может сам двигать, править тексты и цвета; правки сохраняются сами. Рисуй инструментом design (tool + args), чаще всего render с JSX — целый экран за один вызов; посмотреть результат — design_shot."
                if !designGuideSent.contains(who) {
                    designGuideSent.insert(who)
                    let guide = await designGuide(tab)
                    let names = await designToolList(tab).compactMap { $0["name"] as? String }
                    text += "\n\nИнструменты (подробности и схема — design_tools с name): " + names.joined(separator: ", ")
                    if !guide.isEmpty { text += "\n\nКак рисовать в этом редакторе:\n" + guide }
                }
                return .init(text: text)
            } catch {
                return .init(text: error.localizedDescription, error: true)
            }
        case "design_tools":
            guard let tab = designTab else { return .init(text: "Сначала открой макет: design_open.", error: true) }
            let list = await designToolList(tab)
            if !s("name").isEmpty {
                guard let t = list.first(where: { ($0["name"] as? String) == s("name") }) else { return .init(text: "Нет инструмента \(s("name")).", error: true) }
                let schema = (try? JSONSerialization.data(withJSONObject: t["schema"] ?? [:], options: [.prettyPrinted, .sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                return .init(text: "\(s("name")): \(t["description"] as? String ?? "")\nМеняет макет: \((t["mutates"] as? Bool) == true ? "да" : "нет")\nПараметры:\n\(schema)")
            }
            let q = s("query").lowercased()
            let lines = list.compactMap { t -> String? in
                guard let n = t["name"] as? String else { return nil }
                let d = (t["description"] as? String ?? "").split(separator: ".").first.map(String.init) ?? ""
                if !q.isEmpty, !n.lowercased().contains(q), !d.lowercased().contains(q) { return nil }
                return "• \(n) — \(d)"
            }
            return .init(text: lines.isEmpty ? "Ничего не нашлось." : lines.joined(separator: "\n"))
        case "design_guide":
            guard let tab = designTab else { return .init(text: "Сначала открой макет: design_open.", error: true) }
            let g = await designGuide(tab)
            return .init(text: g.isEmpty ? "Справочника нет." : g)
        case "design":
            guard let tab = designTab else { return .init(text: "Сначала открой макет: design_open.", error: true) }
            let t = s("tool")
            guard !t.isEmpty else { return .init(text: "Укажи tool — имя инструмента (render, create_shape, update_node, set_fill, get_page_tree …).", error: true) }
            show(who, Self.designActivity(t))
            let r = await designTool(t, args["args"] as? [String: Any] ?? [:], who: name, in: tab)
            if !r.ok { return .init(text: "\(t): \(r.text)", error: true) }
            return .init(text: Self.clip(r.text, 14_000))
        case "design_eval":
            guard let tab = designTab else { return .init(text: "Сначала открой макет: design_open.", error: true) }
            show(who, "Рисует скриптом")
            let r = await designCall("eval", ["code": args["code"] as? String ?? ""], in: tab)
            return .init(text: Self.clip(r.text, 14_000), error: !r.ok)
        case "design_shot":
            guard let tab = designTab else { return .init(text: "Сначала открой макет: design_open.", error: true) }
            show(who, "Смотрит на макет")
            var a: [String: Any] = ["scale": (args["scale"] as? Double) ?? 1, "format": "PNG"]
            if let ids = args["node_ids"] as? [String], !ids.isEmpty { a["nodeIds"] = ids } else { a["scope"] = "page" }
            let r = await designCall("export", a, in: tab)
            guard r.ok, let o = r.json as? [String: Any], let res = o["result"] as? [String: Any], let b64 = res["base64"] as? String,
                  let data = Data(base64Encoded: b64), let img = NSImage(data: data), let (png, _) = Self.png(img, maxWidth: 1600) else {
                return .init(text: "Картинка не получилась: \(r.text)", error: true)
            }
            return .init(text: "Макет картинкой (\(Int(img.size.width))×\(Int(img.size.height))). Человек видит её в чате.", image: png)
        case "design_save":
            guard let tab = designTab else { return .init(text: "Макет не открыт.", error: true) }
            let ok = await saveDesign(tab, force: true)
            return .init(text: ok ? "Сохранено: \(designDocs[tab.id] ?? "")." : "Сохранить не вышло.", error: !ok)
        default:
            return .init(text: "Нет такого действия: \(tool)", error: true)
        }
    }

    nonisolated static func designActivity(_ tool: String) -> String {
        switch tool {
        case "render": "Рисует экран"
        case "create_shape", "create_vector": "Рисует фигуру"
        case "update_node", "set_fill", "set_stroke", "set_effects", "set_layout": "Правит макет"
        case "delete_node": "Удаляет слой"
        case "create_component", "create_instance": "Делает компонент"
        default: tool.hasPrefix("get") || tool.hasPrefix("list") || tool.hasPrefix("find") || tool.hasPrefix("node") ? "Смотрит макет" : "Работает в макете"
        }
    }

    nonisolated static func clip(_ s: String, _ n: Int) -> String {
        s.count > n ? String(s.prefix(n)) + "\n… ответ длиннее, сузь запрос (node_id, depth)" : s
    }
}
