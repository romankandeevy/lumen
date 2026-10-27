import Foundation

/// Распознавание речи для голосового ввода: Resources/Voice/server.py на Python и моделях FlowLocal (только чтение).
/// Русский — GigaAM v3, английский — Parakeet; всё на этом Маке. Процесс поднимается при первой диктовке
/// и сам закрывается, если им долго не пользуются
final class VoiceBackend: @unchecked Sendable {
    static let shared = VoiceBackend()

    /// Чего не хватает и куда человеку идти
    struct Problem: Equatable {
        var text: String
        var buttonTitle: String?
        var url: URL?
    }

    private static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FlowLocal")
    static let python = support.appendingPathComponent("Python/bin/python3")
    static let flowLocalPage = URL(string: "https://github.com/romankandeevy/flowlocal/releases/latest")

    /// Папка модели: русская — GigaAM, английская — Parakeet
    static func modelDir(_ lang: String) -> URL {
        support.appendingPathComponent("Models/" + (lang == "en" ? "nemo-parakeet-tdt-0.6b-v2-int8" : "gigaam-v3-e2e-rnnt-int8"))
    }

    /// Есть ли всё нужное: Python и модель из FlowLocal. Нет — что сказать человеку
    static func problem(for lang: String) -> Problem? {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: python.path), fm.fileExists(atPath: modelDir(lang).path) else {
            return Problem(text: "Голосу нужен FlowLocal: установите его и запустите один раз — он скачает модели распознавания",
                           buttonTitle: "Скачать FlowLocal", url: flowLocalPage)
        }
        guard script != nil else { return Problem(text: "В приложении нет скрипта распознавания", buttonTitle: nil, url: nil) }
        return nil
    }

    /// Скрипт — в приложении; при запуске из исходников — рядом с ними
    static var script: URL? {
        let fm = FileManager.default
        // для проверок: скрипт из исходников
        if let e = ProcessInfo.processInfo.environment["LUMEN_VOICE_SCRIPT"], fm.fileExists(atPath: e) { return URL(fileURLWithPath: e) }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Voice/server.py"), fm.fileExists(atPath: r.path) { return r }
        let dev = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Voice/server.py")
        return fm.fileExists(atPath: dev.path) ? dev : nil
    }

    private let q = DispatchQueue(label: "lumen.voice")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var ready = false
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]
    private var waiting: [(Int, [Float], String)] = []
    private var idle: DispatchWorkItem?

    /// Распознать запись целиком. nil — не вышло (процесс не поднялся, упал, не ответил за 40 с)
    func transcribe(_ samples: [Float], lang: String) async -> String? {
        await withCheckedContinuation { c in
            q.async {
                let id = self.nextID
                self.nextID += 1
                self.pending[id] = c
                if self.process == nil { self.launch() }
                if self.ready { self.send(id, samples, lang) } else { self.waiting.append((id, samples, lang)) }
                self.touch()
                self.q.asyncAfter(deadline: .now() + 40) { self.pending.removeValue(forKey: id)?.resume(returning: nil) }
            }
        }
    }

    /// Закрыть процесс (Lumen закрывается)
    func shutdown() {
        q.sync { quit() }
    }

    // MARK: процесс

    private func touch() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.quit() }
        idle = work
        // модель держит сотни мегабайт: через три минуты без диктовки процесс закрывается, следующая диктовка поднимет его заново
        q.asyncAfter(deadline: .now() + 180, execute: work)
    }

    private func quit() {
        idle?.cancel()
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        ready = false
        for (_, c) in pending { c.resume(returning: nil) }
        pending.removeAll()
        waiting.removeAll()
    }

    private func launch() {
        guard let script = Self.script, FileManager.default.isExecutableFile(atPath: Self.python.path) else {
            flush(nil)
            return
        }
        let p = Process()
        p.executableURL = Self.python
        p.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        // скрипт лежит внутри подписанного .app: __pycache__ в нём сломал бы подпись
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self, !data.isEmpty else { return }
            self.q.async { self.receive(data) }
        }
        p.terminationHandler = { [weak self] proc in
            self?.q.async {
                guard let self, self.process === proc else { return }
                self.process = nil
                self.input = nil
                self.ready = false
                self.flush(nil)
            }
        }
        buffer.removeAll()
        ready = false
        do {
            try p.run()
            process = p
            input = inPipe.fileHandleForWriting
        } catch {
            flush(nil)
        }
    }

    /// Всем ожидающим — ответ (nil: не вышло)
    private func flush(_ text: String?) {
        for (_, c) in pending { c.resume(returning: text) }
        pending.removeAll()
        waiting.removeAll()
    }

    private func send(_ id: Int, _ samples: [Float], _ lang: String) {
        guard let input else { pending.removeValue(forKey: id)?.resume(returning: nil); return }
        var data = Data("{\"cmd\":\"transcribe\",\"id\":\(id),\"lang\":\"\(lang)\",\"samples\":\(samples.count)}\n".utf8)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        do { try input.write(contentsOf: data) } catch { pending.removeValue(forKey: id)?.resume(returning: nil) }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let event = obj["event"] as? String {
                if event == "ready" {
                    ready = true
                    let queued = waiting
                    waiting.removeAll()
                    for (id, s, lang) in queued { send(id, s, lang) }
                } else if event == "error" {
                    flush(nil)
                }
            } else if let id = obj["id"] as? Int {
                let failed = obj["error"] != nil
                pending.removeValue(forKey: id)?.resume(returning: failed ? nil : (obj["text"] as? String))
            }
        }
    }
}
