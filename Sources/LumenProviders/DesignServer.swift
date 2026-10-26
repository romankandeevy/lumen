import Darwin
import Foundation
import Network

/// Локальный сервер редактора макетов (OpenPencil, собранный tools/design/build.sh): отдаёт его страницы на 127.0.0.1
/// (WebAssembly и модули требуют настоящего http, а не file://) и даёт ему читать и писать .fig в папке макетов
/// через `/files/…` — только с ключом, который знает Lumen. Слушает только этот Мак.
public final class DesignServer: @unchecked Sendable {
    public let root: URL
    public let files: URL
    public let token: String
    public private(set) var port: UInt16 = 0
    /// Где страница редактора внутри папки: "" — в корне (OpenPencil), "editor/" — three.js
    public let entry: String
    /// Неизвестный путь — главная страница (у одностраничных приложений свои адреса)
    public let spa: Bool

    private let listener: NWListener
    private let queue = DispatchQueue(label: "lumen.design.server", attributes: .concurrent)

    /// Постоянный порт: у редактора на нём свои настройки, шрифты и недавние файлы (у каждого адреса — своё хранилище).
    /// Занят — берётся любой свободный
    public static let preferredPort: UInt16 = 47_821

    public init(root: URL, files: URL, token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), port: UInt16? = DesignServer.preferredPort,
                entry: String = "", spa: Bool = true) throws {
        self.root = root.standardizedFileURL
        self.files = files.standardizedFileURL
        self.token = token
        self.entry = entry
        self.spa = spa
        func make(_ p: NWEndpoint.Port) throws -> NWListener {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: p)
            return try NWListener(using: params)
        }
        if let port, let p = NWEndpoint.Port(rawValue: port), let l = try? make(p), Self.free(port) {
            listener = l
        } else {
            listener = try make(.any)
        }
    }

    /// Свободен ли порт на 127.0.0.1 (NWListener узнаёт о занятом только после запуска)
    static func free(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
    }

    /// Адрес редактора: с ключом моста для Lumen
    public var editorURL: URL { URL(string: "http://127.0.0.1:\(port)/\(entry)?lumen=\(token)")! }

    public func start() async throws {
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let p: UInt16 = try await withCheckedThrowingContinuation { c in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { [weak self] st in
                guard let self, !resumed else { return }
                switch st {
                case .ready: resumed = true; c.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed(let e): resumed = true; c.resume(throwing: e)
                case .cancelled: resumed = true; c.resume(throwing: POSIXError(.ECANCELED))
                case .waiting(let e): resumed = true; self.listener.cancel(); c.resume(throwing: e)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
        }
        port = p
    }

    public func stop() { listener.cancel() }

    // MARK: http

    /// Один запрос: заголовок, потом тело ровно Content-Length байт (до 200 МБ); 30 секунд на всё
    private final class Request: @unchecked Sendable {
        var data = Data()
        var header: String?
        var bodyStart = 0
        var length = 0
    }

    static let maxBody = 200_000_000

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        let req = Request()
        queue.asyncAfter(deadline: .now() + 30) { if conn.state != .cancelled { conn.cancel() } }
        read(conn, req)
    }

    private func read(_ conn: NWConnection, _ req: Request) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { conn.cancel(); return }
            if let data { req.data.append(data) }
            if req.header == nil, let head = req.data.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: req.data[..<head.lowerBound], as: UTF8.self)
                let length = Self.header(header, "content-length").map { Int($0) ?? -1 } ?? 0
                guard length >= 0 else { self.fail(conn, 400, "Плохая длина"); return }
                guard length <= Self.maxBody else { self.fail(conn, 413, "Слишком большой файл"); return }
                req.header = header
                req.bodyStart = head.upperBound
                req.length = length
            }
            if let header = req.header, req.data.count - req.bodyStart >= req.length {
                self.respond(conn, header: header, body: req.data.subdata(in: req.bodyStart..<(req.bodyStart + req.length)))
                return
            }
            if done || error != nil || (req.header == nil && req.data.count > 64_000) { conn.cancel(); return }
            self.read(conn, req)
        }
    }

    private func fail(_ conn: NWConnection, _ code: Int, _ text: String) {
        let body = Data(text.utf8)
        var out = Data("HTTP/1.1 \(code) Error\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    static func header(_ head: String, _ name: String) -> String? {
        for line in head.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].lowercased() == name { return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private func respond(_ conn: NWConnection, header: String, body: Data) {
        let first = header.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"
        let path = String(rawPath.split(separator: "?", maxSplits: 1).first ?? "/")
        let reply: (Int, String, Data, [String: String])
        if path.hasPrefix("/files/") {
            reply = filesReply(method: method, path: path, auth: Self.header(header, "authorization"), body: body)
        } else {
            reply = staticReply(path)
        }
        var head = "HTTP/1.1 \(reply.0) \(reply.0 == 200 ? "OK" : "Error")\r\nContent-Type: \(reply.1)\r\nContent-Length: \(reply.2.count)\r\nConnection: close\r\n"
        for (k, v) in reply.3 { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        if method != "HEAD" { out.append(reply.2) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Страницы редактора: путь только внутри папки; неизвестный путь — index.html (у редактора свои адреса страниц)
    func staticReply(_ path: String) -> (Int, String, Data, [String: String]) {
        let clean = (path.removingPercentEncoding ?? path).split(separator: "/").filter { $0 != "." && $0 != ".." && !$0.isEmpty }.joined(separator: "/")
        // офлайн-кэш PWA выключен: страницу всегда отдаёт Lumen
        let last = clean.split(separator: "/").last.map(String.init) ?? ""
        if last == "sw.js" || last.hasPrefix("workbox-") { return (404, "text/plain", Data("no".utf8), [:]) }
        var url = root.appendingPathComponent(clean.isEmpty ? entry + "index.html" : clean)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue {
            url = url.appendingPathComponent("index.html")
        } else if !exists {
            guard spa, !clean.hasPrefix("assets/") else { return (404, "text/plain", Data("not found".utf8), [:]) }
            url = root.appendingPathComponent(entry + "index.html")
        }
        guard url.standardizedFileURL.path.hasPrefix(root.path), let data = try? Data(contentsOf: url) else {
            return (404, "text/plain", Data("not found".utf8), [:])
        }
        let cache = clean.hasPrefix("assets/") ? "public, max-age=31536000, immutable" : "no-cache"
        return (200, Self.mime(url.pathExtension), data, ["Cache-Control": cache])
    }

    /// Файл макета по пути, который назвал редактор: относительный — от папки макетов, абсолютный — только внутри неё
    public func resolve(_ name: String) -> URL? {
        let expanded = (name as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : files.appendingPathComponent(expanded)
        let std = url.standardizedFileURL.resolvingSymlinksInPath()
        let base = files.resolvingSymlinksInPath().path
        guard std.path == base || std.path.hasPrefix(base + "/") else { return nil }
        return std
    }

    func filesReply(method: String, path: String, auth: String?, body: Data) -> (Int, String, Data, [String: String]) {
        guard auth == "Bearer \(token)" else { return (401, "text/plain", Data("нет доступа".utf8), [:]) }
        let segments = path.dropFirst("/files/".count).split(separator: "/", omittingEmptySubsequences: false).map { String($0).removingPercentEncoding ?? String($0) }
        guard let url = resolve(segments.joined(separator: "/")) else { return (403, "text/plain", Data("Макеты лежат только в папке макетов Lumen".utf8), [:]) }
        switch method {
        case "GET", "HEAD":
            guard let d = try? Data(contentsOf: url) else { return (404, "text/plain", Data("нет файла".utf8), [:]) }
            return (200, "application/octet-stream", d, [:])
        case "PUT", "POST":
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try body.write(to: url, options: .atomic)
                return (200, "text/plain", Data("ok".utf8), [:])
            } catch {
                return (500, "text/plain", Data(error.localizedDescription.utf8), [:])
            }
        default:
            return (405, "text/plain", Data(), [:])
        }
    }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "wasm": "application/wasm"
        case "json", "webmanifest": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "ico": "image/x-icon"
        case "ttf": "font/ttf"
        case "otf": "font/otf"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "txt", "md": "text/plain; charset=utf-8"
        case "fig": "application/octet-stream"
        default: "application/octet-stream"
        }
    }
}
