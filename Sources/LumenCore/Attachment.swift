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
            t += "\n\n(Вложения сохранены: " + attachments.map { "\($0.name) — \($0.path)" }.joined(separator: "; ") + ")"
        }
        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(["type": "text", "text": t]) }
        return blocks
    }

    /// Текстовые файлы и не-картинки — в текст запроса (для ChatGPT, у которого картинки идут отдельно)
    public static func inlineText(_ attachments: [Attachment]) -> String {
        attachments.filter { $0.kind != .image }.compactMap { $0.contentBlock()?["text"] as? String }.joined(separator: "\n\n")
    }
}
