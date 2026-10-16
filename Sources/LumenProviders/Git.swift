import Foundation
import LumenCore

/// Git в папке агента: снимок до хода, что поменялось после, разница, откат, коммит (§1 техплана, карточка «Изменения»).
/// Push Lumen не делает никогда: агенту он запрещён, а кнопки для него нет.
public struct Git: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Состояние до хода: какие файлы уже были изменены и их содержимое (хэш)
    public struct Snapshot: Sendable, Equatable, Codable {
        public var dirty: [String: String]
    }

    public var isRepo: Bool {
        get async { (try? await git(["rev-parse", "--is-inside-work-tree"]))?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" }
    }

    /// Ветка и сколько файлов сейчас изменено — для экрана новой задачи
    public struct Info: Sendable, Equatable {
        public let branch: String
        public let changed: Int
    }

    public func info() async -> Info? {
        guard await isRepo, let branch = try? await git(["rev-parse", "--abbrev-ref", "HEAD"]) else { return nil }
        let changed = (try? await status().count) ?? 0
        return Info(branch: branch.trimmingCharacters(in: .whitespacesAndNewlines), changed: changed)
    }

    public func snapshot() async throws -> Snapshot {
        var dirty: [String: String] = [:]
        for (path, _) in try await status() {
            dirty[path] = try await hash(path)
        }
        return Snapshot(dirty: dirty)
    }

    /// Файлы, которые агент поменял за ход: грязные сейчас и (чистые до хода или с другим содержимым)
    public func changes(since before: Snapshot) async throws -> [FileChange] {
        var out: [FileChange] = []
        let numstat = try await numstat()
        for (path, code) in try await status() {
            let h = try await hash(path)
            if let old = before.dirty[path], old == h { continue }
            let status = code.contains("?") || code.contains("A") ? "A" : (code.contains("D") ? "D" : "M")
            var (a, r) = numstat[path] ?? (0, 0)
            if status == "A", a == 0, let text = try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) {
                a = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
            }
            out.append(FileChange(path: path, status: status, added: a, removed: r, preexisting: before.dirty[path] != nil))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Разница по файлам: для новых — всё содержимое со знаком +
    public func diff(_ files: [FileChange]) async throws -> String {
        var parts: [String] = []
        let tracked = files.filter { $0.status != "A" }.map(\.path)
        if !tracked.isEmpty { parts.append(try await git(["diff", "--no-color", "HEAD", "--"] + tracked)) }
        for f in files where f.status == "A" {
            let text = (try? String(contentsOf: folder.appendingPathComponent(f.path), encoding: .utf8)) ?? "(не текстовый файл)"
            parts.append("+++ \(f.path) (новый)\n" + text.split(separator: "\n", omittingEmptySubsequences: false).map { "+" + $0 }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }

    /// Откатить файлы, которые были чистыми до хода. Новые файлы уходят в Корзину — их можно вернуть.
    public func revert(_ files: [FileChange]) async throws {
        for f in files where !f.preexisting {
            if f.status == "A" {
                try FileManager.default.trashItem(at: folder.appendingPathComponent(f.path), resultingItemURL: nil)
            } else {
                _ = try await git(["checkout", "HEAD", "--", f.path])
            }
        }
    }

    public func commit(_ files: [FileChange], message: String) async throws {
        _ = try await git(["add", "-A", "--"] + files.map(\.path))
        _ = try await git(["commit", "-m", message, "--"] + files.map(\.path))
    }

    // MARK: низкий уровень

    /// путь → код статуса (`git status --porcelain`), без папок
    func status() async throws -> [(String, String)] {
        let out = try await git(["status", "--porcelain", "-uall", "-z"])
        var result: [(String, String)] = []
        var items = out.split(separator: "\0").map(String.init)[...]
        while let item = items.popFirst() {
            guard item.count > 3 else { continue }
            let code = String(item.prefix(2))
            let path = String(item.dropFirst(3))
            if code.hasPrefix("R") || code.hasPrefix("C") { _ = items.popFirst() } // старое имя
            result.append((path, code))
        }
        return result
    }

    func numstat() async throws -> [String: (Int, Int)] {
        let out = (try? await git(["diff", "--numstat", "HEAD"])) ?? ""
        var map: [String: (Int, Int)] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            map[String(parts[2])] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        return map
    }

    func hash(_ path: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) else { return "deleted" }
        return try await git(["hash-object", "--", path]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func git(_ args: [String]) async throws -> String {
        guard let bin = Shell.which("git") else { throw GitError(message: "git не найден") }
        let out = try await Shell.run(bin, args, cwd: folder)
        guard out.status == 0 else { throw GitError(message: (out.stderr.isEmpty ? out.stdout : out.stderr).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return out.stdout
    }
}

public struct GitError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { "git: " + message }
}
