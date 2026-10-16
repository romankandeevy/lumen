import AppKit
import Observation
import Sparkle

/// Автообновление через Sparkle (техплан §10.3, docs/versions.md).
/// Лента — `appcast.xml` в репозитории, каждая версия подписана EdDSA. Стабильный канал по умолчанию,
/// бета (пререлизы 1.0.1, 1.0.2 …) — если включена в настройках.
/// Работает только в собранном приложении: без `SUFeedURL` в Info.plist (swift run, тесты) его нет вовсе.
@MainActor @Observable
final class Updater: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    /// Бета-канал: читается Sparkle при каждой проверке
    @ObservationIgnored var beta: () -> Bool = { false }
    private(set) var canCheck = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    static func make() -> Updater? {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return Updater()
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] u, _ in
            let v = u.canCheckForUpdates
            Task { @MainActor in self?.canCheck = v }
        }
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var automatic: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    func check() { controller.checkForUpdates(nil) }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { beta() ? ["beta"] : [] }
    }
}
