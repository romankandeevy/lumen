import Foundation

/// Вложение к сообщению: картинка, PDF, текстовый файл или любой другой файл.
/// Копия лежит в папке Lumen (`attachments/`), поэтому разговор не ломается, если оригинал удалили.
public struct Attachment: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case image, pdf, text, file }

    public var id: String
    public var name: String
    public var kind: Kind
    /// image/jpeg, image/png, application/pdf, text/plain …
    public var mime: String
    /// Путь к копии в папке Lumen
    public var path: String
    public var size: Int
    public var width: Int?
    public var height: Int?
    /// Снимок экрана, что сделал сам агент (browser_screenshot): виден превью на строке его шагов, а не отдельной картинкой
    public var snapshot: Bool?
    /// Репозиторий GitHub «owner/name» из «+ → Добавить из GitHub»: одна карточка с логотипом (как в Claude, Рома 26.10).
    /// У чата `path` — README и список файлов одним текстом, у агента — папка с копией репозитория
    public var repo: String?

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: Kind, mime: String, path: String, size: Int,
                width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mime = mime
        self.path = path
        self.size = size
        self.width = width
        self.height = height
    }

    public var url: URL { URL(fileURLWithPath: path) }

    /// Карточка репозитория: «flowlocal» крупно, владелец — подписью
    public var repoOwner: String? { repo.flatMap { $0.split(separator: "/").first.map(String.init) } }
    public var repoWebURL: URL? { repo.flatMap { URL(string: "https://github.com/\($0)") } }

    /// Видео и аудио — проигрываются в браузере сбоку
    public static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm"]
    public static let audioExts: Set<String> = ["mp3", "m4a", "wav", "aac", "aiff", "aif", "flac", "ogg", "caf"]
    public var isVideo: Bool { Self.videoExts.contains(url.pathExtension.lowercased()) }
    public var isAudio: Bool { Self.audioExts.contains(url.pathExtension.lowercased()) }

    /// «1,2 МБ», «340 КБ»
    public var sizeText: String {
        if size < 1000 { return "\(size) байт" }
        if size < 1_000_000 { return "\(Int((Double(size) / 1000).rounded())) КБ" }
        return String(format: "%.1f МБ", Double(size) / 1_000_000).replacingOccurrences(of: ".", with: ",")
    }

    /// Текст файла для модели: до 100 тысяч знаков
    public static let textLimit = 100_000

    /// Блок содержимого Anthropic (тот же для `claude` через stream-json и для API)
    public func contentBlock() -> [String: Any]? {
        if let repo {
            if kind == .text, let text = try? String(contentsOf: url, encoding: .utf8) {
                let cut = text.count > Self.textLimit ? String(text.prefix(Self.textLimit)) + "\n…(обрезано)" : text
                return ["type": "text", "text": "Репозиторий GitHub «\(repo)» — README и список файлов:\n```\n\(cut)\n```"]
            }
            return ["type": "text", "text": "Репозиторий GitHub «\(repo)» склонирован в папку \(path) — она тебе доступна: читай и ищи файлы там."]
        }
        switch kind {
        case .image:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]]
        case .pdf:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()],
                    "title": name]
        case .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let cut = text.count > Self.textLimit ? String(text.prefix(Self.textLimit)) + "\n…(обрезано)" : text
            return ["type": "text", "text": "Файл «\(name)»:\n```\n\(cut)\n```"]
        case .file:
            return ["type": "text", "text": "Приложен файл «\(name)» (\(sizeText)), лежит здесь: \(path)"]
        }
    }

    /// Содержимое сообщения человека: сначала вложения, потом текст (так модель лучше понимает, к чему вопрос).
    /// Агенту ещё и пути: он может открыть файл инструментами.
    public static func userContent(text: String, attachments: [Attachment], agent: Bool) -> [[String: Any]] {
        var blocks = attachments.compactMap { $0.contentBlock() }
        var t = text
        if agent && !attachments.isEmpty {
            // у репозитория путь уже в его блоке
            let files = attachments.filter { $0.repo == nil }
            if !files.isEmpty { t += "\n\n(Вложения сохранены: " + files.map { "\($0.name) — \($0.path)" }.joined(separator: "; ") + ")" }
        }
        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(["type": "text", "text": t]) }
        return blocks
    }

    /// Служебная приписка агенту «(Вложения сохранены: имя — путь; …)» — человеку не нужна. Отрезает её и
    /// возвращает вложения по путям из неё (те, что ещё лежат на диске)
    public static func splitSavedNote(_ text: String) -> (text: String, attachments: [Attachment]) {
        guard let r = text.range(of: "(Вложения сохранены: ", options: .backwards), text.hasSuffix(")") else { return (text, []) }
        let list = text[r.upperBound..<text.index(before: text.endIndex)]
        var out: [Attachment] = []
        for item in list.components(separatedBy: "; ") {
            guard let dash = item.range(of: " — ") else { continue }
            let name = String(item[..<dash.lowerBound]), path = String(item[dash.upperBound...])
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let image = ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext)
            out.append(Attachment(name: name, kind: image ? .image : (ext == "pdf" ? .pdf : .file),
                                  mime: image ? "image/" + (ext == "jpg" ? "jpeg" : ext) : (ext == "pdf" ? "application/pdf" : "application/octet-stream"),
                                  path: path, size: attrs[.size] as? Int ?? 0))
        }
        return (String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), out)
    }

    /// Текстовые файлы и не-картинки — в текст запроса (для ChatGPT, у которого картинки идут отдельно)
    public static func inlineText(_ attachments: [Attachment]) -> String {
        attachments.filter { $0.kind != .image }.compactMap { $0.contentBlock()?["text"] as? String }.joined(separator: "\n\n")
    }
}

