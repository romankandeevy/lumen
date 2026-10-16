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
    /// Навыки: папки с SKILL.md (§8.3)
    public var skills: URL { root.appendingPathComponent("skills", isDirectory: true) }
    /// Копии вложений (картинки и файлы из сообщений)
    public var attachments: URL { root.appendingPathComponent("attachments", isDirectory: true) }

    public func create() throws {
        for dir in [root, run, logs, skills, attachments] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
