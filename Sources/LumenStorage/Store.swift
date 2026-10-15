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
        return m
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

    @discardableResult
    public func remember(_ fact: MemoryFact) throws -> MemoryFact {
        try db.write { db in
            var f = fact
            try f.insert(db)
            return f
        }
    }

    /// Обновляет факт того же вида и источника, а если такого нет — добавляет.
    /// Знакомство можно пройти заново: имя не должно дублироваться.
    @discardableResult
    public func upsert(_ fact: MemoryFact) throws -> MemoryFact {
        try db.write { db in
            var f = fact
            if let old = try MemoryFact.filter(Column("kind") == fact.kind && Column("source") == fact.source).fetchOne(db) {
                f.id = old.id
                f.createdAt = old.createdAt
                try f.update(db)
            } else {
                try f.insert(db)
            }
            return f
        }
    }

    public func memories() throws -> [MemoryFact] {
        try db.read { db in try MemoryFact.order(Column("createdAt")).fetchAll(db) }
    }
}

extension MemoryFact: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "memory"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
