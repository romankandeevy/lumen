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
            if attachment.kind == .image, let image = NSImage(contentsOf: attachment.url) {
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
    @Environment(\.palette) private var p

    var body: some View {
        let images = items.filter { $0.kind == .image }
        let files = items.filter { $0.kind != .image }
        VStack(alignment: .trailing, spacing: 8) {
            if images.count == 1, let a = images.first, let image = NSImage(contentsOf: a.url) {
                Button { open(a) } label: {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: R.xl))
                        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.border))
                }
                .buttonStyle(.plain)
                .help("Открыть \(a.name)")
            } else if !images.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 6), count: min(3, images.count)), alignment: .trailing, spacing: 6) {
                    ForEach(images) { a in
                        Button { open(a) } label: {
                            Group {
                                if let image = NSImage(contentsOf: a.url) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                } else { p.card }
                            }
                            .frame(width: 120, height: 120)
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
