import Foundation

/// HyperFrames (Apache-2.0, heygen-com/hyperframes) — видео из HTML: агент пишет сцены, Студия показывает таймлайн,
/// рендер даёт MP4. Lumen зовёт его CLI через npx закреплённой версии; нужны Node (npx), FFmpeg и Chrome на этом Маке.
public enum VideoCLI {
    /// Проверенная с Lumen версия (26.10)
    public static let version = "0.8.202"

    public struct Missing: Error, LocalizedError {
        public let what: [String]
        public init(what: [String]) { self.what = what }
        public var errorDescription: String? {
            "Для видео на этом Маке нет: \(what.joined(separator: ", ")). Поставь через Homebrew: brew install \(what.map { $0 == "Node.js" ? "node" : ($0 == "FFmpeg" ? "ffmpeg" : $0) }.joined(separator: " "))"
        }
    }

    /// Чего не хватает (пусто — всё есть). Chrome — либо обычный, либо скачает сам HyperFrames
    public static func missing() -> [String] {
        var m: [String] = []
        if Shell.which("npx") == nil { m.append("Node.js") }
        if Shell.which("ffmpeg") == nil { m.append("FFmpeg") }
        return m
    }

    public static var available: Bool { missing().isEmpty }

    /// Окружение: без телеметрии, без цветов в выводе, без вопросов и без установки навыков в чужие агенты
    static let extraEnv: [String: String] = [
        "HYPERFRAMES_SKIP_SKILLS": "1", "DO_NOT_TRACK": "1", "HYPERFRAMES_TELEMETRY": "0",
        "NO_COLOR": "1", "FORCE_COLOR": "0", "CI": "1", "npm_config_yes": "true", "npm_config_update_notifier": "false",
    ]

    /// `npx hyperframes@<версия> <args>` в папке `cwd`
    public static func run(_ args: [String], cwd: URL) async throws -> Shell.Output {
        let m = missing()
        guard m.isEmpty, let npx = Shell.which("npx") else { throw Missing(what: m.isEmpty ? ["Node.js"] : m) }
        return try await Shell.run(npx, ["-y", "hyperframes@\(version)"] + args, cwd: cwd, extraEnv: extraEnv)
    }

    /// Телеметрию HyperFrames выключить один раз (их CLI спрашивает своё хранилище настроек)
    public static func disableTelemetry(cwd: URL) async {
        _ = try? await run(["telemetry", "disable"], cwd: cwd)
    }

    /// Убрать ANSI-цвета из вывода, если CLI их всё же поставил
    public static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\u{1B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
    }
}
