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

    // MARK: окно
    enum Page: Equatable { case chat, memory, settings(SettingsView.Section) }

    var page: Page = .chat
    /// Вся память — для страницы «Что Lumen знает», счётчика и плашек в чате
    var memories: [MemoryFact] = []
    /// Последний забытый факт — чтобы «Вернуть»
    var lastForgotten: MemoryFact?
    /// Вкладка панели: Чат или Агент
    enum Tab { case chat, agent }
    var tab: Tab = .chat
    /// Папка для новой задачи агента
    var agentFolder: URL?
    var conversations: [Conversation] = []
    @ObservationIgnored private(set) lazy var chat = ChatController(app: self)

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
        conversations = (try? store.conversations()) ?? []
        memories = (try? store.memories()) ?? []
        agentFolder = prefs.recentFolders.lazy.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: разговоры

    /// Агент по умолчанию думает Opus на высоком уровне, как в макете; если Opus недоступен — Sonnet
    var defaultAgentModel: ChatModel {
        availableModels(for: .subscription).contains(.opus) ? .opus : .sonnet
    }

    func rememberFolder(_ url: URL) {
        update {
            $0.recentFolders.removeAll { $0 == url.path }
            $0.recentFolders.insert(url.path, at: 0)
            $0.recentFolders = Array($0.recentFolders.prefix(8))
        }
    }

    var recentFolders: [URL] {
        prefs.recentFolders.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Папка проекта для агента"
        if panel.runModal() == .OK, let url = panel.url {
            agentFolder = url
            rememberFolder(url)
        }
    }

    func newAgentTask() {
        tab = .agent
        chat.startNew()
        page = .chat
    }

    /// Сколько фактов помнит Lumen — для пустого чата и счётчика в панели
    var memoryCount: Int { memories.count }

    func reloadConversations() {
        conversations = (try? store.conversations()) ?? []
    }

    func openChat(_ c: Conversation) {
        tab = c.kind == .agent ? .agent : .chat
        chat.open(c)
        page = .chat
    }

    func newChat() {
        if tab == .agent { return newAgentTask() }
        chat.startNew()
        page = .chat
    }

    func deleteChat(_ c: Conversation) {
        if chat.conversation?.id == c.id { chat.startNew() }
        try? store.deleteConversation(c.id)
        reloadConversations()
    }

    /// Модели, которые сейчас реально работают с выбранным движком.
    /// Opus 5.5 через подписку требует claude 2.1.280+ (docs/spikes.md).
    func availableModels(for backend: Backend) -> [ChatModel] {
        guard backend == .subscription, case .signedIn(let v, _) = claude, v < Self.opus55Version else {
            return ChatModel.allCases
        }
        return ChatModel.allCases.filter { $0 != .opus }
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
            _ = try? store.save(MemoryFact(kind: .you, text: "Зовут \(name)", source: "Знакомство", key: "onboarding.name", pinned: true))
        }
        _ = try? store.save(MemoryFact(kind: .pref, text: address == .ty ? "Обращаться на «ты»" : "Обращаться на «вы»",
                                       source: "Знакомство", key: "onboarding.address", pinned: true))
        reloadMemories()
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
