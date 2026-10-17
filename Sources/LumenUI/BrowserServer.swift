import Darwin
import Foundation
import LumenCore

/// Сокет встроенного браузера (`run/browser.sock`): lumen-mcp присылает строку JSON с действием,
/// Lumen выполняет его в панели и отвечает строкой JSON. Доступ — только у этого пользователя (права 0600).
final class BrowserServer: @unchecked Sendable {
    private let path: String
    private let handler: @Sendable (String, [String: Any], String) async -> BrowserTools.Reply
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "lumen.browser.server")

    init(path: String, handler: @escaping @Sendable (String, [String: Any], String) async -> BrowserTools.Reply) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { close(fd); throw POSIXError(.EIO) }
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        s.setEventHandler { [weak self] in self?.accept() }
        s.resume()
        source = s
    }

    func stop() {
        source?.cancel()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private func accept() {
        let c = Darwin.accept(fd, nil, nil)
        guard c >= 0 else { return }
        let handler = self.handler
        queue.async {
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 65_536)
            while true {
                let n = read(c, &buf, buf.count)
                if n <= 0 { break }
                data.append(contentsOf: buf[0..<n])
                if buf[n - 1] == 0x0A { break }
            }
            guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tool = o["tool"] as? String else {
                close(c)
                return
            }
            let args = o["args"] as? [String: Any] ?? [:]
            let who = o["who"] as? String ?? "Lumen"
            nonisolated(unsafe) let a = args
            Task {
                let reply = await handler(tool, a, who)
                let out = reply.json
                out.withUnsafeBytes { p in
                    var sent = 0
                    while sent < out.count {
                        let n = write(c, p.baseAddress! + sent, out.count - sent)
                        if n <= 0 { break }
                        sent += n
                    }
                }
                close(c)
            }
        }
    }
}
