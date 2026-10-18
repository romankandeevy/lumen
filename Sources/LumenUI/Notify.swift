import AppKit
import LumenCore
import ServiceManagement
import UserNotifications

// Настройки → Общие (Рома, 18.10): ответ готов, а Lumen в фоне — уведомление и звук; Lumen открывается при входе в систему.

extension AppModel {
    /// Системные звуки на выбор: пусто — без звука
    static let doneSounds: [(String, String)] = [("", "Без звука"), ("Glass", "Стекло"), ("Ping", "Пинг"), ("Pop", "Хлопок"), ("Tink", "Тинь"), ("Hero", "Фанфары")]

    /// Ответ готов: если Lumen не на переднем плане — звук и уведомление с началом ответа (как выбрано в настройках)
    func answerReady(_ c: Conversation, text: String) {
        guard !NSApplication.shared.isActive else { return }
        if !prefs.doneSound.isEmpty { NSSound(named: NSSound.Name(prefs.doneSound))?.play() }
        guard prefs.notifyWhenDone, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let content = UNMutableNotificationContent()
        content.title = c.title
        content.body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "done-\(c.id)", content: content, trigger: nil))
    }

    /// Включить уведомления: macOS один раз спросит разрешение. false — не разрешили
    func allowNotifications() async -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Открывать Lumen при входе в систему. nil — получилось, иначе — что сказать человеку
    static func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return "Не получилось: \(error.localizedDescription)"
        }
        if on && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Разреши Lumen в Системных настройках → Основные → Объекты входа"
        }
        return nil
    }
}
