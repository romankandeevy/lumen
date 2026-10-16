import AppKit
import CryptoKit
import Foundation
import LumenCore
import Network

/// Вход в сайт MCP через браузер — как кнопка «Подключить» в Claude (спецификация авторизации MCP):
/// 401 → метаданные ресурса → сервер авторизации → регистрация клиента (DCR) → браузер с PKCE →
/// ответ на 127.0.0.1 → токены. Токены хранит вызывающий (Связка ключей), продление — `refresh`.
public enum MCPOAuth {
    public struct Tokens: Codable, Sendable, Equatable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?
        public var clientID: String
        public var clientSecret: String?
        public var tokenEndpoint: String
        public var resource: String

        /// Пора продлить: осталось меньше пяти минут
        public var stale: Bool { expiresAt.map { $0.timeIntervalSinceNow < 300 } ?? false }
    }

    struct Endpoints {
        let authorize: URL
        let token: URL
        let register: URL?
        let scope: String?
        let resource: String
    }

    // MARK: вход

    /// Открыть браузер и дождаться входа (до 5 минут)
    public static func login(serverURL: String, session: URLSession = .shared,
                             open: @Sendable (URL) -> Void = { url in Task { @MainActor in NSWorkspace.shared.open(url) } }) async throws -> Tokens {
        guard let server = URL(string: serverURL) else { throw MCPClient.Failure("Неверный адрес") }
        let ep = try await discover(server, session: session)
        let listener = try LoopbackListener()
        defer { listener.stop() }
        let redirect = "http://127.0.0.1:\(try await listener.start())/callback"

        // регистрация клиента (если сервер её даёт); иначе — публичный клиент «lumen»
        var clientID = "lumen"
        var clientSecret: String?
        if let reg = ep.register {
            var r = URLRequest(url: reg)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_name": "Lumen", "redirect_uris": [redirect], "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"], "token_endpoint_auth_method": "none",
            ] as [String: Any])
            let (data, resp) = try await session.data(for: r)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = obj["client_id"] as? String else {
                throw MCPClient.Failure("Сайт не дал зарегистрировать Lumen для входа")
            }
            clientID = id
            clientSecret = obj["client_secret"] as? String
        }

        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomString(24)
        var c = URLComponents(url: ep.authorize, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
            .init(name: "resource", value: ep.resource),
        ] + (ep.scope.map { [URLQueryItem(name: "scope", value: $0)] } ?? [])
        open(c.url!)

        let query = try await listener.waitForCallback(timeout: 300)
        if let err = query["error"] { throw MCPClient.Failure("Вход отменён: \(query["error_description"] ?? err)") }
        guard query["state"] == state, let code = query["code"] else { throw MCPClient.Failure("Сайт вернул неверный ответ на вход") }

        let body = ["grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "client_id": clientID,
                    "code_verifier": verifier, "resource": ep.resource]
        return try await tokenRequest(ep.token, body, clientID: clientID, clientSecret: clientSecret, resource: ep.resource, old: nil, session: session)
    }

    /// Продлить по refresh_token
    public static func refresh(_ t: Tokens, session: URLSession = .shared) async throws -> Tokens {
        guard let rt = t.refreshToken, let url = URL(string: t.tokenEndpoint) else { throw MCPClient.Failure("Нужно войти заново") }
        return try await tokenRequest(url, ["grant_type": "refresh_token", "refresh_token": rt, "client_id": t.clientID, "resource": t.resource],
                                      clientID: t.clientID, clientSecret: t.clientSecret, resource: t.resource, old: t, session: session)
    }

    static func tokenRequest(_ url: URL, _ form: [String: String], clientID: String, clientSecret: String?, resource: String,
                             old: Tokens?, session: URLSession) async throws -> Tokens {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        var f = form
        if let clientSecret { f["client_secret"] = clientSecret }
        r.httpBody = f.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .formValue) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: r)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let access = obj["access_token"] as? String else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw MCPClient.Failure(old == nil ? "Сайт не выдал доступ (\(code))" : "Доступ истёк — войди заново")
        }
        let expires = (obj["expires_in"] as? Double ?? (obj["expires_in"] as? Int).map(Double.init)).map { Date().addingTimeInterval($0) }
        return Tokens(accessToken: access, refreshToken: obj["refresh_token"] as? String ?? old?.refreshToken, expiresAt: expires,
                      clientID: clientID, clientSecret: clientSecret, tokenEndpoint: url.absoluteString, resource: resource)
    }

    // MARK: где входить

    static func discover(_ server: URL, session: URLSession) async throws -> Endpoints {
        let origin = URL(string: "\(server.scheme ?? "https")://\(server.host ?? "")\(server.port.map { ":\($0)" } ?? "")")!
        // 1. 401 подсказывает, где описан ресурс
        var metaURL: URL?
        var scope: String?
        var probe = URLRequest(url: server)
        probe.httpMethod = "POST"
        probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
        probe.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        probe.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"Lumen","version":"1"}}}"#.utf8)
        if let (_, resp) = try? await session.data(for: probe), let h = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "WWW-Authenticate") {
            metaURL = param("resource_metadata", in: h).flatMap(URL.init(string:))
            scope = param("scope", in: h)
        }
        // 2. метаданные ресурса → сервер авторизации
        var authServer = origin
        var resource = origin.absoluteString
        let candidates = [metaURL, URL(string: origin.absoluteString + "/.well-known/oauth-protected-resource" + server.path),
                          URL(string: origin.absoluteString + "/.well-known/oauth-protected-resource")].compactMap { $0 }
        for u in candidates {
            if let obj = try? await json(u, session) {
                if let a = (obj["authorization_servers"] as? [String])?.first, let au = URL(string: a) { authServer = au }
                if let r = obj["resource"] as? String { resource = r }
                if scope == nil, let s = obj["scopes_supported"] as? [String], !s.isEmpty { scope = s.joined(separator: " ") }
                break
            }
        }
        // 3. метаданные сервера авторизации
        let base = authServer.absoluteString.hasSuffix("/") ? String(authServer.absoluteString.dropLast()) : authServer.absoluteString
        let asOrigin = "\(authServer.scheme ?? "https")://\(authServer.host ?? "")\(authServer.port.map { ":\($0)" } ?? "")"
        let path = authServer.path == "/" ? "" : authServer.path
        for s in [asOrigin + "/.well-known/oauth-authorization-server" + path, base + "/.well-known/oauth-authorization-server",
                  asOrigin + "/.well-known/openid-configuration" + path, base + "/.well-known/openid-configuration"] {
            guard let u = URL(string: s), let obj = try? await json(u, session),
                  let a = (obj["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
                  let t = (obj["token_endpoint"] as? String).flatMap(URL.init(string:)) else { continue }
            return Endpoints(authorize: a, token: t, register: (obj["registration_endpoint"] as? String).flatMap(URL.init(string:)),
                             scope: scope, resource: resource)
        }
        // старые серверы: стандартные пути от корня
        return Endpoints(authorize: URL(string: asOrigin + "/authorize")!, token: URL(string: asOrigin + "/token")!,
                         register: URL(string: asOrigin + "/register"), scope: scope, resource: resource)
    }

    static func json(_ u: URL, _ session: URLSession) async throws -> [String: Any] {
        let (data, resp) = try await session.data(from: u)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClient.Failure("нет")
        }
        return obj
    }

    static func param(_ name: String, in header: String) -> String? {
        guard let r = header.range(of: name + "=\"") else { return nil }
        let rest = header[r.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let formValue: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()
}

/// Однократный приёмник ответа браузера на 127.0.0.1
final class LoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "lumen.oauth")
    private var ready: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?
    private let lock = NSLock()

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { c in
            ready = c
            listener.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                switch st {
                case .ready: if let c = self.ready { self.ready = nil; c.resume(returning: self.listener.port?.rawValue ?? 0) }
                case .failed(let e): if let c = self.ready { self.ready = nil; c.resume(throwing: e) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let line = text.split(separator: "\r\n").first.map(String.init) ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let isCallback = path.hasPrefix("/callback")
            let html = isCallback
                ? "<html><body style=\"font:16px -apple-system;padding:48px;background:#111;color:#eee\"><h2>Готово</h2><p>Вход выполнен — вернись в Lumen.</p></body></html>"
                : "<html><body>Lumen</body></html>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(html.utf8.count)\r\n\r\n" + html
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            guard isCallback, let self else { return }
            var q: [String: String] = [:]
            for item in URLComponents(string: "http://x" + path)?.queryItems ?? [] { q[item.name] = item.value ?? "" }
            self.finish(.success(q))
        }
    }

    private func finish(_ r: Result<[String: String], Error>) {
        lock.lock()
        let c = callback
        callback = nil
        if c == nil, result == nil { result = r }
        lock.unlock()
        c?.resume(with: r)
    }

    func waitForCallback(timeout: Double) async throws -> [String: String] {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { self?.finish(.failure(MCPClient.Failure("Вход не завершён за \(Int(timeout / 60)) мин"))) }
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { c in
            lock.lock()
            if let r = result { lock.unlock(); c.resume(with: r); return }
            callback = c
            lock.unlock()
        }
    }

    func stop() { listener.cancel() }
}
