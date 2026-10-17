import Foundation
import LumenCore

/// Клиент встроенного браузера для lumen-mcp: строка JSON в сокет Lumen, строка JSON обратно.
/// Unix-сокет, а не порт: firewall его не трогает, а достучаться может только этот пользователь Мака.
public enum BrowserClient {
    public static func call(socket path: String, tool: String, args: [String: Any], who: String, conv: String = "", timeout: Int = 90) -> BrowserTools.Reply {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .init(text: "Браузер Lumen недоступен: не открылся сокет.", error: true) }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return .init(text: "Слишком длинный путь к сокету браузера.", error: true) }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else {
            return .init(text: "Браузер Lumen сейчас недоступен — Lumen закрыт или перезапускается. Попробуй через несколько секунд.", error: true)
        }
        let request = BrowserTools.request(tool: tool, args: args, who: who, conv: conv)
        var sent = 0
        while sent < request.count {
            let n = request.withUnsafeBytes { write(fd, $0.baseAddress! + sent, request.count - sent) }
            guard n > 0 else { return .init(text: "Браузер Lumen не принял запрос.", error: true) }
            sent += n
        }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if buf[n - 1] == 0x0A { break }
        }
        return BrowserTools.Reply(json: data) ?? .init(text: "Браузер Lumen не ответил вовремя.", error: true)
    }
}
