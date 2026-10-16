import Foundation

/// Проект — как в Claude: свои инструкции и файлы, которые видят все его чаты и задачи агента.
/// У агента в проекте ещё и папка: новая задача работает в ней.
public struct Project: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// Добавляются к системному промпту каждого разговора проекта
    public var instructions: String
    /// Папка для задач агента (необязательно)
    public var folder: String?
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString.lowercased(), name: String, instructions: String = "", folder: String? = nil,
                pinned: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.folder = folder
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Файл проекта: текст, который модель видит в каждом разговоре проекта
public struct ProjectFile: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int64?
    public var projectID: String
    public var name: String
    public var text: String
    public var addedAt: Date

    public init(id: Int64? = nil, projectID: String, name: String, text: String, addedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.text = text
        self.addedAt = addedAt
    }

    /// Больше этого в промпт не кладём: файл проекта — справка, а не книга
    public static let maxChars = 120_000
}

extension Project {
    /// Блок для системного промпта: инструкции и файлы проекта
    public func promptBlock(files: [ProjectFile]) -> String {
        var lines = ["Это разговор в проекте «\(name)»."]
        let ins = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ins.isEmpty { lines.append("Инструкции проекта:\n" + ins) }
        if !files.isEmpty {
            lines.append("Файлы проекта:")
            for f in files {
                lines.append("<file name=\"\(f.name)\">\n\(f.text.prefix(ProjectFile.maxChars))\n</file>")
            }
        }
        return lines.joined(separator: "\n\n")
    }
}
