import Foundation

// Самостоятельная работа агента (Рома, 19.10): «хочу дать задачу и быть уверенным, что он доведёт её до хорошего
// результата без меня». Здесь — правила без интерфейса: ночь, «рядом ли человек», лимиты, записка-передача при сжатии.

/// Режим «Ночь»: человек спит, агент работает сам до утра, утром — отчёт
public struct NightPrefs: Codable, Sendable, Equatable {
    /// Во сколько утро: «ЧЧ:ММ»
    public var wake = "06:00"
    /// Что Lumen сам отправит агенту утром
    public var morning = "Доброе утро. Заверши то, что делаешь сейчас, и напиши отчёт за ночь: что сделал, как проверил, что не получилось и почему, что ждёт моего решения, и план на день."
    /// Не давать Маку засыпать, пока идёт ночь
    public var keepAwake = true
    /// Лимит подписки кончился — дождаться сброса и продолжить
    public var waitForLimits = true
    /// До какого времени идёт ночь; nil — ночь выключена
    public var until: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NightPrefs()
        wake = (try? c.decodeIfPresent(String.self, forKey: .wake)) ?? d.wake
        morning = (try? c.decodeIfPresent(String.self, forKey: .morning)) ?? d.morning
        keepAwake = (try? c.decodeIfPresent(Bool.self, forKey: .keepAwake)) ?? d.keepAwake
        waitForLimits = (try? c.decodeIfPresent(Bool.self, forKey: .waitForLimits)) ?? d.waitForLimits
        until = try? c.decodeIfPresent(Date.self, forKey: .until)
    }

    /// Ночь идёт сейчас
    public func active(now: Date = Date()) -> Bool { until.map { now < $0 } ?? false }
}

public enum Night {
    /// Ближайшее «ЧЧ:ММ» после `now`: сегодня, если ещё не наступило, иначе завтра. Непонятная строка — 06:00
    public static func nextWake(_ hhmm: String, after now: Date, calendar: Calendar = .current) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let (h, m) = parts.count == 2 && (0..<24).contains(parts[0]) && (0..<60).contains(parts[1]) ? (parts[0], parts[1]) : (6, 0)
        let today = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// «06:00»
    public static func clock(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Скрытая пометка к сообщению ночью — правила к ней в AgentRules («Ночь»)
    public static func note(until: Date) -> String {
        "\n\n<lumen-night until=\"\(clock(until))\">Человек спит до \(clock(until)). Работай сам до результата, ничего у него не спрашивай.</lumen-night>"
    }

    /// Агент сказал, что всё сделал и проверил, — страж больше не будит его до утра
    public static let doneMark = "<lumen-night-done/>"
}

/// «Рядом ли человек»: спрашивать можно, только когда он за компьютером (Рома, 19.10: «если сидит у компа — можно
/// спросить; если нет — не задавай, делай сам, как хорошо»)
public enum Presence {
    /// Сколько без мыши и клавиатуры — уже «отошёл»
    public static let awayAfter: TimeInterval = 5 * 60

    public static func isAway(idle: TimeInterval, screenLocked: Bool, threshold: TimeInterval = awayAfter) -> Bool {
        screenLocked || idle >= threshold
    }

    /// Скрытая пометка к сообщению, когда человека нет
    public static let awayNote = "\n\n<lumen-presence away=\"true\">Человек сейчас не за компьютером. Не задавай вопросов — решай сам.</lumen-presence>"

    /// Что Lumen отвечает за человека, когда тот отошёл, а агент спросил
    public static let autoAnswer = "Меня сейчас нет за компьютером. Реши сам: выбери разумный вариант, продолжай и запиши допущение в отчёте. Если без меня правда нельзя (пароль, оплата, что-то необратимое) — пропусти этот шаг, сделай остальное и напиши, что ждёт меня."

    /// Ответ на запрос разрешения, когда человека нет
    public static let deniedWhileAway = "Человека нет рядом, а это действие ждёт его OK. Не делай его: пропусти, сделай остальное и напиши в отчёте, что ждёт его решения."
}

/// Лимит подписки кончился: так claude сообщает об этом в итоге хода
public enum UsageLimit {
    public static func isLimit(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.contains("usage limit") || s.contains("hit your limit") || s.contains("limit reached")
            || (s.contains("limit") && s.contains("reset")) || s.contains("лимит")
    }
}

/// Свой автокомпакт (Рома, 19.10): «чтобы он всё помнил, а контекст стирался». Когда окно заполнено, агент сам пишет
/// записку-передачу (у него в голове весь разговор, вместе с выводом команд), Lumen сохраняет её у себя и начинает
/// свежую сессию claude: записка уходит первым скрытым сообщением. Что сжимать — решает Lumen, а не claude.
public enum Handoff {
    /// Сжимать, когда занято столько от окна…
    public static let defaultPercent = 70
    /// …но не позже этого: длинный контекст отвечает медленнее и хуже держит главное, даже если окно в 1 млн
    public static let tokenCap = 400_000

    public static func due(used: Int, window: Int, percent: Int) -> Bool {
        guard used > 0, window > 0 else { return false }
        return used >= min(window * max(10, min(percent, 95)) / 100, tokenCap)
    }

    /// Просьба написать записку: скрытое сообщение в ту же сессию
    public static let request = """
        <lumen-handoff-request>
        Окно контекста почти заполнено. Lumen начнёт с тобой свежий разговор, и прошлого ты помнить не будешь — останется только записка, которую ты сейчас напишешь. Напиши её для себя же, чтобы продолжить работу без потерь. Ничего не запускай и не правь, только записка. Без вступления и без блока <lumen-next>.

        Разделы (заголовки ##):
        ## Задача — что просил человек, дословно главное; цель и критерии готовности.
        ## Что сделано — по шагам: какие файлы, функции, команды; что получилось.
        ## Решения — что выбрали и почему; что пробовали и отбросили.
        ## Как проверено — какие сборки, тесты, проверки и с каким результатом; что не проверено.
        ## Сейчас — на чём остановились, что открыто, план дальше по пунктам.
        ## Важные детали — точные пути, команды, имена, ошибки, адреса, договорённости и предпочтения человека.
        ## Последние сообщения человека — дословно, начиная с последнего.

        Пиши плотно, без воды, до 2500 слов. Точные пути и имена — без сокращений.
        </lumen-handoff-request>
        """

    /// Первое скрытое сообщение свежей сессии: записка
    public static func prefix(_ note: String) -> String {
        """
        <lumen-handoff>
        Это продолжение работы. Прошлый разговор Lumen сжал: ниже — твоя же записка-передача. Опирайся на неё как на свою память. \
        Нужна деталь, которой здесь нет, — поищи в прошлых разговорах (recall) или в файлах проекта, а не спрашивай человека.

        \(note.trimmingCharacters(in: .whitespacesAndNewlines))
        </lumen-handoff>


        """
    }
}
