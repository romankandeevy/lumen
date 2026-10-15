import AppKit
import Foundation
import LumenCore
import LumenProviders
import LumenStorage
import Observation

/// Состояние приложения для интерфейса. Сервисы (claude, API, база) живут ниже, сюда приходят готовые ответы.
@MainActor @Observable
public final class AppModel {
    let paths: AppPaths
    let store: Store
    let keychain = Keychain()

    var profile: Profile
    var prefs: Preferences
    var orb: Orb.State = .idle

    // MARK: подписка
    enum ClaudeState: Equatable {
        case checking
        case notInstalled
        case tooOld(Version)
        case signedOut(Version)
        case signedIn(Version, ClaudeCLI.AuthStatus)
        case failed(String)
    }

    var claude: ClaudeState = .checking
    var usage: [UsageWindow] = []
    var usageError: String?
    var subscriptionBusy = false
    /// Итог «Проверить»: настоящий короткий ход через claude
    var subscriptionCheck: String?
    private(set) var cli: ClaudeCLI?

    /// Opus 5.5 в CLI работает только с этой версии (docs/spikes.md)
    static let opus55Version = Version(2, 1, 280)

    // MARK: ключ API
    enum KeyState: Equatable {
        case none, saved, checking, ok, rejected, noNetwork, error(String)
    }

    var keyState: KeyState = .none
    /// Последние 4 знака сохранённого ключа — чтобы узнать его, не показывая
    var savedKeyTail: String?

    public init(paths: AppPaths = .standard) throws {
        try paths.create()
        self.paths = paths
        store = try Store(path: paths.database)
        profile = store.profile
        prefs = store.preferences
        if let key = keychain.read(Keychain.anthropicKey) {
            savedKeyTail = String(key.suffix(4))
            keyState = .saved
        }
    }

    // MARK: настройки

    func update(_ change: (inout Preferences) -> Void) {
        change(&prefs)
        try? store.set("preferences", prefs)
    }

    /// Знакомство: имя и обращение — первые факты о человеке
    func finishOnboarding(name: String, address: Address, backend: Backend, theme: Theme) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = Profile(name: name, address: address)
        try? store.set("profile", profile)
        if !name.isEmpty {
            _ = try? store.upsert(MemoryFact(kind: "name", text: "Зовут \(name)", source: "onboarding", pinned: true))
        }
        _ = try? store.upsert(MemoryFact(kind: "address", text: address == .ty ? "Обращаться на «ты»" : "Обращаться на «вы»",
                                     source: "onboarding", pinned: true))
        update {
            $0.onboarded = true
            $0.backend = backend
            $0.theme = theme
        }
        flash()
    }

    func restartOnboarding() {
        update { $0.onboarded = false }
    }

    /// Сфера вспыхивает: «запомнил»
    func flash() {
        orb = .remember
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            orb = .idle
        }
    }

    // MARK: подписка

    func refreshClaude() async {
        claude = .checking
        guard let cli = ClaudeCLI.locate() else {
            self.cli = nil
            claude = .notInstalled
            return
        }
        self.cli = cli
        do {
            let v = try await cli.version()
            guard v >= ClaudeCLI.minimumVersion else {
                claude = .tooOld(v)
                return
            }
            let auth = try await cli.authStatus()
            claude = auth.loggedIn ? .signedIn(v, auth) : .signedOut(v)
            if auth.loggedIn { await refreshUsage() }
        } catch {
            claude = .failed(error.localizedDescription)
        }
    }

    func refreshUsage() async {
        guard let cli else { return }
        do {
            usage = try await cli.usage()
            usageError = usage.isEmpty ? "Claude Code не показал лимиты" : nil
        } catch {
            usageError = error.localizedDescription
        }
    }

    func signIn() async {
        guard let cli else { return }
        subscriptionBusy = true
        defer { subscriptionBusy = false }
        do { try await cli.login() } catch { claude = .failed(error.localizedDescription) }
        await refreshClaude()
    }

    func signOut() async {
        guard let cli else { return }
        subscriptionBusy = true
        defer { subscriptionBusy = false }
        do { try await cli.logout() } catch { claude = .failed(error.localizedDescription) }
        usage = []
        await refreshClaude()
    }

    /// «Проверить»: обновить вход и лимиты и сделать настоящий короткий ход через подписку
    func checkSubscription() async {
        subscriptionBusy = true
        subscriptionCheck = nil
        defer { subscriptionBusy = false }
        await refreshClaude()
        guard case .signedIn = claude, let cli else { return }
        let started = Date()
        do {
            let session = try ClaudeSession(cli: cli, config: .init(model: "claude-haiku-5-5",
                                                                    systemPrompt: "Ответь одним словом: «готов»."))
            defer { session.close() }
            let r = try await session.ask("Проверка связи")
            let secs = Date().timeIntervalSince(started).formatted(.number.precision(.fractionLength(1)))
            subscriptionCheck = r.ok ? "Подписка отвечает: ответ за \(secs) с" : "Claude Code ответил ошибкой: \(r.text)"
        } catch {
            subscriptionCheck = "Не получилось: \(error.localizedDescription)"
        }
    }

    // MARK: ключ API

    func checkKey(_ typed: String) async {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = key.isEmpty ? keychain.read(Keychain.anthropicKey) : key
        guard let candidate, !candidate.isEmpty else {
            keyState = .none
            return
        }
        guard AnthropicAPI.looksValid(candidate) else {
            keyState = .rejected
            return
        }
        keyState = .checking
        switch await AnthropicAPI(key: candidate).check() {
        case .ok:
            do {
                try keychain.save(candidate, for: Keychain.anthropicKey)
                savedKeyTail = String(candidate.suffix(4))
                keyState = .ok
            } catch {
                keyState = .error(error.localizedDescription)
            }
        case .rejected: keyState = .rejected
        case .noNetwork: keyState = .noNetwork
        case .other(let m): keyState = .error(m)
        }
    }

    func forgetKey() {
        keychain.delete(Keychain.anthropicKey)
        savedKeyTail = nil
        keyState = .none
    }

    // MARK: данные

    func showDataInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.database])
    }
}
