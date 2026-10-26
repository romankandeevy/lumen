import Foundation
import LumenProviders
import Observation

/// Вход на сайт, сохранённый человеком. Пароль лежит только в Связке ключей (Keychain.swift), здесь — кто и куда.
/// Агент пароля не видит: он говорит «войди», а Lumen сам подставляет данные в поля страницы.
struct SavedLogin: Codable, Identifiable, Hashable {
    var id: String
    /// Сайт без «www.»: «github.com». Подходит и поддомен (gist.github.com)
    var host: String
    var username: String
    /// Подпись, если на сайте несколько входов («рабочий», «личный»)
    var label = ""
    /// Агент, дойдя до страницы входа, жмёт «Войти» сам; выключено — только подставляет
    var autoSubmit = true
    var lastUsed: Date?

    var title: String { label.isEmpty ? username : "\(label) · \(username)" }
}

/// Данные, которые человек ввёл при входе на странице: Lumen предлагает их сохранить
struct CapturedLogin: Equatable, Identifiable {
    let id = UUID()
    let host: String
    let username: String
    let password: String
    /// Пароль у этого входа уже сохранён, но другой — «Обновить»
    var update: Bool
}

@MainActor @Observable
final class BrowserVault {
    private(set) var logins: [SavedLogin] = []
    /// Сайты, где человек сказал «не предлагать сохранить»
    private(set) var neverSave: [String] = []

    @ObservationIgnored private let keychain: Keychain
    @ObservationIgnored var persist: (_ logins: [SavedLogin], _ never: [String]) -> Void

    init(keychain: Keychain = Keychain(), persist: @escaping ([SavedLogin], [String]) -> Void = { _, _ in }) {
        self.keychain = keychain
        self.persist = persist
    }

    func load(logins: [SavedLogin], never: [String]) {
        self.logins = logins
        neverSave = never
    }

    private static func account(_ id: String) -> String { "browser-login/" + id }

    /// Сайт без «www.» и в нижнем регистре
    nonisolated static func normalize(_ host: String) -> String {
        var h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: h), let uh = u.host, h.contains("://") { h = uh }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        return h
    }

    /// Сохранённый сайт подходит странице: тот же хост или его поддомен (но не «evilgithub.com» и не «github.com.evil.ru»)
    nonisolated static func siteMatches(saved: String, page: String) -> Bool {
        let s = normalize(saved), p = normalize(page)
        guard !s.isEmpty, !p.isEmpty else { return false }
        return p == s || p.hasSuffix("." + s)
    }

    /// Подставлять можно только на защищённых страницах (и на localhost для своих проектов)
    nonisolated static func safeToFill(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if url.scheme == "https" { return true }
        return url.scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".localhost"))
    }

    func matches(host: String) -> [SavedLogin] {
        logins.filter { Self.siteMatches(saved: $0.host, page: host) }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    func has(host: String) -> Bool { !matches(host: host).isEmpty }

    func password(for login: SavedLogin) -> String? { keychain.read(Self.account(login.id)) }

    @discardableResult
    func add(host: String, username: String, password: String, label: String = "") throws -> SavedLogin {
        let h = Self.normalize(host)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var login: SavedLogin
        if let i = logins.firstIndex(where: { $0.host == h && $0.username == user }) {
            login = logins[i]
            if !label.isEmpty { login.label = label }
            try keychain.save(password, for: Self.account(login.id))
            logins[i] = login
        } else {
            login = SavedLogin(id: UUID().uuidString, host: h, username: user, label: label)
            try keychain.save(password, for: Self.account(login.id))
            logins.append(login)
        }
        neverSave.removeAll { $0 == h }
        persist(logins, neverSave)
        return login
    }

    func remove(_ id: String) {
        keychain.delete(Self.account(id))
        logins.removeAll { $0.id == id }
        persist(logins, neverSave)
    }

    func setAutoSubmit(_ id: String, _ on: Bool) {
        guard let i = logins.firstIndex(where: { $0.id == id }) else { return }
        logins[i].autoSubmit = on
        persist(logins, neverSave)
    }

    func used(_ id: String) {
        guard let i = logins.firstIndex(where: { $0.id == id }) else { return }
        logins[i].lastUsed = Date()
        persist(logins, neverSave)
    }

    func never(host: String) {
        let h = Self.normalize(host)
        guard !neverSave.contains(h) else { return }
        neverSave.append(h)
        persist(logins, neverSave)
    }

    /// Предложить сохранить то, что человек ввёл: nil — не предлагать (уже сохранено, сайт в «никогда», пустой пароль)
    func offer(host: String, username: String, password: String) -> CapturedLogin? {
        let h = Self.normalize(host)
        guard !h.isEmpty, password.count >= 1, !neverSave.contains(h) else { return nil }
        // обновить можно только вход этого же сайта: поддомен не переписывает пароль основного
        if let existing = logins.first(where: { $0.host == h && $0.username == username }) {
            return self.password(for: existing) == password ? nil : CapturedLogin(host: existing.host, username: username, password: password, update: true)
        }
        return CapturedLogin(host: h, username: username, password: password, update: false)
    }

    /// Пароли не должны попасть к модели ни в одном ответе: любой сохранённый пароль в тексте заменяется точками
    func redact(_ text: String) -> String {
        guard !logins.isEmpty, !text.isEmpty else { return text }
        var out = text
        for l in logins {
            guard let pw = password(for: l), pw.count >= 4 else { continue }
            // как есть, в адресе (%-кодировка) и в JSON (с экранированием)
            var forms: Set<String> = [pw]
            if let enc = pw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { forms.insert(enc) }
            if let enc = pw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { forms.insert(enc) }
            if let d = try? JSONSerialization.data(withJSONObject: [pw]), let j = String(data: d, encoding: .utf8) { forms.insert(String(j.dropFirst(2).dropLast(2))) }
            for f in forms where f.count >= 4 { out = out.replacingOccurrences(of: f, with: "••••••••") }
        }
        return out
    }

    /// Адрес без того, что похоже на пароль или ключ в параметрах (?password=…, ?token=…) — для истории и ответов модели
    nonisolated static func scrubURL(_ s: String) -> String {
        guard var c = URLComponents(string: s), let items = c.queryItems, !items.isEmpty else { return s }
        let secret = ["pass", "password", "passwd", "pwd", "secret", "token", "access_token", "auth", "code", "otp", "key", "apikey", "api_key"]
        guard items.contains(where: { secret.contains($0.name.lowercased()) }) else { return s }
        c.queryItems = items.map { secret.contains($0.name.lowercased()) ? URLQueryItem(name: $0.name, value: "•••") : $0 }
        return c.string ?? s
    }
}
