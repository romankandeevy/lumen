import AppKit
import LumenCore
import SwiftUI
import UniformTypeIdentifiers

// Вложения: «+» в поле ввода, перетаскивание и вставка картинки (⌘V). Копия — в папке Lumen,
// большие картинки ужимаются (длинная сторона 1568 px — больше модель всё равно не смотрит), HEIC и прочее → JPEG.

extension AppModel {
    /// Длинная сторона картинки для модели
    static let imageSide: CGFloat = 1568

    func importAttachment(_ url: URL) -> Attachment? {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url) {
            return importImage(image, name: url.lastPathComponent, original: url, type: type)
        }
        let id = UUID().uuidString.lowercased()
        let dest = paths.attachments.appendingPathComponent("\(id).\(url.pathExtension.isEmpty ? "bin" : url.pathExtension)")
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
        if type?.conforms(to: .pdf) == true {
            return Attachment(id: id, name: url.lastPathComponent, kind: .pdf, mime: "application/pdf", path: dest.path, size: size)
        }
        let textual = type.map { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) || $0.conforms(to: .json) || $0.conforms(to: .xml) } ?? false
            || ["md", "swift", "ts", "tsx", "js", "py", "yml", "yaml", "toml", "sh", "csv", "log"].contains(url.pathExtension.lowercased())
        if textual && size <= 2_000_000, (try? String(contentsOf: dest, encoding: .utf8)) != nil {
            return Attachment(id: id, name: url.lastPathComponent, kind: .text, mime: "text/plain", path: dest.path, size: size)
        }
        return Attachment(id: id, name: url.lastPathComponent, kind: .file, mime: type?.preferredMIMEType ?? "application/octet-stream",
                          path: dest.path, size: size)
    }

    /// Картинка из файла или буфера обмена. PNG/JPEG/GIF/WebP небольшие — как есть, остальное — JPEG нужного размера.
    func importImage(_ image: NSImage, name: String, original: URL? = nil, type: UTType? = nil) -> Attachment? {
        guard let rep = image.representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide > 0 ? rep.pixelsWide : Int(image.size.width))
        let h = CGFloat(rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(image.size.height))
        let id = UUID().uuidString.lowercased()
        let keep: [UTType: String] = [.png: "image/png", .jpeg: "image/jpeg", .gif: "image/gif", .webP: "image/webp"]
        if let original, let type, let mime = keep[type], max(w, h) <= Self.imageSide,
           let size = (try? original.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 3_500_000 {
            let dest = paths.attachments.appendingPathComponent("\(id).\(original.pathExtension.lowercased())")
            guard (try? FileManager.default.copyItem(at: original, to: dest)) != nil else { return nil }
            return Attachment(id: id, name: name, kind: .image, mime: mime, path: dest.path, size: size, width: Int(w), height: Int(h))
        }
        // уменьшить и сохранить JPEG
        let scale = min(1, Self.imageSide / max(w, h))
        let tw = max(1, Int((w * scale).rounded())), th = max(1, Int((h * scale).rounded()))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor.white.setFill() // у прозрачных PNG фон белый, JPEG прозрачности не знает
        NSRect(x: 0, y: 0, width: tw, height: th).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = out.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let dest = paths.attachments.appendingPathComponent("\(id).jpg")
        guard (try? data.write(to: dest)) != nil else { return nil }
        let base = (name as NSString).deletingPathExtension
        return Attachment(id: id, name: base + ".jpg", kind: .image, mime: "image/jpeg", path: dest.path, size: data.count, width: tw, height: th)
    }

    /// Файлы из перетаскивания или буфера: сначала ссылки на файлы, иначе — сама картинка
    func attach(_ providers: [NSItemProvider], add: @escaping @MainActor (Attachment) -> Void) {
        for item in providers {
            if item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = item.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in if let a = self.importAttachment(url) { add(a) } }
                }
            } else if item.canLoadObject(ofClass: NSImage.self) {
                _ = item.loadObject(ofClass: NSImage.self) { image, _ in
                    let data = (image as? NSImage)?.tiffRepresentation
                    Task { @MainActor in
                        if let data, let img = NSImage(data: data), let a = self.importImage(img, name: "Картинка") { add(a) }
                    }
                }
            }
        }
    }

    /// «+»: выбрать файлы и картинки
    func chooseAttachments() -> [Attachment] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Прикрепить"
        panel.message = "Картинки, PDF, тексты и любые файлы"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(importAttachment)
    }
}

// MARK: в поле ввода

/// Ряд вложений над полем: превью картинок и карточки файлов, крестик — убрать
struct AttachmentStrip: View {
    @Binding var items: [Attachment]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { a in
                    AttachmentThumb(attachment: a) { items.removeAll { $0.id == a.id } }
                }
            }
            .padding(.top, 6).padding(.trailing, 6)
        }
        .scrollIndicators(.never)
    }
}

