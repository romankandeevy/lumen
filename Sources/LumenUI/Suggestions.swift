import Foundation
import LumenCore
import LumenProviders
import LumenStorage

/// Подсказки пустого чата: Lumen сам предлагает, чем заняться — из памяти и недавних разговоров.
/// Думает быстрая модель (Haiku 5.5): по подписке через claude, иначе по ключу API.
/// Готовые подсказки хранятся в базе и показываются сразу, обновляются в фоне.
struct SuggestionCache: Codable, Equatable {
    var items: [String]
    var at: Date
    /// Что было известно, когда придумывали: если поменялось — пора придумать заново
    var basis: String
}

enum Suggestions {
    /// Пока Lumen ничего не придумал (первый запуск, нет ни подписки, ни ключа)
    static let fallback = ["Как прошёл день?", "Объясни, как работает память Lumen", "Запомни, что я встаю в 9"]

    static func prompt(name: String, address: Address, facts: [String], recent: [String]) -> String {
        var lines = ["Ты придумываешь подсказки для пустого чата в Lumen — личном помощнике на Маке."]
        lines.append("Напиши ровно три коротких сообщения, которые человек мог бы сейчас отправить Lumen. Пиши от его лица, по-русски, до 45 знаков каждое, без кавычек и эмодзи.")
        lines.append("Три разные темы, ни одна не повторяет другую: первое — следующий шаг по одному недавнему разговору, второе — про его проекты или дела из того, что о нём известно (не про тот же разговор), третье — что-то полезное или приятное на сегодня, связанное с его привычками. Не пересказывай названия разговоров дословно.")
        if !name.isEmpty { lines.append("Человека зовут \(name), к Lumen он обращается на «ты».") }
        if !facts.isEmpty { lines.append("Что о нём известно:\n" + facts.prefix(20).map { "- \($0)" }.joined(separator: "\n")) }
        if !recent.isEmpty { lines.append("Недавние разговоры:\n" + recent.prefix(8).map { "- \($0)" }.joined(separator: "\n")) }
        lines.append("Ответь только JSON-массивом из трёх строк, без пояснений.")
        return lines.joined(separator: "\n\n")
    }

    /// Пока Lumen не придумал для папки (нет подписки и ключа, первый показ): общие задачи
    static func agentFallback(home: Bool) -> [String] {
        home
            ? ["Найди самые большие файлы и скажи, что можно удалить", "Наведи порядок в папке «Загрузки»", "Расскажи, что занимает место на диске"]
            : ["Расскажи, что в этой папке и как она устроена", "Найди, что здесь можно улучшить, и предложи план", "Проверь, что всё собирается, а тесты проходят"]
    }

    static func agentPrompt(name: String, folder: String, home: Bool, branch: String?, changed: Int, files: [String], recent: [String]) -> String {
        var lines = ["Ты придумываешь подсказки для экрана новой задачи агента в Lumen. Агент работает с файлами и кодом в выбранной папке на Маке."]
        lines.append("Напиши ровно три коротких задачи, которые человек мог бы поручить агенту прямо сейчас в этой папке. Пиши от его лица, по-русски, до 55 знаков каждая, без кавычек и эмодзи, начинай с глагола.")
        lines.append("Три разные: первая — продолжить или довести дело, которое видно по недавним задачам и незакоммиченному; вторая — проверить или починить что-то (тесты, ошибки, порядок); третья — улучшить или упростить то, что в папке лежит. Не повторяй названия недавних задач дословно.")
        if !name.isEmpty { lines.append("Человека зовут \(name), к агенту он обращается на «ты».") }
        lines.append(home ? "Папка: домашняя папка человека (все его файлы)." : "Папка: \(folder).")
        if let branch { lines.append("Ветка git: \(branch), изменённых файлов не закоммичено: \(changed).") }
        if !files.isEmpty { lines.append("Что лежит в папке:\n" + files.prefix(25).map { "- \($0)" }.joined(separator: "\n")) }
        if !recent.isEmpty { lines.append("Недавние задачи в этой папке:\n" + recent.prefix(8).map { "- \($0)" }.joined(separator: "\n")) }
        lines.append("Ответь только JSON-массивом из трёх строк, без пояснений.")
        return lines.joined(separator: "\n\n")
    }

    /// Достать три строки из ответа модели (JSON-массив, возможно в ```)
    static func parse(_ text: String) -> [String]? {
        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"), a < b else { return nil }
        guard let arr = try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8)) as? [String] else { return nil }
        let items = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "«»\""))) }
            .filter { !$0.isEmpty && $0.count <= 60 }
        return items.count >= 2 ? Array(items.prefix(3)) : nil
    }
}

extension AppModel {
    /// Что сейчас показывать в пустом чате
    var suggestions: [String] {
        suggestionCache?.items ?? Suggestions.fallback
    }

    /// Отпечаток того, на чём строились подсказки: факты и последние разговоры
    private var suggestionBasis: String {
        // без hashValue: он у String меняется от запуска к запуску
        let lastFact = memories.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let lastChat = conversations.first?.updatedAt.timeIntervalSince1970 ?? 0
        return "\(memories.count)-\(Int(lastFact))-\(conversations.count)-\(Int(lastChat))"
    }

    /// Придумать заново, если подсказок нет, им больше 6 часов или с тех пор появилось новое (но не чаще раза в 10 минут)
    func refreshSuggestionsIfNeeded() {
        guard !suggestionsLoading else { return }
        let age = suggestionCache.map { Date().timeIntervalSince($0.at) } ?? .infinity
        let changed = suggestionCache?.basis != suggestionBasis
        guard age > 6 * 3600 || (changed && age > 600) else { return }
        Task { await refreshSuggestions() }
    }

