import Foundation

/// Папки Lumen (§10.4 техплана). Всё лежит на этом Маке.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// ~/Library/Application Support/Lumen. Для проверок — другая папка через LUMEN_HOME.
    public static var standard: AppPaths {
        if let custom = ProcessInfo.processInfo.environment["LUMEN_HOME"], !custom.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appendingPathComponent("Lumen", isDirectory: true))
    }

    public var database: URL { root.appendingPathComponent("lumen.sqlite") }
    public var run: URL { root.appendingPathComponent("run", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    /// Кастомизация — всё в одном месте, в формате Claude Code: навыки, коннекторы MCP, хуки
    public var customize: URL { root.appendingPathComponent("customize", isDirectory: true) }
    /// Навыки: папки с SKILL.md (§8.3)
    public var skills: URL { customize.appendingPathComponent("skills", isDirectory: true) }
    /// Коннекторы: `{"mcpServers": {…}}`
    public var mcp: URL { customize.appendingPathComponent("mcp.json") }
    /// Хуки: `{"hooks": {…}}`
    public var hooks: URL { customize.appendingPathComponent("hooks.json") }
    /// PROJECT.md проектов без своей папки: `projects/<id>/PROJECT.md`
    public var projects: URL { root.appendingPathComponent("projects", isDirectory: true) }
    /// Копии вложений (картинки и файлы из сообщений)
    public var attachments: URL { root.appendingPathComponent("attachments", isDirectory: true) }
    /// Макеты «как в Фигме» (.fig), которые агент собирает в браузере сбоку, а человек правит
    public var designs: URL { root.appendingPathComponent("designs", isDirectory: true) }
    /// 3D-модели: проект редактора (.three.json — правится дальше) и GLB для Blender, игр и Quick Look
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    /// Сокет встроенного браузера: lumen-mcp передаёт сюда действия агентов
    public var browserSocket: URL { run.appendingPathComponent("browser.sock") }
    /// Плагины Claude Code (их навыки, агенты, хуки, коннекторы): Lumen выключает их в своих сессиях — список id
    public var claudePlugins: URL { run.appendingPathComponent("claude-plugins.json") }

    /// Что сейчас делает позванный бот (пишет lumen-mcp, читает окно) — по разговору, откуда его позвали
    public func liveWork(_ conversationID: String) -> URL { run.appendingPathComponent("live-\(conversationID).json") }

    public func create() throws {
        // до 1.1 навыки лежали в Lumen/skills — переезжают в customize/skills
        let old = root.appendingPathComponent("skills", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: skills.path) {
            try fm.createDirectory(at: customize, withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: skills)
        }
        for dir in [root, run, logs, customize, skills, attachments] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
