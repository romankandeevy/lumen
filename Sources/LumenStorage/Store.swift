import Foundation
import GRDB
import LumenCore

/// База Lumen: SQLite в режиме WAL через GRDB (§10.4).
/// Таблицы добавляются миграциями по мере того, как появляются функции.
public final class Store: Sendable {
    public let db: DatabaseWriter

    /// Рабочая база на диске
    public init(path: URL) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: path.path, configuration: config)
        try Self.migrator.migrate(db)
    }

    /// База в памяти — для тестов
    public init() throws {
        db = try DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            // Настройки и профиль — пары ключ → JSON, чтобы новые поля не требовали миграций
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .jsonText).notNull()
            }
            try db.create(table: "memory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("source", .text).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
        }
        m.registerMigration("v2-chat") { db in
            try db.create(table: "conversation") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("backend", .text).notNull()
                t.column("model", .text).notNull()
                t.column("effort", .text).notNull()
                t.column("cliSessionID", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "message") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("conversationID", .text).notNull().indexed()
                    .references("conversation", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("apiContent", .text)
                t.column("model", .text)
                t.column("stopped", .boolean).notNull().defaults(to: false)
                t.column("error", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        m.registerMigration("v3-agent") { db in
            try db.alter(table: "conversation") { t in
                t.add(column: "kind", .text).notNull().defaults(to: "chat")
                t.add(column: "folder", .text)
            }
            try db.alter(table: "message") { t in
                t.add(column: "steps", .jsonText).notNull().defaults(to: "[]")
                t.add(column: "changes", .jsonText)
            }
        }
        m.registerMigration("v4-memory") { db in
            try db.alter(table: "memory") { t in
                t.add(column: "conversationID", .text)
                t.add(column: "key", .text)
                t.add(column: "updatedAt", .datetime)
            }
            // факты знакомства 0.1–0.4: «name»/«address» → виды из макета, постоянные ключи
            try db.execute(sql: """
                UPDATE memory SET key = 'onboarding.' || kind, kind = CASE kind WHEN 'name' THEN 'you' ELSE 'pref' END,
                       source = 'Знакомство' WHERE source = 'onboarding';
                UPDATE memory SET kind = 'you' WHERE kind NOT IN ('you','project','decision','pref','people');
                UPDATE memory SET updatedAt = createdAt;
                """)
            try db.create(index: "memory_key", on: "memory", columns: ["key"], unique: true, ifNotExists: true)
            try db.alter(table: "message") { t in
                t.add(column: "remembered", .jsonText).notNull().defaults(to: "[]")
                t.add(column: "recalled", .jsonText).notNull().defaults(to: "[]")
            }
            // полнотекстовый поиск. Своя копия текста с «ё» → «е»: unicode61 не сводит их в кириллице.
            // Таблицы обновляются триггерами из memory и message.
            for (fts, table) in [("memory_fts", "memory"), ("message_fts", "message")] {
                try db.execute(sql: "CREATE VIRTUAL TABLE \(fts) USING fts5(text, tokenize = 'unicode61 remove_diacritics 2')")
                let norm = "replace(replace(new.text, 'ё', 'е'), 'Ё', 'Е')"
                try db.execute(sql: """
                    INSERT INTO \(fts)(rowid, text) SELECT id, replace(replace(text, 'ё', 'е'), 'Ё', 'Е') FROM \(table);
                    CREATE TRIGGER \(table)_fts_ai AFTER INSERT ON \(table) BEGIN
                        INSERT INTO \(fts)(rowid, text) VALUES (new.id, \(norm)); END;
                    CREATE TRIGGER \(table)_fts_au AFTER UPDATE OF text ON \(table) BEGIN
                        UPDATE \(fts) SET text = \(norm) WHERE rowid = new.id; END;
                    CREATE TRIGGER \(table)_fts_ad AFTER DELETE ON \(table) BEGIN
                        DELETE FROM \(fts) WHERE rowid = old.id; END;
                    """)
            }
            // что из памяти запомнено или вспомнено в каком разговоре — для «Запомнил» и «Опирался на»
            try db.create(table: "memoryUse") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("conversationID", .text).notNull().indexed()
                t.column("memoryID", .integer).notNull().references("memory", onDelete: .cascade)
                t.column("action", .text).notNull() // remember | recall
                t.column("at", .datetime).notNull()
            }
        }
        m.registerMigration("v5-spend") { db in
            try db.alter(table: "message") { t in
                t.add(column: "contextTokens", .integer)
                t.add(column: "contextWindow", .integer)
                t.add(column: "note", .text)
            }
            // журнал трат (§11): по API — по ценам, по подписке — оценка claude «сколько стоило бы»
            try db.create(table: "spend") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("at", .datetime).notNull().indexed()
                t.column("conversationID", .text)
                t.column("backend", .text).notNull()
                t.column("model", .text).notNull()
                t.column("input", .integer).notNull()
                t.column("output", .integer).notNull()
                t.column("cacheRead", .integer).notNull()
                t.column("cacheWrite", .integer).notNull()
                t.column("usd", .double).notNull()
            }
        }
        m.registerMigration("v6-plan") { db in
            try db.alter(table: "conversation") { t in t.add(column: "plan", .jsonText).notNull().defaults(to: "[]") }
            try db.alter(table: "message") { t in t.add(column: "next", .jsonText) }
        }
        m.registerMigration("v7-pinned") { db in
            try db.alter(table: "conversation") { t in t.add(column: "pinned", .boolean).notNull().defaults(to: false) }
        }
        m.registerMigration("v8-projects") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("instructions", .text).notNull().defaults(to: "")
                t.column("folder", .text)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "projectFile") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("projectID", .text).notNull().indexed().references("project", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("text", .text).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            // удалили проект — его разговоры остаются, просто без проекта
            try db.alter(table: "conversation") { t in
                t.add(column: "projectID", .text).indexed().references("project", onDelete: .setNull)
            }
        }
        m.registerMigration("v9-bots") { db in
            try db.create(table: "bot") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull()
                t.column("hue", .double).notNull()
                t.column("role", .text).notNull()
                t.column("instructions", .text).notNull()
                t.column("capabilities", .jsonText).notNull()
                t.column("commands", .jsonText).notNull()
                t.column("folder", .text)
                t.column("model", .text).notNull()
                t.column("effort", .text).notNull()
                t.column("starters", .jsonText).notNull()
                t.column("handoff", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            // постоянный разговор бота и ответы бота в чужих чатах (@id)
            try db.alter(table: "conversation") { t in t.add(column: "botID", .text).indexed() }
            try db.alter(table: "message") { t in t.add(column: "botID", .text) }
        }
        m.registerMigration("v10-skills") { db in
            try db.create(table: "skillUse") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().indexed()
                t.column("conversationID", .text)
                t.column("at", .datetime).notNull()
            }
            // навыки бота и чему он научился; предложенный навык под ответом
            try db.alter(table: "bot") { t in
                t.add(column: "skills", .jsonText).notNull().defaults(to: "[]")
                t.add(column: "learned", .jsonText).notNull().defaults(to: "[]")
            }
            try db.alter(table: "message") { t in t.add(column: "skillDraft", .jsonText) }
        }
        m.registerMigration("v11-modes") { db in
            try db.alter(table: "conversation") { t in t.add(column: "mode", .text) }
        }
        m.registerMigration("v12-attachments") { db in
            try db.alter(table: "message") { t in t.add(column: "attachments", .jsonText).notNull().defaults(to: "[]") }
        }
        m.registerMigration("v13-via") { db in
            try db.alter(table: "message") { t in t.add(column: "via", .jsonText) }
        }
        m.registerMigration("v14-connectors") { db in
            try db.alter(table: "bot") { t in t.add(column: "connectors", .jsonText).notNull().defaults(to: "[]") }
        }
        m.registerMigration("v15-proposals") { db in
            try db.alter(table: "message") { t in t.add(column: "proposals", .jsonText).notNull().defaults(to: "[]") }
        }
        return m
    }

    // MARK: навыки

    public func logSkillUse(_ name: String, conversationID: String?) throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO skillUse(name, conversationID, at) VALUES (?, ?, ?)", arguments: [name, conversationID, Date()])
        }
    }

    /// Сколько раз модель брала каждый навык
    public func skillUseCounts() throws -> [String: Int] {
        try db.read { db in
            var out: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT name, COUNT(*) AS n FROM skillUse GROUP BY name") { out[row["name"]] = row["n"] }
            return out
        }
    }

    // MARK: боты

    public func bots() throws -> [Bot] {
        try db.read { db in try Bot.order(Column("createdAt")).fetchAll(db) }
    }

    public func save(_ b: Bot) throws {
        try db.write { db in try b.save(db) }
    }

    /// Бот уходит вместе со своим разговором; его ответы в других чатах остаются
    public func deleteBot(_ id: String) throws {
        try db.write { db in
            let convs = try String.fetchAll(db, sql: "SELECT id FROM conversation WHERE botID = ? AND kind = 'bot'", arguments: [id])
            for c in convs {
                try db.execute(sql: "DELETE FROM message WHERE conversationID = ?", arguments: [c])
                try db.execute(sql: "DELETE FROM conversation WHERE id = ?", arguments: [c])
            }
            _ = try Bot.deleteOne(db, key: id)
        }
    }

    // MARK: проекты

    public func projects() throws -> [Project] {
        try db.read { db in try Project.order(Column("pinned").desc, Column("updatedAt").desc).fetchAll(db) }
    }

    public func save(_ p: Project) throws {
        var p = p
        p.updatedAt = Date()
        try db.write { db in try p.save(db) }
    }

    public func deleteProject(_ id: String) throws {
        _ = try db.write { db in try Project.deleteOne(db, key: id) }
    }

    public func files(in projectID: String) throws -> [ProjectFile] {
        try db.read { db in try ProjectFile.filter(Column("projectID") == projectID).order(Column("addedAt")).fetchAll(db) }
    }

    @discardableResult
    public func save(_ f: ProjectFile) throws -> ProjectFile {
        try db.write { db in
            var f = f
            try f.save(db)
            return f
        }
    }

    public func deleteFile(_ id: Int64) throws {
        _ = try db.write { db in try ProjectFile.deleteOne(db, key: id) }
    }

    // MARK: траты

    public func logSpend(conversationID: String?, backend: Backend, model: String, input: Int, output: Int,
                         cacheRead: Int, cacheWrite: Int, usd: Double) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO spend(at, conversationID, backend, model, input, output, cacheRead, cacheWrite, usd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [Date(), conversationID, backend.rawValue, model, input, output, cacheRead, cacheWrite, usd])
        }
    }

    /// Сколько потрачено с начала месяца (по API — деньги, по подписке — оценка)
    public func spent(backend: Backend, since: Date) throws -> Double {
        try db.read { db in
            try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(usd), 0) FROM spend WHERE backend = ? AND at >= ?",
                                arguments: [backend.rawValue, since]) ?? 0
        }
    }

    // MARK: разговоры

    public func conversations() throws -> [Conversation] {
        try db.read { db in try Conversation.order(Column("updatedAt").desc).fetchAll(db) }
    }

    public func save(_ c: Conversation) throws {
        try db.write { db in try c.save(db) }
    }

    public func updatePlan(_ id: String, _ plan: [PlanItem]) throws {
        let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        try db.write { db in try db.execute(sql: "UPDATE conversation SET plan = ? WHERE id = ?", arguments: [json, id]) }
    }

    public func deleteConversation(_ id: String) throws {
        _ = try db.write { db in try Conversation.deleteOne(db, key: id) }
    }

    public func deleteMessage(_ id: Int64) throws {
        _ = try db.write { db in try ChatMessage.deleteOne(db, key: id) }
    }

    public func messages(in conversationID: String) throws -> [ChatMessage] {
        try db.read { db in
            try ChatMessage.filter(Column("conversationID") == conversationID).order(Column("id")).fetchAll(db)
        }
    }

    /// Добавляет сообщение (или обновляет, если у него уже есть id) и поднимает разговор наверх списка
    @discardableResult
    public func save(_ message: ChatMessage) throws -> ChatMessage {
        try db.write { db in
            var m = message
            try m.save(db)
            try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?", arguments: [Date(), m.conversationID])
            return m
        }
    }

    // MARK: настройки

    public func value<T: Codable>(_ key: String, as type: T.Type) throws -> T? {
        try db.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) else { return nil }
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    public func set<T: Codable>(_ key: String, _ value: T) throws {
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try db.write { db in
            try db.execute(sql: "INSERT INTO setting(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [key, json])
        }
    }

    public var profile: Profile { (try? value("profile", as: Profile.self)) ?? Profile() }
    public var preferences: Preferences { (try? value("preferences", as: Preferences.self)) ?? Preferences() }

    // MARK: память

    /// Добавляет факт или, если у него есть ключ и такой уже есть, переписывает его
    @discardableResult
    public func save(_ fact: MemoryFact) throws -> MemoryFact {
        try db.write { db in
            var f = fact
            f.updatedAt = Date()
            if f.id == nil, let key = f.key, let old = try MemoryFact.filter(Column("key") == key).fetchOne(db) {
                f.id = old.id
                f.createdAt = old.createdAt
            }
            try f.save(db)
            return f
        }
    }

    public func deleteMemory(_ id: Int64) throws {
        _ = try db.write { db in try MemoryFact.deleteOne(db, key: id) }
    }

    /// Все факты: закреплённые сверху, дальше свежие
    public func memories() throws -> [MemoryFact] {
        try db.read { db in
            try MemoryFact.order(Column("pinned").desc, Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func memoryCount() throws -> Int {
        try db.read { db in try MemoryFact.fetchCount(db) }
    }

    /// Поиск фактов по словам с русскими окончаниями. `anyWord` — хватит любого слова (для recall), иначе все.
    public func searchMemories(_ text: String, limit: Int = 8, anyWord: Bool = false) throws -> [MemoryFact] {
        guard let q = SearchQuery.fts(text, anyWord: anyWord) else { return [] }
        return try db.read { db in
            try MemoryFact.fetchAll(db, sql: """
                SELECT memory.* FROM memory JOIN memory_fts ON memory_fts.rowid = memory.id
                WHERE memory_fts MATCH ? ORDER BY memory.pinned DESC, bm25(memory_fts) LIMIT ?
                """, arguments: [q, limit])
        }
    }

    /// Поиск по прошлым разговорам: одно лучшее место на разговор
    public func searchConversations(_ text: String, limit: Int = 20) throws -> [ConversationHit] {
        guard let q = SearchQuery.fts(text) else { return [] }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT message.id, message.conversationID, message.createdAt, conversation.title, conversation.kind,
                       snippet(message_fts, 0, '«', '»', '…', 14) AS snip, bm25(message_fts) AS rank
                FROM message_fts JOIN message ON message.id = message_fts.rowid
                JOIN conversation ON conversation.id = message.conversationID
                WHERE message_fts MATCH ? ORDER BY rank LIMIT 200
                """, arguments: [q])
            var seen = Set<String>()
            var out: [ConversationHit] = []
            for r in rows {
                let cid: String = r["conversationID"]
                guard seen.insert(cid).inserted else { continue }
                out.append(ConversationHit(messageID: r["id"], conversationID: cid, title: r["title"],
                                           kind: ConversationKind(rawValue: r["kind"]) ?? .chat, snippet: r["snip"], date: r["createdAt"]))
                if out.count == limit { break }
            }
            return out
        }
    }

    /// Отметить, что факт запомнен или вспомнен в разговоре
    public func logMemoryUse(_ memoryID: Int64, conversationID: String, action: String) throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO memoryUse(conversationID, memoryID, action, at) VALUES (?, ?, ?, ?)",
                           arguments: [conversationID, memoryID, action, Date()])
        }
    }

    /// Факты, запомненные или вспомненные в разговоре с момента `since`
    public func memoryUses(conversationID: String, since: Date, action: String) throws -> [Int64] {
        try db.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT DISTINCT memoryID FROM memoryUse WHERE conversationID = ? AND action = ? AND at >= ? ORDER BY id
                """, arguments: [conversationID, action, since])
        }
    }

    public func memories(ids: [Int64]) throws -> [MemoryFact] {
        guard !ids.isEmpty else { return [] }
        return try db.read { db in try MemoryFact.fetchAll(db, keys: ids) }
    }
}

extension Bot: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bot"
}

extension Project: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project"
}

extension ProjectFile: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "projectFile"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Conversation: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "conversation"
}

extension ChatMessage: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "message"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension MemoryFact: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "memory"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