    func refreshSuggestions() async {
        suggestionsLoading = true
        defer { suggestionsLoading = false }
        // при запуске вход в claude ещё проверяется — дождаться (не дольше 15 с)
        for _ in 0..<150 where claude == .checking { try? await Task.sleep(for: .milliseconds(100)) }
        let prompt = Suggestions.prompt(name: profile.name, address: profile.address,
                                        facts: memories.map(\.text), recent: conversations.prefix(8).map(\.title))
        let basis = suggestionBasis
        let text = await askFast(prompt)
        guard let text, let items = Suggestions.parse(text) else { return }
        let cache = SuggestionCache(items: items, at: Date(), basis: basis)
        suggestionCache = cache
        try? store.set("suggestions", cache)
    }

    /// Быстрый вопрос Haiku: по подписке через claude, иначе по ключу API (по выбранному движку). Ответ или nil
    func askFast(_ prompt: String) async -> String? {
        var text: String?
        let key = keychain.read(Keychain.anthropicKey)
        // Рома, 26.10: выбран движок API, а подсказки предпочитали подписку — платим как выбрано,
        // вторым способом достаём, если первый не ответил
        let wantAPI = prefs.backend == .api
        // выбран API — подпиской не достаём: человек выбрал платить ключом (Рома, 26.10)
        if wantAPI, let key { text = await askAPI(prompt, key: key) }
        if text == nil, !wantAPI, case .signedIn = claude, let cli {
            // одноразовый процесс: без инструментов, без настроек ~/.claude
            if let s = try? ClaudeSession(cli: cli, config: .init(model: ChatModel.haiku.rawValue, effort: Effort.low.rawValue,
                                                                 systemPrompt: "Отвечай только тем, что просят.", tools: [])) {
                if let r = try? await s.ask(prompt), r.ok {
                    text = r.text
                    try? store.logSpend(conversationID: nil, backend: .subscription, model: ChatModel.haiku.rawValue, input: r.inputTokens,
                                        output: r.outputTokens, cacheRead: r.cacheReadTokens, cacheWrite: r.cacheWriteTokens, usd: r.costUSD)
                }
                s.close()
            }
        }
        if text == nil, !wantAPI, let key, limitReached == nil { text = await askAPI(prompt, key: key) }
        return text
    }

    /// Тот же запрос по ключу API — напрямую, без claude
    private func askAPI(_ prompt: String, key: String) async -> String? {
        var api = AnthropicAPI(key: key)
        api.session = urlSession
        var req = AnthropicChatRequest(model: .haiku, effort: .low, system: "Отвечай только тем, что просят.",
                                       messages: [["role": "user", "content": prompt]])
        req.maxTokens = 400
        var out = ""
        do {
            for try await ev in api.chat(req) {
                switch ev {
                case .textDelta(let t): out += t
                case .finished(_, _, let u):
                    try? store.logSpend(conversationID: nil, backend: .api, model: ChatModel.haiku.rawValue, input: u.input, output: u.output,
                                        cacheRead: u.cacheRead, cacheWrite: u.cacheWrite,
                                        usd: ChatModel.haiku.cost(input: u.input, output: u.output, cacheRead: u.cacheRead, cacheWrite: u.cacheWrite))
                }
            }
            return out.isEmpty ? nil : out
        } catch { return nil }
    }
}

extension AppModel {
    static func agentSuggestionKey(_ folder: URL?) -> String { folder?.standardizedFileURL.path ?? "~" }

    /// Что предложить на экране новой задачи агента в этой папке (три задачи)
    func agentSuggestions(for folder: URL?) -> [String] {
        // всегда три: если модель дала меньше, недостающее — из запасных
        var items = agentSuggestionCache[Self.agentSuggestionKey(folder)]?.items ?? []
        for f in Suggestions.agentFallback(home: folder.map(Self.isHome) ?? true) where items.count < 3 && !items.contains(f) { items.append(f) }
        return Array(items.prefix(3))
    }

    /// Придумать заново для папки, если подсказок нет, им больше 6 часов или в папке с тех пор что-то поменялось (но не чаще раза в 10 минут)
    func refreshAgentSuggestionsIfNeeded(folder: URL?, git: Git.Info?) {
        let key = Self.agentSuggestionKey(folder)
        guard !agentSuggestionsLoading.contains(key) else { return }
        let tasks = conversations.filter { $0.kind == .agent && $0.folder.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == key }
        let basis = "\(git?.branch ?? "-")-\(git?.changed ?? 0)-\(tasks.count)-\(Int(tasks.first?.updatedAt.timeIntervalSince1970 ?? 0))"
        let cached = agentSuggestionCache[key]
        let age = cached.map { Date().timeIntervalSince($0.at) } ?? .infinity
        guard age > 6 * 3600 || (cached?.basis != basis && age > 600) else { return }
        agentSuggestionsLoading.insert(key)
        Task {
            defer { agentSuggestionsLoading.remove(key) }
            let home = folder.map(Self.isHome) ?? true
            // имена файлов — только у настоящей папки проекта, у домашней не отправляем
            let files = home ? [] : ((try? FileManager.default.contentsOfDirectory(atPath: key)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            let prompt = Suggestions.agentPrompt(name: profile.name, folder: folder?.lastPathComponent ?? "", home: home, branch: git?.branch,
                                                 changed: git?.changed ?? 0, files: files, recent: tasks.prefix(8).map(\.title))
            for _ in 0..<150 where claude == .checking { try? await Task.sleep(for: .milliseconds(100)) }
            guard let text = await askFast(prompt), let items = Suggestions.parse(text) else { return }
            agentSuggestionCache[key] = SuggestionCache(items: items, at: Date(), basis: basis)
            try? store.set("agentSuggestions", agentSuggestionCache)
        }
    }
}
