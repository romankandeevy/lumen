import Foundation

// Доменные типы Lumen. Здесь только то, что уже используется.

/// Как обращаться к человеку
public enum Address: String, Codable, Sendable, CaseIterable {
    case ty, vy
}

/// Через что Lumen думает
public enum Backend: String, Codable, Sendable, CaseIterable {
    /// Подписка через установленный у пользователя `claude`
    case subscription
    /// Ключ Anthropic API
    case api
}

/// Тема окна: «Люмен» и «Монохром» тёмные, «Светлая», и своя (основа, цвет, окраска фона)
public enum Theme: String, Codable, Sendable, CaseIterable {
    case lumen, mono, light, custom
}

/// Своя тема: тёмная или светлая основа, оттенок акцента 0…360, насколько окрашен фон 0…1
public struct CustomTheme: Codable, Sendable, Equatable {
    public var dark: Bool
    public var hue: Double
    public var tint: Double

    public init(dark: Bool = true, hue: Double = 210, tint: Double = 0.5) {
        self.dark = dark
        self.hue = hue
        self.tint = tint
    }
}

/// Свет приложения: светлое, тёмное или как в системе. Тема держит цвета для обоих, свет выбирает, какие
public enum Appearance: String, Codable, Sendable, CaseIterable {
    case light, dark, system
}

/// Своя тема (26.10): копия готовой (`base`) со своими цветами для темноты и для света. Готовые темы не меняются —
/// цвета правятся только у своих. Старые свои темы (до 26.10) без основы считаются от оттенка `hue` и окраски `tint`
public struct UserTheme: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var hue: Double
    public var tint: Double
    /// Готовая тема, от которой сделана: «lumen», «mono», «corona», «aurora»
    public var base: String?
    /// Свои цвета поверх основы
    public var darkColors: ThemeOverrides?
    public var lightColors: ThemeOverrides?

    public init(id: String = "user-" + UUID().uuidString.lowercased().prefix(8), name: String, hue: Double = 210, tint: Double = 0.4,
                base: String? = nil, darkColors: ThemeOverrides? = nil, lightColors: ThemeOverrides? = nil) {
        self.id = id
        self.name = name
        self.hue = hue
        self.tint = tint
        self.base = base
        self.darkColors = darkColors
        self.lightColors = lightColors
    }

    public func colors(dark: Bool) -> ThemeOverrides { (dark ? darkColors : lightColors) ?? ThemeOverrides() }
}

/// Свои цвета поверх темы (hex «#RRGGBB»): акцент, фон, текст. Свои для светлого и тёмного света
public struct ThemeOverrides: Codable, Sendable, Equatable, Hashable {
    public var accent: String?
    public var background: String?
    public var foreground: String?
    /// Карточки, шаги, файлы — «поверхность» над фоном
    public var surface: String?
    public init(accent: String? = nil, background: String? = nil, foreground: String? = nil, surface: String? = nil) {
        self.accent = accent
        self.background = background
        self.foreground = foreground
        self.surface = surface
    }
    public var isEmpty: Bool { accent == nil && background == nil && foreground == nil && surface == nil }
}

/// «Меньше движения»: как в системе, всегда или никогда
public enum MotionPref: String, Codable, Sendable, CaseIterable { case system, on, off }

/// Как показывать разницу правок: цветом строк или только знаками +/−
public enum DiffMarkers: String, Codable, Sendable, CaseIterable { case color, signs }

/// Шрифт текста переписки (Настройки → Шрифты и масштаб)
public enum ChatFont: String, Codable, Sendable, CaseIterable {
    case geist, system, serif, mono
}

/// Где открываются ссылки из переписки: в браузере сбоку или в браузере Мака по умолчанию (Chrome, Safari…)
public enum LinkTarget: String, Codable, Sendable, CaseIterable {
    case side, system
}

/// Ширина переписки: чат, агент и боты (`chatWidthClass` в макете)
public enum ChatWidth: String, Codable, Sendable, CaseIterable {
    case normal, wide, full

    /// max-w-[44rem] / [60rem] / [88rem] + 16 pt: слева теперь поле под знак (Рома, 22.10), а сам текст остаётся прежней ширины
    public var points: Double {
        switch self { case .normal: 736; case .wide: 976; case .full: 1424 }
    }
}

/// Кто пользуется Lumen — из знакомства
public struct Profile: Codable, Sendable, Equatable {
    public var name: String
    public var address: Address

    public init(name: String = "", address: Address = .ty) {
        self.name = name
        self.address = address
    }
}

