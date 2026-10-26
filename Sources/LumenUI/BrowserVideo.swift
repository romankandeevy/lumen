import AppKit
import Foundation
import LumenCore
import LumenProviders
import WebKit

/// Видео «как в Claude» (Рома, 26.10, 1.7.2): HyperFrames (Apache-2.0, heygen-com/hyperframes) — анимации на HTML/GSAP,
/// которые рендерятся в MP4 кадр за кадром. Агент пишет сцены (video_write), проверяет (video_cli check), смотрит кадры
/// (video_shot), берёт готовые блоки из каталога, делает озвучку и рендерит (video_render). Человек монтирует в Студии
/// HyperFrames прямо в браузере сбоку: таймлайн, ключевые кадры, слои, тексты, экспорт; выделенное — в чат.
/// Проекты — папки в `<данные Lumen>/videos/<название>`.
extension BrowserModel {
    /// Справочник по видео (SKILL.md и references HyperFrames): в Lumen.app или tools/video/guide рядом с исходниками
    nonisolated static func videoGuideRoot() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("VideoGuide")) }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../tools/video/guide").standardized)
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
    }

    /// Node и FFmpeg есть на этом Маке (проверяется один раз за запуск)
    nonisolated static let videoAvailable: Bool = VideoCLI.available

    func videoDir(_ name: String) -> URL { videosDir.appendingPathComponent(name, isDirectory: true) }

    func isVideo(_ tab: Tab) -> Bool {
        guard let u = URL(string: tab.url.isEmpty ? (tab.pending ?? "") : tab.url), u.host == "127.0.0.1", let port = u.port else { return false }
        return videoPorts.values.contains(port)
    }

    var videoTab: Tab? {
        if let t = tabs.first(where: { $0.id == agentTabID }), isVideo(t) { return t }
        if isVideo(active) { return active }
        return tabs.last { isVideo($0) }
    }

    /// Проекты в папке видео — для пустой вкладки
    func videoProjects() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.map(\.lastPathComponent)
    }

    // MARK: Студия

    /// Поднять Студию проекта (фоновый сервер HyperFrames) и вернуть её адрес
    func startStudio(_ name: String) async throws -> URL {
        let dir = videoDir(name)
        if !videoTelemetryOff {
            videoTelemetryOff = true
            await VideoCLI.disableTelemetry(cwd: videosDir)
        }
        // у каждого ролика своя Студия: свободный порт с 47830 (уже запущенную для этой папки HyperFrames вернёт сам)
        let port = (47830..<47900).first { p in !videoPorts.values.contains(p) && DesignServer.free(UInt16(p)) } ?? 47830
        _ = try await VideoCLI.run(["preview", ".", "--port", "\(port)", "--no-open", "--background"], cwd: dir)
        for _ in 0..<20 {
            let st = try await VideoCLI.run(["preview", ".", "--status", "--json"], cwd: dir)
            if let o = try? JSONSerialization.jsonObject(with: Data(VideoCLI.plain(st.stdout).utf8)) as? [String: Any],
               let res = o["result"] as? [String: Any], res["ready"] as? Bool == true,
               let s = res["studioUrl"] as? String, let url = URL(string: s), let port = res["port"] as? Int {
                videoPorts[name] = port
                if let pid = res["pid"] as? Int { videoPIDs[name] = Int32(pid) }
                return url
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        throw DesignError("Студия видео не запустилась. Проверь: \(VideoCLI.missing().isEmpty ? "npx hyperframes doctor" : VideoCLI.missing().joined(separator: ", "))")
    }

    /// Открыть (или создать) видео в браузере: новая папка — `hyperframes init`, потом Студия
    func openVideo(name raw: String, resolution: String = "landscape", in given: Tab?, select: Bool) async throws -> Tab {
        let missing = VideoCLI.missing()
        guard missing.isEmpty else { throw VideoCLI.Missing(what: missing) }
        let name = Self.modelName(raw)
        if let t = tabs.first(where: { videoDocs[$0.id] == name }) {
            if select { self.select(t.id); wantsFull += 1 }
            return t
        }
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        let dir = videoDir(name)
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) {
            let res = ["landscape", "portrait", "square", "landscape-4k", "portrait-4k", "square-4k"].contains(resolution) ? resolution : "landscape"
            let r = try await VideoCLI.run(["init", name, "--example", "blank", "--non-interactive", "--resolution", res], cwd: videosDir)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) else {
                throw DesignError("Проект видео не создался: \(VideoCLI.plain(r.stderr + r.stdout).suffix(600))")
            }
        }
        let studio = try await startStudio(name)
        let tab: Tab
        if let given, given.file == nil, designDocs[given.id] == nil, modelDocs[given.id] == nil, videoDocs[given.id] == nil, (given.url.isEmpty || given.url == "about:blank") {
            tab = given
        } else {
            tab = newTab(configuration: nil, select: select)
        }
        tab.webView.load(URLRequest(url: studio))
        if select { self.select(tab.id); wantsFull += 1 }
        BrowserStage.keepRendering(tab.webView)
        tab.webView.allowsMagnification = false
        tab.webView.magnification = 1
        videoDocs[tab.id] = name
        tab.title = name
        onTabsChange?()
        return tab
    }

    /// В Студии — только то, что работает в Lumen: без логотипа HeyGen в шапке, рекламы их приложения и подсказок про их агента
    /// (агент тут — Lumen, через чат). Лицензия Apache-2.0 логотип показывать не требует; текст лицензии лежит в VideoGuide
    func tidyStudio(_ tab: Tab) {
        let js = """
            if (!window.__lumenTidy) {
              window.__lumenTidy = true;
              const st = document.createElement('style');
              st.textContent = '[data-testid=header-open-in-desktop], .hf-framey-trigger, svg[aria-label=Hyperframes], svg[aria-label=Hyperframes] + span[aria-hidden=true] { display: none !important; }';
              document.head.appendChild(st);
              const hide = () => {
                const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let n;
                while ((n = w.nextNode())) {
                  if (/to the agent|desktop app|Framey/i.test(n.textContent)) {
                    const row = n.parentElement && n.parentElement.closest('span.justify-between, button, a');
                    if (row && row.style.display !== 'none') row.style.display = 'none';
                  }
                }
              };
              hide();
              let t = 0;
              new MutationObserver(() => { clearTimeout(t); t = setTimeout(hide, 120); }).observe(document.body, { childList: true, subtree: true });
            }
            """
        tab.webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Закрыли вкладку видео — Студию остановить (Node-сервер не висит зря)
    func stopStudio(_ name: String) {
        videoPorts[name] = nil
        guard let pid = videoPIDs.removeValue(forKey: name) else { return }
        kill(pid, SIGTERM)
        // Node ждёт, пока закроются открытые соединения превью, — не ждём его
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
    }

    /// Выход из Lumen: фоновые Студии не остаются висеть (синхронно — приложение сейчас закроется)
    func stopAllStudios() {
        for name in Array(videoPorts.keys) { stopStudio(name) }
    }

    // MARK: выделенное — в чат

    struct VideoPick {
        var name: String
        var line: String
        var image: NSImage?
    }

    /// Что выделено в Студии: элемент, его текст, сцена, момент на таймлайне и миниатюра
    func videoSelection() async -> VideoPick? {
        let tab = active
        guard isVideo(tab), let name = videoDocs[tab.id], let port = videoPorts[name],
              let url = URL(string: "http://127.0.0.1:\(port)/api/projects/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)/selection"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sel = o["selection"] as? [String: Any] else { return nil }
        let label = sel["label"] as? String ?? (sel["tagName"] as? String ?? "элемент")
        let target = sel["target"] as? [String: Any]
        let id = (target?["id"] as? String) ?? (target?["selector"] as? String) ?? ""
        let time = (sel["currentTime"] as? Double).map { String(format: "%.2f с", $0) } ?? ""
        let file = sel["sourceFile"] as? String ?? (sel["compositionPath"] as? String ?? "")
        let text = (sel["textContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120) ?? ""
        var line = "«\(label)»"
        var details: [String] = []
        if !id.isEmpty { details.append("id \(id)") }
        if !file.isEmpty { details.append(file) }
        if !time.isEmpty { details.append("на \(time)") }
        if !details.isEmpty { line += " (" + details.joined(separator: ", ") + ")" }
        if !text.isEmpty { line += ", текст: «\(text)»" }
        var image: NSImage?
        if let thumb = sel["thumbnailUrl"] as? String, !thumb.isEmpty {
            if thumb.hasPrefix("data:"), let comma = thumb.firstIndex(of: ","), let d = Data(base64Encoded: String(thumb[thumb.index(after: comma)...])) {
                image = NSImage(data: d)
            } else if let u = URL(string: thumb, relativeTo: URL(string: "http://127.0.0.1:\(port)/")), let (d, _) = try? await URLSession.shared.data(from: u) {
                image = NSImage(data: d)
            }
        }
        return VideoPick(name: name, line: line, image: image)
    }

    // MARK: файлы проекта (агент пишет только внутрь своей папки)

    func videoFile(_ name: String, _ path: String) -> URL? {
        let base = videoDir(name).standardizedFileURL.resolvingSymlinksInPath()
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("/"), !clean.hasPrefix("~") else { return nil }
        let url = base.appendingPathComponent(clean).standardizedFileURL
        let parentResolved = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard url.path.hasPrefix(base.path + "/"), parentResolved == base.path || parentResolved.hasPrefix(base.path + "/") || !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return nil }
        return url
    }

    // MARK: рендер в фоне (дольше, чем агент может ждать один вызов)

    final class VideoRender: @unchecked Sendable {
        enum State { case running, done, failed }
        let output: URL
        let started = Date()
        var state = State.running
        var log = ""
        init(output: URL) { self.output = output }
    }

    func startRender(_ name: String, quality: String, format: String) -> VideoRender {
        let dir = videoDir(name)
        let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm-ss"; return f.string(from: Date()) }()
        let ext = ["mp4", "webm", "mov", "gif"].contains(format) ? format : "mp4"
        let out = dir.appendingPathComponent("renders", isDirectory: true).appendingPathComponent("\(name) \(stamp).\(ext)")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let job = VideoRender(output: out)
        videoRenders[name] = job
        let q = ["draft", "looks", "delivery"].contains(quality) ? quality : "looks"
        Task.detached {
            do {
                let r = try await VideoCLI.run(["render", "-o", out.path, "--quality", q, "--format", ext, "--quiet"], cwd: dir)
                let ok = r.status == 0 && FileManager.default.fileExists(atPath: out.path)
                await MainActor.run {
                    job.log = VideoCLI.plain(r.stdout + "\n" + r.stderr)
                    job.state = ok ? .done : .failed
                }
            } catch {
                await MainActor.run { job.log = error.localizedDescription; job.state = .failed }
            }
        }
        return job
    }

    // MARK: инструменты агента (video_*)

    private static let videoCommands: Set<String> = ["check", "lint", "validate", "timeline", "compositions", "info", "history", "add", "catalog",
                                                     "keyframes", "inspect", "beats", "audio", "tts", "transcribe", "docs", "media-treatment",
                                                     "normalize-audio", "models", "capture", "compare", "grade-compare"]

    func performVideo(tool: String, args: [String: Any], who: String) async -> BrowserTools.Reply {
        func s(_ k: String) -> String { (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func current() -> String? { videoTab.flatMap { videoDocs[$0.id] } }
        switch tool {
        case "video_open":
            let name = Self.modelName(s("name"))
            show(who, "Открывает видео «\(name)»")
            do {
                let tab = try await openVideo(name: name, resolution: s("resolution").isEmpty ? "landscape" : s("resolution"), in: workTab, select: true)
                adoptForAgent(tab, who: who)
                var text = "Видео «\(name)» открыто в Студии HyperFrames в браузере сбоку: папка проекта \(videoDir(name).path). Человек видит превью и таймлайн и может сам монтировать: двигать клипы, менять тексты, ключевые кадры, экспортировать."
                if !videoGuideSent.contains(who) {
                    videoGuideSent.insert(who)
                    text += "\n\n" + Self.videoGuideIntro
                    if let root = Self.videoGuideRoot(), let skill = try? String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8) {
                        text += "\n\n— Справочник HyperFrames (SKILL.md) —\n" + skill
                    }
                }
                return .init(text: text)
            } catch {
                return .init(text: error.localizedDescription, error: true)
            }
        case "video_guide":
            guard let root = Self.videoGuideRoot() else { return .init(text: "Справочника нет.", error: true) }
            var topic = s("topic").replacingOccurrences(of: "references/", with: "")
            if topic.hasSuffix(".md") { topic.removeLast(3) }
            let file = topic.isEmpty ? root.appendingPathComponent("SKILL.md") : root.appendingPathComponent("references/\(topic).md")
            guard !topic.contains(".."), let text = try? String(contentsOf: file, encoding: .utf8) else {
                let list = ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("references").path)) ?? []).filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }
                let types = ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("references/types").path)) ?? []).map { "types/" + $0.dropLast(3) }
                return .init(text: "Нет раздела «\(topic)». Есть: " + (list + types).sorted().joined(separator: ", "), error: true)
            }
            return .init(text: text)
        case "video_files":
            guard let name = current() else { return .init(text: "Сначала открой видео: video_open.", error: true) }
            let base = videoDir(name)
            let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            var out: [String] = []
            while let u = e?.nextObject() as? URL {
                let rel = String(u.path.dropFirst(base.path.count + 1))
                if rel.hasPrefix("node_modules") || rel.hasPrefix("renders/") && out.count > 200 { e?.skipDescendants(); continue }
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { out.append("\(rel)  \(size / 1024) КБ") }
                if out.count > 300 { break }
            }
            return .init(text: "Файлы проекта \(base.path):\n" + out.sorted().joined(separator: "\n"))
        case "video_read":
            guard let name = current(), let url = videoFile(name, s("path")) else { return .init(text: "Нет такого файла в проекте (путь от папки проекта, например index.html или compositions/intro.html).", error: true) }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .init(text: "Не прочитать \(s("path")) (не текст или нет файла).", error: true) }
            return .init(text: Self.clip(text, 40_000))
        case "video_write":
            guard let name = current() else { return .init(text: "Сначала открой видео: video_open.", error: true) }
            guard let url = videoFile(name, s("path")) else { return .init(text: "Писать можно только внутрь папки проекта (путь вроде index.html, compositions/intro.html, assets/…).", error: true) }
            let content = args["content"] as? String ?? ""
            guard content.utf8.count < 3_000_000 else { return .init(text: "Файл больше 3 МБ — так не пишу.", error: true) }
            show(who, "Пишет сцену \(url.lastPathComponent)")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                return .init(text: "Записано: \(s("path")) (\(content.utf8.count / 1024) КБ). Студия обновится сама. Проверь: video_cli check.")
            } catch {
                return .init(text: "Не записалось: \(error.localizedDescription)", error: true)
            }
        case "video_cli":
            guard let name = current() else { return .init(text: "Сначала открой видео: video_open.", error: true) }
            let cmd = s("command")
            guard Self.videoCommands.contains(cmd) else {
                return .init(text: "Эту команду так не запускаю. Можно: \(Self.videoCommands.sorted().joined(separator: ", ")). Кадры — video_shot, рендер — video_render.", error: true)
            }
            var extra = (args["args"] as? [Any])?.map { "\($0)" } ?? []
            if ["check", "timeline", "compositions", "info", "lint", "validate", "inspect", "keyframes", "history"].contains(cmd), !extra.contains("--json") { extra.append("--json") }
            show(who, "Видео: \(cmd)")
            do {
                let r = try await VideoCLI.run([cmd] + extra, cwd: videoDir(name))
                let out = VideoCLI.plain(r.stdout + (r.stderr.isEmpty ? "" : "\n" + r.stderr)).trimmingCharacters(in: .whitespacesAndNewlines)
                return .init(text: Self.clip(out.isEmpty ? "(пусто, код \(r.status))" : out, 14_000), error: r.status != 0 && cmd != "check")
            } catch {
                return .init(text: error.localizedDescription, error: true)
            }
        case "video_shot":
            guard let name = current() else { return .init(text: "Сначала открой видео: video_open.", error: true) }
            show(who, "Смотрит кадры видео")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-video-shot-\(UUID().uuidString.prefix(6))", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            var cli = ["snapshot", "--output", dir.path, "--keep"]
            let at = (args["at"] as? [Any])?.compactMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? []
            if !at.isEmpty { cli += ["--at", at.prefix(6).map { String($0) }.joined(separator: ","), "--no-end"] } else { cli += ["--frames", "\(min(6, max(1, (args["frames"] as? Int) ?? 4)))"] }
            if !s("zoom").isEmpty { cli += ["--zoom", s("zoom")] }
            do {
                let r = try await VideoCLI.run(cli, cwd: videoDir(name))
                let pngs = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "png" }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                let images = pngs.compactMap { NSImage(contentsOf: $0) }
                guard !images.isEmpty, let sheet = Self.sheet(images, labels: pngs.map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "at-", with: "") }),
                      let (png, _) = Self.png(sheet, maxWidth: 1600) else {
                    return .init(text: "Кадры не снялись: \(Self.clip(VideoCLI.plain(r.stderr + r.stdout), 3000))", error: true)
                }
                return .init(text: "Кадры видео: \(pngs.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", ")). Человек видит их в чате.", image: png)
            } catch {
                return .init(text: error.localizedDescription, error: true)
            }
        case "video_render":
            guard let name = current() else { return .init(text: "Сначала открой видео: video_open.", error: true) }
            if let job = videoRenders[name], job.state == .running { return .init(text: "Рендер уже идёт (\(Int(Date().timeIntervalSince(job.started))) с): video_render_wait.") }
            show(who, "Рендерит видео")
            let job = startRender(name, quality: s("quality"), format: s("format"))
            return .init(text: "Рендер начат: \(job.output.path). Жди его через video_render_wait (до 80 с за вызов), потом покажи человеку файл — show_in_chat.")
        case "video_render_wait":
            guard let name = current(), let job = videoRenders[name] else { return .init(text: "Рендера нет — запусти video_render.", error: true) }
            show(who, "Ждёт рендер")
            let limit = Date().addingTimeInterval(min(80, (args["seconds"] as? Double) ?? Double(args["seconds"] as? Int ?? 60)))
            while job.state == .running, Date() < limit { try? await Task.sleep(for: .milliseconds(500)) }
            switch job.state {
            case .running: return .init(text: "Рендер ещё идёт (\(Int(Date().timeIntervalSince(job.started))) с). Позови video_render_wait ещё раз.")
            case .failed: return .init(text: "Рендер не удался:\n" + Self.clip(job.log, 6000), error: true)
            case .done:
                let size = ((try? job.output.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) / 1_048_576
                return .init(text: "Готово за \(Int(Date().timeIntervalSince(job.started))) с: \(job.output.path) (\(size) МБ). Покажи его человеку — show_in_chat с этим путём.")
            }
        default:
            return .init(text: "Нет такого действия: \(tool)", error: true)
        }
    }

    /// Кадры сеткой (до 6, по 2 в ряд) с подписями времени
    nonisolated static func sheet(_ images: [NSImage], labels: [String]) -> NSImage? {
        guard let first = images.first else { return nil }
        if images.count == 1 { return first }
        let w = first.size.width, h = first.size.height
        let cols = 2, rows = (images.count + 1) / 2
        let out = NSImage(size: NSSize(width: w * CGFloat(cols), height: h * CGFloat(rows)))
        out.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: out.size).fill()
        for (i, img) in images.enumerated() {
            let x = CGFloat(i % cols) * w, y = CGFloat(rows - 1 - i / cols) * h
            img.draw(in: NSRect(x: x, y: y, width: w, height: h))
            if i < labels.count {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(22, w / 40), weight: .semibold), .foregroundColor: NSColor.white,
                                                            .backgroundColor: NSColor.black.withAlphaComponent(0.55)]
                NSString(string: " \(labels[i]) ").draw(at: NSPoint(x: x + 16, y: y + h - max(40, w / 24)), withAttributes: attrs)
            }
        }
        out.unlockFocus()
        return out
    }

    nonisolated static let videoGuideIntro = """
        Как делать видео в Lumen (HyperFrames):
        - Студию Lumen уже открыл — preview запускать не надо. Команды «npx hyperframes X» из справочника делай через video_cli \
        (command: X, args: [...]): check, timeline, add (готовые блоки из каталога), catalog, tts (озвучка на этом Маке), beats, audio, \
        keyframes, inspect, transcribe, docs. Файлы проекта — video_write / video_read / video_files (пути от папки проекта: index.html, \
        compositions/<сцена>.html, assets/…). Кадры посмотреть — video_shot (at: [секунды]). Рендер — video_render, потом video_render_wait, \
        потом show_in_chat с путём MP4.
        - Цикл: план (сцены, длительность, палитра, шрифт) → сцены → video_cli check (исправить все ошибки) → video_shot по ключевым \
        моментам → поправить → показать человеку в Студии; рендерить, когда он доволен или просит файл.
        - Красиво и плавно: продуманные эйзы (power3/expo.out), нахлёсты и задержки, движение в 2–3 слоя, крупная типографика, \
        одна палитра и один шрифт на ролик, без дешёвых эффектов. Подробно — video_guide motion, look, film; типы роликов — video_guide types/launch и др.
        - Человек правит сам в Студии и присылает выделенный элемент в чат (id, сцена, момент) — меняй именно его.
        """
}
