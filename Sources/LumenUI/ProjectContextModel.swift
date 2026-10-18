import Foundation
import LumenCore
import LumenStorage

// Контекст проекта (PROJECT.md, Рома 18.10): Lumen сам его заводит, заполняет по папке проекта и после каждого ответа
// дописывает, что поменялось, и короткий компакт этого чата. Новый чат в проекте сразу знает, где он и что уже было;
// чаты проекта видят компакт друг друга. Человек добавляет своё словами в чате (add_to_project) или правит файл руками.

/// Обновления контекста идут по одному на проект: пока идёт одно, следующее ждёт и берёт самый свежий чат
@MainActor enum ProjectContextQueue {
    static var running: Set<String> = []
    static var again: [String: Conversation] = [:]
}

extension AppModel {
    func contextURL(_ p: Project) -> URL { p.contextURL(fallback: paths.projects) }

    /// Текст PROJECT.md. Файла ещё нет — заводим заготовку (и заполняем по папке фоном)
    func projectContext(_ p: Project) -> String? {
        ensureContextFile(p)
        return try? String(contentsOf: contextURL(p), encoding: .utf8)
    }

    /// Заготовка PROJECT.md. Существующий файл не трогаем — его могли написать руками.
    /// Проект получил папку — прежний PROJECT.md из папки Lumen переезжает в неё.
    /// У проекта со своей папкой Lumen сразу фоном заполняет разделы по README, CLAUDE.md и истории git.
    func ensureContextFile(_ p: Project) {
        let url = contextURL(p)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oldDir = paths.projects.appendingPathComponent(p.id, isDirectory: true)
        let old = oldDir.appendingPathComponent(Project.contextFileName)
        if let folder = p.ownFolder, fm.fileExists(atPath: old.path), (try? fm.moveItem(at: old, to: url)) != nil {
            let files = oldDir.appendingPathComponent(ProjectContext.filesFolder, isDirectory: true)
            if fm.fileExists(atPath: files.path) {
                try? fm.moveItem(at: files, to: folder.appendingPathComponent(ProjectContext.filesFolder, isDirectory: true))
            }
            if let doc = try? String(contentsOf: url, encoding: .utf8) {
                try? ProjectContext.appending("Папка: `\(folder.path)`", to: "Где", in: doc).write(to: url, atomically: true, encoding: .utf8)
            }
            log("Проекты: контекст «\(p.name)» переехал в \(url.path)")
            return
        }
        guard (try? ProjectContext.template(name: p.name, folder: p.ownFolder?.path).write(to: url, atomically: true, encoding: .utf8)) != nil else {
            log("Проекты: не смог завести \(url.path)")
            return
        }
        log("Проекты: завёл \(url.path)")
        if p.ownFolder != nil {
            let id = p.id
            ProjectContextQueue.running.insert(id)
            Task {
                await fillProjectContext(p)
                ProjectContextQueue.running.remove(id)
                if let next = ProjectContextQueue.again.removeValue(forKey: id) { updateProjectContext(after: next) }
            }
        }
    }

    /// Как модель ведёт PROJECT.md: правит только свои разделы, «Заметки» человека не трогает
    static let contextSystem = """
        Ты ведёшь PROJECT.md — контекст проекта для помощника Lumen. Его читает каждый новый чат проекта, чтобы сразу знать, \
        что это за проект, где он лежит, как устроен и что уже сделано, и ничего не переспрашивать.
        Отвечай строго JSON без markdown:
        {"sections": {"Что это": "…" или null, "Где": "…" или null, "Стек и запуск": "…" или null, "Статус": "…" или null, "Решения": "…" или null}, "chat": "…" или null}
        sections — НОВЫЙ полный текст раздела в Markdown, только если в нём надо что-то поменять или добавить; иначе null. \
        Не теряй то, что в разделе уже было и всё ещё верно. Пиши коротко, по-русски, фактами: пути, адреса, команды, имена, решения. \
        Без воды, без пересказа разговора, без выдумок — только то, что видно из материалов. \
        Про сам PROJECT.md и его заполнение не пиши.
        «Что это» — одним-двумя предложениями, что за проект и для кого. «Где» — папки, сайт, репозиторий, где запущено. \
        «Стек и запуск» — на чём сделано и какими командами собрать, запустить, проверить. \
        «Статус» — что сделано, что в работе, что ждёт решения, с датами ДД.ММ. «Решения» — принятые решения и почему, списком.
        chat — компакт этого чата для других чатов проекта: 2–4 предложения, о чём он, что сделано, что осталось. Нет чата — null.
        """

