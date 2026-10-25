import Foundation

/// Репозиторий GitHub из того, что человек вставил: «owner/repo», ссылка на страницу или на клон
public struct GitHubRepo: Equatable, Sendable {
    public let owner: String
    public let name: String

    public var slug: String { "\(owner)/\(name)" }
    public var cloneURL: String { "https://github.com/\(owner)/\(name).git" }
    /// Имя папки для клона в папке Lumen
    public var folderName: String { "\(owner)__\(name)" }

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Понимает: `owner/repo`, `github.com/owner/repo`, `https://github.com/owner/repo/tree/main/src`, `…repo.git`,
    /// `git@github.com:owner/repo.git`. Не репозиторий — nil
    public static func parse(_ text: String) -> GitHubRepo? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["git@github.com:", "https://github.com/", "http://github.com/", "https://www.github.com/", "github.com/", "www.github.com/"] {
            if s.lowercased().hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        // без схемы «a/b» — репозиторий; со схемой другого сайта — нет
        guard !s.contains("://"), !s.contains(" ") else { return nil }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        var name = parts[1]
        if name.hasSuffix(".git") { name.removeLast(4) }
        let valid = { (t: String) in !t.isEmpty && t.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }
        guard valid(parts[0]), valid(name), !name.hasPrefix(".") else { return nil }
        return GitHubRepo(owner: parts[0], name: name)
    }
}