private struct AttachmentThumb: View {
    let attachment: Attachment
    let remove: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Group {
            if attachment.kind == .image, let image = ThumbCache.image(attachment.url, side: 64) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
            } else {
                FileCard(attachment: attachment).frame(height: 64)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Icon("x", 10).foregroundStyle(p.foreground)
                    .frame(width: 18, height: 18)
                    .background(p.popover, in: Circle())
                    .overlay(Circle().strokeBorder(p.border))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .opacity(hover ? 1 : 0)
            .help("Убрать")
        }
        .onHover { hover = $0 }
        .help(attachment.name)
    }
}

/// Карточка файла: значок по виду, имя, размер
struct FileCard: View {
    let attachment: Attachment
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            Icon(attachment.kind == .pdf ? "file-text" : attachment.kind == .text ? "file-text" : "file", 18)
                .foregroundStyle(p.glow)
                .frame(width: 36, height: 36)
                .background(p.glow.opacity(0.08), in: RoundedRectangle(cornerRadius: R.md))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name).tw(13, .medium, lh: 18).lineLimit(1).truncationMode(.middle)
                Text(kindName + " · " + attachment.sizeText).tw(11, lh: 14).foregroundStyle(p.mutedFg)
            }
        }
        .padding(.leading, 10).padding(.trailing, 14)
        .frame(minWidth: 160, maxWidth: 240, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(p.card, in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }

    private var kindName: String {
        switch attachment.kind {
        case .pdf: "PDF"
        case .text: (attachment.name as NSString).pathExtension.uppercased().isEmpty ? "Текст" : (attachment.name as NSString).pathExtension.uppercased()
        case .image: "Картинка"
        case .file: "Файл"
        }
    }
}

// MARK: в переписке

/// Вложения отправленного сообщения, как в Claude: одна картинка — крупно, несколько — плиткой; файлы — карточками.
/// Щелчок по картинке или файлу открывает его.
struct MessageAttachments: View {
    let items: [Attachment]
    /// У человека — справа, у ответа — слева и крупнее (снимки страниц, рендеры)
    var leading = false
    @Environment(\.palette) private var p

    var body: some View {
        let images = items.filter { $0.kind == .image }
        let files = items.filter { $0.kind != .image }
        VStack(alignment: leading ? .leading : .trailing, spacing: 8) {
            if images.count == 1, let a = images.first, let image = ThumbCache.image(a.url, side: 520) {
                Button { open(a) } label: {
                    // рамка ровно по картинке, без пустых полей по бокам
                    let box = CGSize(width: leading ? 520 : 320, height: leading ? 400 : 280)
                    let k = min(box.width / max(image.size.width, 1), box.height / max(image.size.height, 1), 1)
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: image.size.width * k, height: image.size.height * k)
                        .clipShape(RoundedRectangle(cornerRadius: R.xl))
                        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                }
                .buttonStyle(.plain)
                .help("Открыть \(a.name)")
            } else if !images.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(leading ? 160 : 120), spacing: 6), count: min(3, images.count)),
                          alignment: leading ? .leading : .trailing, spacing: 6) {
                    ForEach(images) { a in
                        Button { open(a) } label: {
                            Group {
                                if let image = ThumbCache.image(a.url, side: 160) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                } else { p.card }
                            }
                            .frame(width: leading ? 160 : 120, height: leading ? 120 : 120)
                            .clipShape(RoundedRectangle(cornerRadius: R.lg))
                            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                        }
                        .buttonStyle(.plain)
                        .help("Открыть \(a.name)")
                    }
                }
            }
            if !files.isEmpty {
                FlowWrap(spacing: 6) {
                    ForEach(files) { a in
                        Button { open(a) } label: { FileCard(attachment: a).frame(height: 56) }
                            .buttonStyle(.plain)
                            .help("Открыть \(a.name)")
                    }
                }
            }
        }
    }

    private func open(_ a: Attachment) { NSWorkspace.shared.open(a.url) }
}

/// Картинки и файлы, которые показал агент, — как в Claude Code: маленькие превью в строку, при наведении — крупнее
/// на том же месте, много — первые четыре и «+N». Нажатие открывает файл.
struct AttachmentThumbs: View {
    let items: [Attachment]
    /// Открыть сбоку и скачать — для файлов (без app — открыть в программе по умолчанию)
    var app: AppModel?

    @Environment(\.palette) private var p
    @State private var hovered: String?
    @State private var all = false

    static let visible = 4