    /// Первое заполнение по папке проекта: что за проект, стек, как запускать, что сейчас
    func fillProjectContext(_ p: Project) async {
        guard let folder = p.ownFolder else { return }
        let fm = FileManager.default
        var parts: [String] = []
        let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        if !names.isEmpty { parts.append("Файлы в корне папки: " + names.prefix(80).joined(separator: ", ")) }
        for n in ["README.md", "CLAUDE.md", "AGENTS.md", "Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod"] {
            if let t = try? String(contentsOf: folder.appendingPathComponent(n), encoding: .utf8), !t.isEmpty {
                parts.append("\(n):\n" + String(t.prefix(4000)))
            }
        }
        if let git = await Self.git(["-C", folder.path, "log", "--date=format:%d.%m", "--format=%ad %s", "-15"]) {
            parts.append("Последние коммиты:\n" + git)
        }
        guard !parts.isEmpty, let doc = try? String(contentsOf: contextURL(p), encoding: .utf8) else { return }
        let prompt = "Проект «\(p.name)», папка \(folder.path). Это первое заполнение, PROJECT.md сейчас:\n\(doc)\n\nЧто есть в папке:\n\n"
            + parts.joined(separator: "\n\n")
        guard let text = await quickAsk(prompt, system: Self.contextSystem), let json = Self.jsonObject(in: text) else {
            log("Проекты: не смог заполнить контекст «\(p.name)» по папке")
            return
        }
        writeContext(p, json: json, chat: nil)
    }

    /// После ответа в чате проекта: обновить разделы и компакт этого чата (фоном, по одному на проект)
    func updateProjectContext(after c: Conversation) {
        guard let pid = c.projectID, project(pid) != nil, cli != nil else { return }
        if ProjectContextQueue.running.contains(pid) {
            ProjectContextQueue.again[pid] = c
            return
        }
        ProjectContextQueue.running.insert(pid)
        Task {
            await refreshProjectContext(c)
            ProjectContextQueue.running.remove(pid)
            if let next = ProjectContextQueue.again.removeValue(forKey: pid) { updateProjectContext(after: next) }
        }
    }

    private func refreshProjectContext(_ c: Conversation) async {
        guard let p = project(c.projectID), let doc = projectContext(p) else { return }
        let c = conversations.first { $0.id == c.id } ?? c
        let msgs = ((try? store.messages(in: c.id)) ?? []).filter { $0.error == nil && !$0.text.isEmpty }.suffix(12)
        guard !msgs.isEmpty else { return }
        let talk = msgs.map { ($0.role == .user ? "Человек" : "Lumen") + ": " + String($0.text.prefix(2000)) }.joined(separator: "\n\n")
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        let prompt = "Сегодня \(f.string(from: Date())). PROJECT.md сейчас:\n\(doc.prefix(30_000))\n\n"
            + "Чат «\(c.title)» — последние сообщения:\n\n\(talk)"
        guard let text = await quickAsk(prompt, system: Self.contextSystem), let json = Self.jsonObject(in: text) else { return }
        writeContext(p, json: json, chat: c)
    }

    /// Применить ответ модели к свежему PROJECT.md (за время запроса его могли поправить) и сказать остальным чатам проекта
    private func writeContext(_ p: Project, json: [String: Any], chat c: Conversation?) {
        let url = contextURL(p)
        guard let before = try? String(contentsOf: url, encoding: .utf8) else { return }
        let after = Self.applyContext(json, to: before, chat: c)
        guard after != before, (try? after.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        // остальные чаты проекта возьмут новый контекст со следующего хода; этот продолжает со своей историей
        for ctl in controllers { ctl.promptChanged(projectID: p.id, except: c?.id) }
    }

    /// Разделы, которые модель предложила поменять, и компакт чата — в документ
    static func applyContext(_ json: [String: Any], to doc: String, chat c: Conversation?) -> String {
        var doc = doc
        if let s = json["sections"] as? [String: Any] {
            for title in ProjectContext.autoSections {
                if let t = s[title] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    doc = ProjectContext.replacing(title, with: t, in: doc)
                }
            }
        }
        if let c, let chat = json["chat"] as? String, !chat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            doc = ProjectContext.settingChat(id: c.id, title: c.title, summary: chat, in: doc)
        }
        return doc
    }

    /// git в папке проекта; не репозиторий или ошибка — nil
    nonisolated static func git(_ args: [String]) async -> String? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }.value
    }
}
