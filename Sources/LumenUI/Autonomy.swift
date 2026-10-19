import AppKit
import CoreGraphics
import Foundation
import LumenCore

/// Рядом ли человек: сколько без мыши и клавиатуры и не заблокирован ли экран (Presence в LumenCore решает, «отошёл» ли)
enum PresenceProbe {
    static var idle: TimeInterval {
        let kinds: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .flagsChanged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    static var screenLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) == true || (d["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}

extension AppModel {
    /// Человек отошёл от компьютера (5 минут без мыши и клавиатуры или экран заблокирован)
    var away: Bool { Presence.isAway(idle: PresenceProbe.idle, screenLocked: PresenceProbe.screenLocked) }

    /// Файл ночи для стража готовности: до какого времени спит человек (ISO 8601)
    var nightFile: URL { paths.run.appendingPathComponent("night") }

    /// «Ночь»: до утра агент работает сам — без вопросов и разрешений, Мак не спит, утром — отчёт
    func startNight() {
        update { $0.night.until = Night.nextWake($0.night.wake, after: Date()) }
        syncNight()
        chat.nightStarted()
        log("Ночь до \(prefs.night.until.map { Night.clock($0) } ?? "?")")
    }

    /// Ночь кончилась: утром (по будильнику) — сообщение агентам; выключили руками — просто день
    func endNight(morning: Bool) {
        update { $0.night.until = nil }
        syncNight()
        if morning { chat.morning(prefs.night.morning) } else { chat.nightConversations = [] }
        log(morning ? "Утро: агентам отправлено «заверши и напиши отчёт»" : "Ночь выключена")
    }

    /// Привести всё в соответствие с настройкой: файл для стража, «не засыпать», будильник. И при запуске Lumen
    func syncNight() {
        let fm = FileManager.default
        nightTimer?.cancel()
        nightTimer = nil
        guard let until = prefs.night.until else {
            try? fm.removeItem(at: nightFile)
            if let a = nightActivity { ProcessInfo.processInfo.endActivity(a); nightActivity = nil }
            return
        }
        // Lumen был закрыт, а утро уже наступило — просто день
        guard until > Date() else {
            update { $0.night.until = nil }
            syncNight()
            return
        }
        try? fm.createDirectory(at: paths.run, withIntermediateDirectories: true)
        try? ISO8601DateFormatter().string(from: until).write(to: nightFile, atomically: true, encoding: .utf8)
        if prefs.night.keepAwake, nightActivity == nil {
            nightActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                                                                  reason: "Lumen: ночью агент работает сам")
        } else if !prefs.night.keepAwake, let a = nightActivity {
            ProcessInfo.processInfo.endActivity(a)
            nightActivity = nil
        }
        nightTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.prefs.night.until == until else { return }
            self.endNight(morning: true)
        }
    }
}