/// Настройки, которые хранятся в базе
public struct Preferences: Codable, Sendable, Equatable {
    public var onboarded: Bool
    public var backend: Backend
    public var theme: Theme
    /// Настройки своей темы (используются, когда theme == .custom)
    public var customTheme = CustomTheme()
    /// Выбранная тема: встроенная («lumen», «mono», …) или своя (id из `userThemes`)
    public var themeID = "lumen"
    /// Свет: светлый, тёмный или как в системе — тема подстраивается
    public var appearance = Appearance.dark
    /// Свои темы
    public var userThemes: [UserTheme] = []
    /// Текст переписки: шрифт и масштаб (1 = 15 pt)
    public var chatFont = ChatFont.geist
    public var textScale: Double = 1
    /// Браузер выезжает сам, когда агент открывает страницу или показывает макет
    public var browserAutoOpen = true
    /// Ссылки из переписки — в браузер сбоку или в свой (Рома, 18.10). ⌘-клик — в другое место
    public var linkTarget = LinkTarget.side
    /// Свои цвета поверх темы: ключ — «id темы|light» или «id темы|dark»
    public var themeOverrides: [String: ThemeOverrides] = [:]
    /// Раздельные темы для светлого и тёмного света: тёмный берёт `darkThemeID`
    public var separateModes = false
    public var darkThemeID: String?
    /// Размер шрифта интерфейса (база 14) и кода (база 12.5)
    public var uiFontSize: Double = 14
    public var codeFontSize: Double = 12.5
    public var motion = MotionPref.system
    /// Контраст 0…100: 50 — как задумано, больше — резче линии и подписи
    public var contrast: Double = 50
    public var diffMarkers = DiffMarkers.color
    /// Правая панель блоками, как в Claude: порядок, убранные и свёрнутые блоки
    public var panelOrder: [String] = ["plan", "session", "memory", "context", "usage"]
    public var panelHidden: [String] = []
    public var panelCollapsed: [String] = []
    public var reducedMotion: Bool
    /// Последние выбранные в чате модель и «сколько думать» — для нового чата
    public var model: ChatModel
    public var effort: Effort
    public var chatWidth: ChatWidth
    /// Папки, где недавно работал агент — первая выбрана для новой задачи
    public var recentFolders: [String] = []
    /// «Запоминать само»: Lumen сам сохраняет важное из разговора, а не только по просьбе «запомни»
    public var autoRemember = true
    /// «Поиск в сети» (меню «+»): Lumen и агент могут искать в интернете и открывать страницы. По умолчанию включён
    public var webSearch = true
    /// «Память о тебе» (меню «+»): Lumen знает твои факты и дополняет их. Выключена — не читает и не записывает. По умолчанию включена
    public var useMemory = true
    /// Фон главной области: зерно, звёзды и лучи короны (Sky). Выключен — ровный цвет темы
    public var skyBackground = true
    /// Предохранитель API: не тратить больше стольких долларов в месяц (§18.3: $100, что входят в Max)
    public var monthlyLimit = 100
    /// Правая панель «Контекст» открыта
    public var contextOpen = false
    /// Левая панель спрятана (кнопка рядом с кнопками окна, как в Claude)
    public var sidebarHidden = false
    /// Ширина левой панели и правой (контекст, паспорт бота) — тянутся за край, не шире половины окна
    public var sidebarWidth: Double = 284
    public var panelWidth: Double = 320
    /// Модель и «сколько думать» для новой задачи агента (у чата — `model` и `effort`)
    public var agentModel: ChatModel?
    public var agentEffort: Effort?
    /// Режим новой задачи агента
    public var agentMode: AgentMode = .auto
    /// Ключи Anthropic API: имена и последние знаки (сами ключи — в Связке ключей); какой используется
    public var apiKeys: [ApiKeyEntry] = []
    public var activeKeyID: String?
    /// Режимы, которые не показывать в поле агента (Настройки → Внешний вид)
    public var hiddenModes: [AgentMode] = []
    /// Ответ готов, а Lumen не на переднем плане: уведомление и звук (пусто — без звука). Настройки → Общие
    public var notifyWhenDone = false
    public var doneSound = ""
    /// Отправка: Enter (Shift+Enter — новая строка) или ⌘Enter (Enter — новая строка)
    public var sendWithCommand = false
    /// Lumen сам ведёт PROJECT.md проектов: заполняет по папке и дописывает после ответов (тратит немного подписки)
    public var projectContextAuto = true
    /// Правила агента от человека (Настройки → Модели и оплата): идут вслед за правилами, что зашиты в Lumen. Характера у агента нет (Рома, 19.10)
    public var agentRules = ""
    /// «Страж готовности»: не даёт агенту закончить ход, пока не проверено сделанное (хук Stop у claude)
    public var agentGuard = true
    /// «Присутствие»: агент спрашивает, только когда человек за компьютером; отошёл — Lumen отвечает «реши сам»
    public var presence = true
    /// Режим «Ночь»
    public var night = NightPrefs()
    /// Автовыбор модели: запасные при перегрузке и другая модель, когда у выбранной кончился лимит на неделю
    public var autoModel = true
    /// Свой автокомпакт: при заполнении окна — записка-передача и свежая сессия
    public var autoCompact = true
    public var compactAt = Handoff.defaultPercent

