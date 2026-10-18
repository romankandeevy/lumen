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
    /// Файл контекста проекта: его читают все чаты проекта, агент и Рома
    public static let contextFileName = "PROJECT.md"

    /// Своя папка проекта (не домашняя): в ней лежит PROJECT.md
    public var ownFolder: URL? {
        guard let folder, !folder.isEmpty else { return nil }
        let url = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        return url.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path ? nil : url
    }

    /// Где живёт контекст: в папке проекта (решение Ромы, 18.10), а без неё — в папке Lumen `projects/<id>`
    public func contextFolder(fallback projectsRoot: URL) -> URL {
        ownFolder ?? projectsRoot.appendingPathComponent(id, isDirectory: true)
    }

    public func contextURL(fallback projectsRoot: URL) -> URL {
        contextFolder(fallback: projectsRoot).appendingPathComponent(Project.contextFileName)
    }

    /// Блок для системного промпта: папка, контекст из PROJECT.md, инструкции и файлы проекта
    public func promptBlock(files: [ProjectFile], context: String? = nil, contextPath: String? = nil) -> String {
        var lines = ["Это разговор в проекте «\(name)». Что это за проект, где он и что уже решено — в его контексте ниже: опирайся на него и не переспрашивай то, что там уже есть."]
        if let ownFolder { lines.append("Папка проекта: \(ownFolder.path).") }
        let ctx = (context ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty { lines.append("Контекст проекта (\(contextPath ?? Project.contextFileName)):\n" + String(ctx.prefix(ProjectFile.maxChars))) }
        lines.append("Человек может попросить добавить в проект текст, ссылки, файлы или картинки — делай это инструментом add_to_project: "
                     + "он дописывает \(Project.contextFileName), и это увидят все чаты проекта. Остальное Lumen дописывает в контекст сам после ответа.")
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
