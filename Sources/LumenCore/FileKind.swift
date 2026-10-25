import Foundation

/// Чем показывать файл в панели сбоку (как у Claude: для каждого вида — своё превью, а не браузер для всего).
/// Страницы — браузер; остальное — без адресной строки, «назад», «обновить»: нужно посмотреть, скопировать, скачать, показать курсором
/// и прикрепить к разговору.
public enum FileKind: String, Sendable, CaseIterable {
    /// Markdown — оформленным текстом
    case markdown
    /// Текст и код — моноширинным
    case text
    case pdf
    case image
    case video
    case audio
    /// Презентации, документы, таблицы (pptx, key, docx, xlsx, pages…) — системное превью Quick Look
    case office
    /// 3D-модели (usdz, obj, stl…) — системное превью Quick Look
    case model3d
    /// Страницы и макеты: обычный браузер
    case web
    /// Всё прочее: значок и «Открыть в программе»
    case other

    static let markdownExts: Set<String> = ["md", "markdown", "mdx"]
    static let textExts: Set<String> = [
        "txt", "text", "log", "json", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf", "csv", "tsv", "xml", "plist", "diff", "patch",
        "swift", "py", "js", "mjs", "ts", "tsx", "jsx", "css", "scss", "sh", "zsh", "bash", "rb", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp",
        "m", "mm", "sql", "php", "lua", "r", "tex", "srt", "vtt", "env", "gitignore", "dockerfile", "makefile", "lock", "rtf",
    ]
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "aac", "aiff", "aif", "flac", "caf"]
    static let officeExts: Set<String> = ["pptx", "ppt", "key", "odp", "docx", "doc", "pages", "odt", "xlsx", "xls", "numbers", "ods"]
    static let modelExts: Set<String> = ["usdz", "usd", "usda", "usdc", "reality", "obj", "stl", "dae", "scn", "ply", "abc"]
    static let webExts: Set<String> = ["html", "htm", "svg", "webm", "ogg", "ogv", "glb", "gltf"]

    public static func of(extension raw: String) -> FileKind {
        let ext = raw.lowercased()
        if markdownExts.contains(ext) { return .markdown }
        if ext == "pdf" { return .pdf }
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if officeExts.contains(ext) { return .office }
        if modelExts.contains(ext) { return .model3d }
        if webExts.contains(ext) { return .web }
        if textExts.contains(ext) { return .text }
        return .other
    }

    public static func of(_ url: URL) -> FileKind { of(extension: url.pathExtension) }

    /// Подпись для панели: «Markdown», «Презентация»…
    public var label: String {
        switch self {
        case .markdown: "Markdown"
        case .text: "Текст"
        case .pdf: "PDF"
        case .image: "Картинка"
        case .video: "Видео"
        case .audio: "Звук"
        case .office: "Документ"
        case .model3d: "3D-модель"
        case .web: "Страница"
        case .other: "Файл"
        }
    }

    public var icon: String {
        switch self {
        case .markdown, .text: "file-text"
        case .pdf: "file-text"
        case .image: "image"
        case .video: "play"
        case .audio: "music"
        case .office: "layout-grid"
        case .model3d: "box"
        case .web: "globe"
        case .other: "file"
        }
    }

    /// Можно выделить текст и отдать в разговор цитатой
    public var hasText: Bool { self == .markdown || self == .text || self == .pdf }
}