/// Файл, брошенный прямо на поле ввода (или вставленный), поле само превращает в текст — путь вида
/// «/var/folders/…/Снимок экрана ….png». Рома видел вместо вложения «var и всякое разное» (19.10).
/// Здесь — узнать такую вставку: что добавилось в черновик и не путь ли это к существующим файлам.
public enum DroppedPaths {
    /// Что вставилось между старым и новым текстом (общее начало и конец отрезаны). nil — ничего не добавилось
    public static func insertion(old: String, new: String) -> (text: String, prefix: String, suffix: String)? {
        guard new.count > old.count else { return nil }
        let o = Array(old), n = Array(new)
        var start = 0
        while start < o.count, o[start] == n[start] { start += 1 }
        var end = 0
        while end < o.count - start, o[o.count - 1 - end] == n[n.count - 1 - end] { end += 1 }
        let inserted = String(n[start..<(n.count - end)])
        return inserted.isEmpty ? nil : (inserted, String(n[..<start]), String(n[(n.count - end)...]))
    }

    /// Вставка целиком состоит из путей к существующим файлам (папки не в счёт) — их адреса; иначе nil.
    /// Пути со пробелами, несколько путей через перевод строки или пробел, `file://` и `\ ` из Терминала.
    public static func files(in inserted: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [URL]? {
        let text = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") || text.hasPrefix("file://") || text.hasPrefix("~/") else { return nil }
        var urls: [URL] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            guard let found = paths(in: line, exists: exists) else { return nil }
            urls += found
        }
        return urls.isEmpty ? nil : urls
    }

    static func path(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if s.hasPrefix("file://"), let u = URL(string: s) { s = u.path }
        if s.hasPrefix("~/") { s = NSHomeDirectory() + s.dropFirst(1) }
        return s.replacingOccurrences(of: "\\ ", with: " ")
    }

    /// Одна строка: один путь (с пробелами) или несколько, каждый начинается с «/» или «file://»
    static func paths(in line: String, exists: (String) -> Bool) -> [URL]? {
        let whole = path(line)
        if exists(whole) { return [URL(fileURLWithPath: whole)] }
        // несколько путей через пробел: режем перед каждым « /» и « file://» и собираем куски, пока не найдётся файл
        var starts: [String.Index] = []
        var i = line.startIndex
        while i < line.endIndex {
            let next = line.index(after: i)
            if line[i].isWhitespace, next < line.endIndex, line[next...].hasPrefix("/") || line[next...].hasPrefix("file://") || line[next...].hasPrefix("~/") {
                starts.append(next)
            }
            i = next
        }
        guard !starts.isEmpty else { return nil }
        let bounds = [line.startIndex] + starts + [line.endIndex]
        var out: [URL] = []
        var from = 0
        while from < bounds.count - 1 {
            var hit: Int?
            for to in (from + 1)..<bounds.count where exists(path(String(line[bounds[from]..<bounds[to]]))) { hit = to; break }
            guard let to = hit else { return nil }
            out.append(URL(fileURLWithPath: path(String(line[bounds[from]..<bounds[to]]))))
            from = to
        }
        return out
    }
}
