import Foundation

/// Запущенные на этом Маке локальные серверы (localhost:порт) — сайты, превью, dev-серверы.
/// Берутся из `lsof`: кто слушает TCP. Системные службы (AirPlay, Handoff и т. п.) не показываем.
public enum LocalServers {
    public struct Server: Sendable, Hashable, Identifiable {
        public var port: Int
        public var process: String
        public var pid: Int
        public var title: String?
        public var id: Int { port }
        public var url: URL { URL(string: "http://localhost:\(port)")! }

        public init(port: Int, process: String, pid: Int, title: String? = nil) {
            self.port = port
            self.process = process
            self.pid = pid
            self.title = title
        }
    }

    /// Программы, которые запускают сайты и превью (имя у lsof обрезано до 9 знаков)
    static let devPrograms = ["node", "python", "ruby", "php", "deno", "bun", "java", "go", "dotnet", "hugo", "jekyll", "caddy",
                              "nginx", "httpd", "uvicorn", "gunicorn", "flask", "rails", "puma", "vite", "esbuild", "next-serv",
                              "webpack", "astro", "bundle", "rustc", "cargo", "swift", "http-serv", "serve", "live-serv", "npm",
                              "pnpm", "yarn", "docker", "com.docke", "postgres", "redis-ser", "mysqld", "mongod", "ollama", "lm studio"]

    /// Разобрать вывод `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`
    public static func parse(_ out: String) -> [Server] {
        var pid = 0, cmd = ""
        var seen = Set<Int>()
        var list: [Server] = []
        for line in out.split(separator: "\n") {
            guard let f = line.first else { continue }
            let v = String(line.dropFirst())
            switch f {
            case "p": pid = Int(v) ?? 0
            case "c": cmd = v
            case "n":
                // *:5173, 127.0.0.1:3000, [::1]:8080
                guard let colon = v.lastIndex(of: ":"), let port = Int(v[v.index(after: colon)...]), port >= 1024,
                      isDev(cmd), seen.insert(port).inserted else { continue }
                list.append(Server(port: port, process: cmd, pid: pid))
            default: break
            }
        }
        return list.sorted { $0.port < $1.port }
    }

    static func isDev(_ cmd: String) -> Bool {
        let c = cmd.lowercased()
        return devPrograms.contains { c.hasPrefix($0) }
    }

    /// Список с заголовками страниц (кто отвечает быстро)
    public static func scan() async -> [Server] {
        guard let out = try? await Shell.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else { return [] }
        var list = parse(out.stdout)
        await withTaskGroup(of: (Int, String?).self) { g in
            for s in list { g.addTask { (s.port, await title(port: s.port)) } }
            for await (port, t) in g { if let i = list.firstIndex(where: { $0.port == port }) { list[i].title = t } }
        }
        return list
    }

    /// <title> страницы за полсекунды; не HTTP — nil
    static func title(port: Int) async -> String? {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
        req.timeoutInterval = 0.6
        guard let (data, resp) = try? await URLSession.shared.data(for: req), resp is HTTPURLResponse else { return nil }
        let html = String(decoding: data.prefix(60_000), as: UTF8.self)
        guard let a = html.range(of: "<title", options: .caseInsensitive), let gt = html[a.upperBound...].firstIndex(of: ">"),
              let b = html.range(of: "</title>", options: .caseInsensitive, range: gt..<html.endIndex) else { return "" }
        return String(html[html.index(after: gt)..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
