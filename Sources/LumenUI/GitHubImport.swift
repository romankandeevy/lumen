import Foundation
import LumenCore
import LumenProviders

/// «Добавить из GitHub» в меню «+»: репозиторий клонируется в папку Lumen (мелко, без истории) и достаётся человеку:
/// агенту — как ещё одна папка с доступом, чату — README и списком файлов. В поле ввода — одна карточка репозитория.
extension AppModel {
    var githubFolder: URL { paths.root.appendingPathComponent("github", isDirectory: true) }

    struct GitHubResult {
        let repo: GitHubRepo
        let folder: URL
        /// Для чата: README и список файлов одним текстом (его копирует importAttachment)
        let summary: URL?
    }

    enum GitHubError: LocalizedError {
        case notARepo
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notARepo: "Не похоже на репозиторий: напиши «owner/repo» или вставь ссылку на GitHub"
            case .failed(let why): why
            }
        }
    }

    /// Репозитории, которые видит `gh` у этого человека (если вошёл в gh) — для списка в меню; нет gh или не вошёл — пусто
    func githubRepos(limit: Int = 30) async -> [(slug: String, note: String)] {
        guard let gh = Shell.which("gh"),
              let out = try? await Shell.run(gh, ["repo", "list", "--limit", String(limit), "--json", "nameWithOwner,description,isPrivate"]),
              out.status == 0, let data = out.stdout.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { r in
            guard let slug = r["nameWithOwner"] as? String else { return nil }
            let note = (r["isPrivate"] as? Bool == true ? "приватный · " : "") + ((r["description"] as? String) ?? "")
            return (slug, note)
        }
    }

    func importGitHub(_ text: String) async throws -> GitHubResult {
        guard let repo = GitHubRepo.parse(text) else { throw GitHubError.notARepo }
        let fm = FileManager.default
        let dir = githubFolder.appendingPathComponent(repo.folderName, isDirectory: true)
        try fm.createDirectory(at: githubFolder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            // уже клонирован — подтянуть свежее (не вышло — работаем с тем, что есть)
            if let git = Shell.which("git") { _ = try? await Shell.run(git, ["-C", dir.path, "pull", "--ff-only", "--quiet"]) }
        } else {
            try? fm.removeItem(at: dir)
            var cloned = false
            var why = ""
            // сначала gh: он знает приватные репозитории; потом обычный git по https
            if let gh = Shell.which("gh"), let out = try? await Shell.run(gh, ["repo", "clone", repo.slug, dir.path, "--", "--depth", "1", "--quiet"]) {
                cloned = out.status == 0
                why = out.stderr
            }
            if !cloned, let git = Shell.which("git") {
                let out = try await Shell.run(git, ["clone", "--depth", "1", "--quiet", repo.cloneURL, dir.path])
                cloned = out.status == 0
                why = out.stderr.isEmpty ? why : out.stderr
            }
            guard cloned else {
                let short = why.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
                throw GitHubError.failed("Не вышло взять «\(repo.slug)»" + (short.isEmpty ? "" : ": \(short)")
                                         + ". Приватный репозиторий — войди в gh (`gh auth login`)")
            }
        }
        return GitHubResult(repo: repo, folder: dir, summary: await summaryFile(repo, in: dir))
    }

    /// README и список файлов репозитория одним текстом: для чата, у которого нет доступа к файлам
    private func summaryFile(_ repo: GitHubRepo, in dir: URL) async -> URL? {
        let fm = FileManager.default
        var parts: [String] = []
        if let readme = (try? fm.contentsOfDirectory(atPath: dir.path))?.first(where: { $0.lowercased().hasPrefix("readme") }),
           let text = try? String(contentsOf: dir.appendingPathComponent(readme), encoding: .utf8) {
            parts.append("— \(readme) —\n" + text)
        }
        if let git = Shell.which("git"), let ls = try? await Shell.run(git, ["-C", dir.path, "ls-files"]), ls.status == 0 {
            let all = ls.stdout.split(separator: "\n")
            let lines = all.prefix(400)
            parts.append("— Файлы (\(all.count)) —\n" + lines.joined(separator: "\n") + (all.count > lines.count ? "\n… и ещё \(all.count - lines.count)" : ""))
        }
        guard !parts.isEmpty else { return nil }
        let tmp = fm.temporaryDirectory.appendingPathComponent("lumen-github-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let file = tmp.appendingPathComponent("\(repo.name).md")
        return (try? parts.joined(separator: "\n\n").write(to: file, atomically: true, encoding: .utf8)) != nil ? file : nil
    }
}