    /// Режимы в поле: все, кроме скрытых; хотя бы один остаётся всегда
    public var visibleModes: [AgentMode] {
        let v = AgentMode.allCases.filter { !hiddenModes.contains($0) }
        return v.isEmpty ? [.auto] : v
    }
    /// Получать бета-версии (1.0.1, 1.0.2…), а не только стабильные
    public var betaUpdates = false
    /// Питомец (1.5): кто, поверх окон ли, вместо точек «работает» ли
    public var pet = PetPrefs()

    public init(onboarded: Bool = false, backend: Backend = .subscription, theme: Theme = .lumen, reducedMotion: Bool = false,
                model: ChatModel = .sonnet, effort: Effort = .medium, chatWidth: ChatWidth = .normal) {
        self.onboarded = onboarded
        self.backend = backend
        self.theme = theme
        self.reducedMotion = reducedMotion
        self.model = model
        self.effort = effort
        self.chatWidth = chatWidth
    }

    // старые настройки (0.1) без модели и effort читаются с умолчаниями
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        backend = try c.decodeIfPresent(Backend.self, forKey: .backend) ?? .subscription
        theme = (try? c.decodeIfPresent(Theme.self, forKey: .theme)) ?? .lumen
        customTheme = (try? c.decodeIfPresent(CustomTheme.self, forKey: .customTheme)) ?? CustomTheme()
        userThemes = (try? c.decodeIfPresent([UserTheme].self, forKey: .userThemes)) ?? []
        chatFont = (try? c.decodeIfPresent(ChatFont.self, forKey: .chatFont)) ?? .geist
        textScale = (try? c.decodeIfPresent(Double.self, forKey: .textScale)) ?? 1
        browserAutoOpen = (try? c.decodeIfPresent(Bool.self, forKey: .browserAutoOpen)) ?? true
        linkTarget = (try? c.decodeIfPresent(LinkTarget.self, forKey: .linkTarget)) ?? .side
        themeOverrides = (try? c.decodeIfPresent([String: ThemeOverrides].self, forKey: .themeOverrides)) ?? [:]
        separateModes = (try? c.decodeIfPresent(Bool.self, forKey: .separateModes)) ?? false
        darkThemeID = try? c.decodeIfPresent(String.self, forKey: .darkThemeID)
        uiFontSize = (try? c.decodeIfPresent(Double.self, forKey: .uiFontSize)) ?? 14
        codeFontSize = (try? c.decodeIfPresent(Double.self, forKey: .codeFontSize)) ?? 12.5
        contrast = (try? c.decodeIfPresent(Double.self, forKey: .contrast)) ?? 50
        diffMarkers = (try? c.decodeIfPresent(DiffMarkers.self, forKey: .diffMarkers)) ?? .color
        if let id = try? c.decodeIfPresent(String.self, forKey: .themeID) {
            themeID = id
            appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .dark
        } else {
            // до 1.3.8 тема и свет были одним выбором: «Светлая» — это Люмен при свете, «Своя» — своя тема
            switch theme {
            case .lumen: themeID = "lumen"; appearance = .dark
            case .mono: themeID = "mono"; appearance = .dark
            case .light: themeID = "lumen"; appearance = .light
            case .custom:
                let t = UserTheme(id: "user-mine", name: "Моя тема", hue: customTheme.hue, tint: customTheme.tint)
                userThemes.append(t)
                themeID = t.id
                appearance = customTheme.dark ? .dark : .light
            }
        }
        panelOrder = (try? c.decodeIfPresent([String].self, forKey: .panelOrder)) ?? ["plan", "session", "memory", "context", "usage"]
        panelHidden = (try? c.decodeIfPresent([String].self, forKey: .panelHidden)) ?? []
        panelCollapsed = (try? c.decodeIfPresent([String].self, forKey: .panelCollapsed)) ?? []
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        // до 1.4 был только «Меньше движения» вкл/выкл
        motion = (try? c.decodeIfPresent(MotionPref.self, forKey: .motion)) ?? (reducedMotion ? .on : .system)
        model = try c.decodeIfPresent(ChatModel.self, forKey: .model) ?? .sonnet
        effort = try c.decodeIfPresent(Effort.self, forKey: .effort) ?? .medium
        chatWidth = try c.decodeIfPresent(ChatWidth.self, forKey: .chatWidth) ?? .normal
        recentFolders = try c.decodeIfPresent([String].self, forKey: .recentFolders) ?? []
        autoRemember = try c.decodeIfPresent(Bool.self, forKey: .autoRemember) ?? true
        webSearch = try c.decodeIfPresent(Bool.self, forKey: .webSearch) ?? true
        useMemory = try c.decodeIfPresent(Bool.self, forKey: .useMemory) ?? true
        skyBackground = try c.decodeIfPresent(Bool.self, forKey: .skyBackground) ?? true
        monthlyLimit = try c.decodeIfPresent(Int.self, forKey: .monthlyLimit) ?? 100
        contextOpen = try c.decodeIfPresent(Bool.self, forKey: .contextOpen) ?? false
        sidebarHidden = try c.decodeIfPresent(Bool.self, forKey: .sidebarHidden) ?? false
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 284
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 320
        betaUpdates = try c.decodeIfPresent(Bool.self, forKey: .betaUpdates) ?? false
        agentModel = try? c.decodeIfPresent(ChatModel.self, forKey: .agentModel)
        agentEffort = try? c.decodeIfPresent(Effort.self, forKey: .agentEffort)
        agentMode = (try? c.decodeIfPresent(AgentMode.self, forKey: .agentMode)) ?? .auto
        hiddenModes = (try? c.decodeIfPresent([AgentMode].self, forKey: .hiddenModes)) ?? []
        apiKeys = (try? c.decodeIfPresent([ApiKeyEntry].self, forKey: .apiKeys)) ?? []
        activeKeyID = try? c.decodeIfPresent(String.self, forKey: .activeKeyID)
        notifyWhenDone = (try? c.decodeIfPresent(Bool.self, forKey: .notifyWhenDone)) ?? false
        pet = (try? c.decodeIfPresent(PetPrefs.self, forKey: .pet)) ?? PetPrefs()
        doneSound = (try? c.decodeIfPresent(String.self, forKey: .doneSound)) ?? ""
        sendWithCommand = (try? c.decodeIfPresent(Bool.self, forKey: .sendWithCommand)) ?? false
        projectContextAuto = (try? c.decodeIfPresent(Bool.self, forKey: .projectContextAuto)) ?? true
        agentRules = (try? c.decodeIfPresent(String.self, forKey: .agentRules)) ?? ""
        agentGuard = (try? c.decodeIfPresent(Bool.self, forKey: .agentGuard)) ?? true
        presence = (try? c.decodeIfPresent(Bool.self, forKey: .presence)) ?? true
        night = (try? c.decodeIfPresent(NightPrefs.self, forKey: .night)) ?? NightPrefs()
        autoModel = (try? c.decodeIfPresent(Bool.self, forKey: .autoModel)) ?? true
        autoCompact = (try? c.decodeIfPresent(Bool.self, forKey: .autoCompact)) ?? true
        compactAt = (try? c.decodeIfPresent(Int.self, forKey: .compactAt)) ?? Handoff.defaultPercent
        Self.migrateThemes(&self)
    }
}



