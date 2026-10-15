import Foundation
import LumenStorage

// lumen-mcp — stdio MCP-сервер Lumen (§0, §7 техплана): память для claude.
// Окружение: LUMEN_DB — путь к базе, LUMEN_CONVERSATION_ID / LUMEN_CONVERSATION_TITLE — откуда факты.
// Протокол — JSON-RPC 2.0 построчно; нужны только initialize, tools/list, tools/call.

let env = ProcessInfo.processInfo.environment
guard let dbPath = env["LUMEN_DB"], let store = try? Store(path: URL(fileURLWithPath: dbPath)) else {
    FileHandle.standardError.write(Data("lumen-mcp: нет LUMEN_DB или база не открылась\n".utf8))
    exit(1)
}
let tools = MemoryTools(store: store, conversationID: env["LUMEN_CONVERSATION_ID"] ?? "",
                        conversationTitle: env["LUMEN_CONVERSATION_TITLE"] ?? "Разговор")

func reply(_ id: Any, _ result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func send(_ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

while let line = readLine(strippingNewline: true) {
    guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
    let id = msg["id"]
    let params = msg["params"] as? [String: Any] ?? [:]
    switch msg["method"] as? String {
    case "initialize":
        reply(id ?? 0, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                        "capabilities": ["tools": [:]],
                        "serverInfo": ["name": "lumen", "version": "1"]])
    case "tools/list":
        reply(id ?? 0, ["tools": MemoryTools.definitions.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try tools.call(name, args)
            reply(id ?? 0, ["content": [["type": "text", "text": text]]])
        } catch {
            reply(id ?? 0, ["content": [["type": "text", "text": "Ошибка памяти: \(error.localizedDescription)"]], "isError": true])
        }
    case "ping":
        reply(id ?? 0, [:])
    default:
        // уведомления (без id) молча пропускаем, на неизвестные запросы — пустой ответ
        if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found"]]) }
    }
}
