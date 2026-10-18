import Foundation

/// Запуск программ из GUI-приложения. У приложения из Finder PATH не как в терминале,
/// поэтому добавляем папки, куда ставятся `claude`, `git`, `node` (§2.2, как `Shell.env` в Пульте).
public enum Shell {
    public static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        e["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return e
    }()

    public struct Output: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Запускает программу и ждёт конца. stdin = /dev/null, чтобы `claude -p` не ждал ввода 3 с.
    public static func run(_ executable: URL, _ args: [String], cwd: URL? = nil,
                           extraEnv: [String: String] = [:]) async throws -> Output {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = executable
            p.arguments = args
            p.environment = env.merging(extraEnv) { $1 }
            if let cwd { p.currentDirectoryURL = cwd }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            // читаем в фоне, чтобы большой вывод не забил буфер трубы и не повесил процесс
            let collector = Collector()
            let group = DispatchGroup()
            for (pipe, isOut) in [(out, true), (err, false)] {
                group.enter()
                DispatchQueue.global().async {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    collector.set(data, isOut: isOut)
                    group.leave()
                }
            }
            p.terminationHandler = { proc in
                group.notify(queue: .global()) {
                    let (o, e) = collector.get()
                    cont.resume(returning: Output(status: proc.terminationStatus,
                                                  stdout: String(decoding: o, as: UTF8.self),
                                                  stderr: String(decoding: e, as: UTF8.self)))
                }
            }
            // у родителя остаётся только чтение: без закрытой записи читатели не получат конца трубы.
            // Так же при ошибке запуска — иначе фоновые читатели висят навсегда
            let closeWriters = { try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close() }
            do {
                try p.run()
                closeWriters()
            } catch {
                closeWriters()
                cont.resume(throwing: error)
            }
        }
    }

    /// Ищет программу в PATH из `env`
    public static func which(_ name: String) -> URL? {
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    func set(_ d: Data, isOut: Bool) { lock.lock(); if isOut { out = d } else { err = d }; lock.unlock() }
    func get() -> (Data, Data) { lock.lock(); defer { lock.unlock() }; return (out, err) }
}