    var body: some View {
        let images = items.filter { $0.kind == .image }
        let files = items.filter { $0.kind != .image }
        VStack(alignment: .leading, spacing: 8) {
            // файлы от агента (make_file, show_in_chat): карточка — открыть сбоку, скачать
            if !files.isEmpty {
                FlowWrap(spacing: 6) { ForEach(files) { a in FileChip(attachment: a, app: app) } }
            }
            if !images.isEmpty { thumbs(images) }
        }
    }

    private func thumbs(_ items: [Attachment]) -> some View {
        let shown = all ? items : Array(items.prefix(Self.visible))
        let more = items.count - shown.count
        return FlowWrap(spacing: 6) {
            ForEach(shown) { a in thumb(a) }
            if more > 0 {
                Button { withAnimation(.easeOut(duration: 0.15)) { all = true } } label: {
                    Text("+\(more)").tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
                        .frame(width: 44, height: 36)
                        .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.md))
                        .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
                }
                .buttonStyle(.plain)
                .help("Показать все \(items.count)")
            }
        }
    }

    @ViewBuilder private func thumb(_ a: Attachment) -> some View {
        Button { NSWorkspace.shared.open(a.url) } label: {
            Group {
                if a.kind == .image, let img = ThumbCache.image(a.url) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Icon(a.kind == .pdf ? "file-text" : "file", 16).foregroundStyle(p.mutedFg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(p.card)
                }
            }
            .frame(width: 52, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: R.md))
            .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.border))
        }
        .buttonStyle(.plain)
        .help(a.name)
        .onHover { hovered = $0 ? a.id : (hovered == a.id ? nil : hovered) }
        // крупнее при наведении — над превью, мышь его не ловит
        .overlay(alignment: .bottomLeading) {
            if hovered == a.id, a.kind == .image, let img = ThumbCache.image(a.url) {
                let side: CGFloat = 300
                let ratio = img.size.width / max(img.size.height, 1)
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
                    .clipShape(RoundedRectangle(cornerRadius: R.lg))
                    .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                    .offset(y: -44)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .zIndex(hovered == a.id ? 10 : 0)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Уменьшенные копии картинок для превью: десятки снимков страниц не держат в памяти целиком
/// Превью картинок: с диска читаются один раз и уменьшаются (вложения в переписке, снимки шагов, артефакты).
/// Раньше вложения в переписке перечитывали и декодировали картинку целиком на каждой перерисовке (25.10)
enum ThumbCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()

    /// Не больше `side` pt по длинной стороне (пикселей вдвое больше — для Retina). Размер картинки в pt — как у оригинала
    static func image(_ url: URL, side: CGFloat = 360) -> NSImage? {
        let key = "\(url.path)|\(Int(side))" as NSString
        if let i = cache.object(forKey: key) { return i }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: side * 2,
                                                                   kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        var size = NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            // pt — как у NSImage(contentsOf:): пиксели × 72 / dpi; повёрнутые снимки — сторонами наоборот
            let k = 72 / ((props[kCGImagePropertyDPIWidth] as? CGFloat) ?? 72)
            let turned = ((props[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
            size = turned ? NSSize(width: h * k, height: w * k) : NSSize(width: w * k, height: h * k)
        }
        let img = NSImage(cgImage: cg, size: size)
        cache.setObject(img, forKey: key)
        return img
    }
}


/// Файл под ответом агента: значок, имя, размер; щелчок — открыть сбоку, «Скачать» — в «Загрузки»
struct FileChip: View {
    let attachment: Attachment
    let app: AppModel?

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button { if let app { app.preview(attachment) } else { NSWorkspace.shared.open(attachment.url) } } label: {
                HStack(spacing: 10) {
                    Group {
                        if attachment.isVideo { Image(systemName: "film").font(.system(size: 15)) }
                        else if attachment.isAudio { Image(systemName: "waveform").font(.system(size: 15)) }
                        else { Icon(attachment.kind == .pdf ? "file-text" : (attachment.kind == .text ? "file-text" : "file"), 18) }
                    }
                    .foregroundStyle(p.glow).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.name).tw(13, .medium, lh: 18).lineLimit(1)
                        Text(attachment.sizeText + (attachment.isVideo || attachment.isAudio ? " · проиграть сбоку" : " · открыть сбоку"))
                            .tw(11, lh: 14).foregroundStyle(p.mutedFg)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Открыть сбоку")
            Button { if let app { app.download(attachment) } } label: {
                Icon("download", 14).foregroundStyle(hover ? p.foreground : p.mutedFg)
                    .frame(width: 28, height: 28)
                    .background(p.foreground.opacity(hover ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: R.md))
            }
            .buttonStyle(.plain)
            .help("Скачать в «Загрузки»")
            .disabled(app == nil)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(p.card.opacity(0.6), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
        .onHover { hover = $0 }
    }
}