/// Ключ API в списке: как назван, последние 4 знака, когда добавлен. Сам ключ — только в Связке ключей.
public struct ApiKeyEntry: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var tail: String
    public var addedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), name: String, tail: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tail = tail
        self.addedAt = addedAt
    }
}

extension Preferences {
    /// Готовые темы 26.10: «Люмен», «Монохром», «Корона», «Сияние». Прежние «Закат» и «Луна» — их ближайшие
    public static let renamedThemes = ["sunset": "corona", "moon": "lumen"]

    /// 26.10: готовые темы больше не меняются. Свои цвета у своих тем переезжают в саму тему,
    /// свои цвета поверх готовых тем отбрасываются; старые названия тем — на новые
    static func migrateThemes(_ p: inout Preferences) {
        if let to = renamedThemes[p.themeID] { p.themeID = to }
        if let d = p.darkThemeID, let to = renamedThemes[d] { p.darkThemeID = to }
        guard !p.themeOverrides.isEmpty else { return }
        for i in p.userThemes.indices {
            let id = p.userThemes[i].id
            if p.userThemes[i].darkColors == nil, let o = p.themeOverrides[id + "|dark"], !o.isEmpty { p.userThemes[i].darkColors = o }
            if p.userThemes[i].lightColors == nil, let o = p.themeOverrides[id + "|light"], !o.isEmpty { p.userThemes[i].lightColors = o }
        }
        p.themeOverrides = [:]
    }
}
