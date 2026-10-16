import Foundation
import LumenCore

/// Официальный реестр MCP (registry.modelcontextprotocol.io): поиск коннекторов.
/// Ставим то, что запускается без сборки: npm-пакет через `npx`, PyPI через `uvx` (если есть uv), или адрес сайта.
public enum MCPRegistry {
    public struct Entry: Sendable, Identifiable, Equatable {
        public var id: String { name }
        /// io.github.org/name
        public let name: String
        public let title: String
        public let description: String
        public let repository: String?
        public let server: MCPServer
        /// Что надо заполнить: переменные и заголовки, помеченные обязательными
        public let asks: [Ask]

        public struct Ask: Sendable, Equatable {
            public let key: String
            public let hint: String
            public let secret: Bool
        }

        /// Короткое имя для коннектора
        public var shortName: String {
            // com.notion/mcp → notion: если имя ничего не говорит, берём владельца
            let parts = name.split(separator: "/").map(String.init)
            let last = ConnectorImportName.short(parts.last ?? name)
            if ["mcp", "server", "mcp-server"].contains(last) || last.isEmpty, parts.count > 1 {
                let owner = parts[parts.count - 2].split(separator: ".").map(String.init)
                    .filter { !["com", "io", "ai", "dev", "app", "org", "net", "github", "co"].contains($0) }
                if let o = owner.last { return ConnectorImportName.short(o) }
            }
            return last
        }
    }

    public static func search(_ query: String, session: URLSession = .shared, uvx: Bool = false) async throws -> [Entry] {
        var c = URLComponents(string: "https://registry.modelcontextprotocol.io/v0/servers")!
        c.queryItems = [URLQueryItem(name: "search", value: query), URLQueryItem(name: "limit", value: "60")]
        let (data, response) = try await session.data(from: c.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["servers"] as? [[String: Any]] else { throw MCPClient.Failure("Реестр MCP не ответил") }
        var out: [Entry] = []
        var seen = Set<String>()
        for item in list {
            guard let s = item["server"] as? [String: Any], let name = s["name"] as? String, !seen.contains(name),
                  let e = entry(s, uvx: uvx) else { continue }
            // в реестре у сервера несколько версий — берём последнюю
            if let meta = (item["_meta"] as? [String: Any])?["io.modelcontextprotocol.registry/official"] as? [String: Any],
               meta["isLatest"] as? Bool == false { continue }
            seen.insert(name)
            out.append(e)
        }
        return out
    }

    static func entry(_ s: [String: Any], uvx: Bool) -> Entry? {
        let name = s["name"] as? String ?? ""
        let desc = s["description"] as? String ?? ""
        let title = s["title"] as? String ?? (name.split(separator: "/").last.map(String.init) ?? name)
        let repo = (s["repository"] as? [String: Any])?["url"] as? String
        // сначала пакет (работает без чужих аккаунтов), потом адрес
        for p in s["packages"] as? [[String: Any]] ?? [] {
            let kind = p["registryType"] as? String ?? p["registry_type"] as? String ?? ""
            let id = p["identifier"] as? String ?? p["name"] as? String ?? ""
            let transport = (p["transport"] as? [String: Any])?["type"] as? String ?? "stdio"
            guard !id.isEmpty, transport == "stdio" else { continue }
            let version = p["version"] as? String
            var asks: [Entry.Ask] = []
            var env: [String: String] = [:]
            for v in p["environmentVariables"] as? [[String: Any]] ?? [] {
                guard let k = v["name"] as? String else { continue }
                let secret = v["isSecret"] as? Bool ?? MCPServer.looksSecret(k)
                if v["isRequired"] as? Bool ?? false {
                    env[k] = "${\(k)}"
                    asks.append(.init(key: k, hint: v["description"] as? String ?? "", secret: secret))
                } else if let d = v["default"] as? String {
                    env[k] = d
                }
            }
            let args = (p["packageArguments"] as? [[String: Any]] ?? []).compactMap { a -> String? in
                guard a["isRequired"] as? Bool ?? false else { return nil }
                return a["value"] as? String ?? a["default"] as? String
            }
            if kind == "npm" {
                let pkg = version.map { "\(id)@\($0)" } ?? id
                return Entry(name: name, title: title, description: desc, repository: repo,
                             server: MCPServer(command: "npx", args: ["-y", pkg] + args, env: env, note: desc), asks: asks)
            }
            if kind == "pypi", uvx {
                return Entry(name: name, title: title, description: desc, repository: repo,
                             server: MCPServer(command: "uvx", args: [id] + args, env: env, note: desc), asks: asks)
            }
        }
        for r in s["remotes"] as? [[String: Any]] ?? [] {
            guard let url = r["url"] as? String, !url.contains("{") else { continue }
            let t = r["type"] as? String ?? "streamable-http"
            var headers: [String: String] = [:]
            var asks: [Entry.Ask] = []
            for h in r["headers"] as? [[String: Any]] ?? [] where h["isRequired"] as? Bool ?? false {
                guard let k = h["name"] as? String else { continue }
                let key = "\(ConnectorImportName.short(name.split(separator: "/").last.map(String.init) ?? name))_\(k)"
                    .uppercased().replacingOccurrences(of: "-", with: "_")
                // «Bearer {token}» → «Bearer ${…}»
                let template = h["value"] as? String ?? "{value}"
                let value = template.replacingOccurrences(of: #"\{[^}]+\}"#, with: "${\(key)}", options: .regularExpression)
                headers[k] = value.contains("${") ? value : "${\(key)}"
                asks.append(.init(key: key, hint: h["description"] as? String ?? k, secret: h["isSecret"] as? Bool ?? true))
            }
            return Entry(name: name, title: title, description: desc, repository: repo,
                         server: MCPServer(type: t == "sse" ? .sse : .http, url: url, headers: headers, note: desc), asks: asks)
        }
        return nil
    }
}

/// Короткое имя коннектора из имени пакета или сервера
public enum ConnectorImportName {
    public static func short(_ s: String) -> String {
        var n = s
        if let at = n.firstIndex(of: "@"), at != n.startIndex { n = String(n[..<at]) }
        for p in ["mcp-server-", "server-", "mcp-"] where n.lowercased().hasPrefix(p) { n = String(n.dropFirst(p.count)) }
        for x in ["-mcp-server", "-mcp", "-server", "_mcp"] where n.lowercased().hasSuffix(x) { n = String(n.dropLast(x.count)) }
        let c = MCPServer.cleanName(n)
        return c.isEmpty ? "server" : c
    }
}
