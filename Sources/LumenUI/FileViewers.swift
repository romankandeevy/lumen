import AppKit
import AVKit
import LumenCore
import PDFKit
import Quartz
import SwiftUI
import WebKit

/// Файл в панели сбоку (как у Claude: для каждого вида — своё превью, а не браузер для всего).
/// Без адреса, «назад», «обновить» и терминала: посмотреть, скопировать, скачать, показать курсором и сразу прикрепить к разговору,
/// чтобы можно было на него сослаться.
struct FileTab: Equatable {
    let url: URL
    let name: String
    var kind: FileKind
}

struct FileTabView: View {
    @Bindable var app: AppModel
    let file: FileTab

    @Environment(\.palette) private var p
    /// Выделенный в просмотре текст (цитата для разговора)
    @State private var selection = ""
    /// Выделенный на картинке фрагмент
    @State private var region: NSImage?
    @State private var attached = false
    @State private var copied = false

    private var hasPointer: Bool { !selection.isEmpty || region != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            p.border.frame(height: 1)
            ZStack(alignment: .bottom) {
                viewer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if hasPointer { pointerBar.padding(12).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(.easeOut(duration: 0.18), value: hasPointer)
        }
        // другой файл — прежнее выделение не переносится
        .onChange(of: file) { selection = ""; region = nil; attached = false; copied = false }
    }

    // MARK: шапка

    private var header: some View {
        HStack(spacing: 10) {
            Icon(file.kind.icon, 16).foregroundStyle(p.glow)
                .frame(width: 30, height: 30)
                .background(p.glow.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(file.name).tw(13, .medium, lh: 17).lineLimit(1).truncationMode(.middle)
                Text(subtitle).tw(11.5, lh: 15).foregroundStyle(p.mutedFg).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                app.attachToChat(file.url)
                attached = true
            } label: {
                HStack(spacing: 6) {
                    Icon(attached ? "check" : "paperclip", 13)
                    Text(attached ? "В поле" : "В чат").tw(12.5, .medium, lh: 16)
                }
                .foregroundStyle(attached ? p.accentSoft : p.onGlow)
                .padding(.horizontal, 11).frame(height: 28)
                .background(attached ? p.accentTint : p.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Прикрепить этот файл к разговору — на него можно ссылаться")
            BrowserTool(icon: copied ? "check" : "copy", help: copyHelp) { copyWhole() }
            BrowserTool(icon: "download", help: "Скачать в «Загрузки»") { app.downloadFile(file.url, name: file.name) }
            BrowserTool(icon: "external-link", help: "Открыть в программе") { NSWorkspace.shared.open(file.url) }
            BrowserTool(icon: "folder-open", help: "Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            p.border.frame(width: 1, height: 16).padding(.horizontal, 2)
            BrowserTool(icon: "x", help: "Закрыть панель · ⇧⌘B") { app.browserOpen = false }
        }
        .padding(.horizontal, 10).frame(height: 50)
    }

    private var subtitle: String {
        let size = ((try? file.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [file.kind.label, size].compactMap { $0 }.joined(separator: " · ")
    }

    private var copyHelp: String {
        switch file.kind {
        case .markdown, .text: "Копировать весь текст"
        case .image: "Копировать картинку"
        default: "Копировать файл"
        }
    }

    private func copyWhole() {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch file.kind {
        case .markdown, .text:
            if let text = try? String(contentsOf: file.url, encoding: .utf8) { pb.setString(text, forType: .string) } else { pb.writeObjects([file.url as NSURL]) }
        case .image:
            if let image = NSImage(contentsOf: file.url) { pb.writeObjects([image]) } else { pb.writeObjects([file.url as NSURL]) }
        default:
            pb.writeObjects([file.url as NSURL])
        }
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
    }

    // MARK: показать курсором → в чат

    private var pointerBar: some View {
        HStack(spacing: 10) {
            if let region {
                Image(nsImage: region).resizable().scaledToFill().frame(width: 42, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Фрагмент картинки").tw(12.5, lh: 16).foregroundStyle(p.mutedFg)
            } else {
                Icon("message-square-quote", 15).foregroundStyle(p.glow)
                Text("«" + selection.replacingOccurrences(of: "\n", with: " ").prefix(70) + (selection.count > 70 ? "…" : "") + "»")
                    .tw(12.5, lh: 16).foregroundStyle(p.foreground.opacity(0.85)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if region == nil {
                Button { copySelection() } label: {
                    Text("Копировать").tw(12, lh: 16).foregroundStyle(p.mutedFg).padding(.horizontal, 8).frame(height: 26)
                }
                .buttonStyle(.plain)
            }
            Button { sendPointer() } label: {
                HStack(spacing: 5) {
                    Icon("paperclip", 12)
                    Text("В чат").tw(12.5, .medium, lh: 16)
                }
                .foregroundStyle(p.onGlow).padding(.horizontal, 11).frame(height: 26)
                .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(region == nil ? "Вставить выделенное в поле ввода цитатой" : "Прикрепить фрагмент к разговору")
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(p.popover, in: RoundedRectangle(cornerRadius: R.xl))
        .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(p.glow.opacity(0.35)))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }

    private func copySelection() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection, forType: .string)
    }

    private func sendPointer() {
        if let region {
            app.attachImage(region, name: "Фрагмент — \(file.name).png")
            self.region = nil
        } else {
            app.quoteToChat(selection, from: file.name)
            selection = ""
        }
    }

    // MARK: просмотр по виду

    @ViewBuilder private var viewer: some View {
        switch file.kind {
        case .markdown, .text:
            TextFileViewer(url: file.url, name: file.name, onSelect: { selection = $0 })
        case .pdf:
            PDFFileViewer(url: file.url, onSelect: { selection = $0 })
        case .image:
            ImagePointViewer(url: file.url, onRegion: { region = $0 })
        case .video, .audio:
            MediaFileViewer(url: file.url)
        case .office, .model3d:
            QuickLookViewer(url: file.url)
        case .web, .other:
            VStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 72, height: 72)
                Text("Этот файл не показать здесь").tw(13, lh: 18).foregroundStyle(p.mutedFg)
                Button { NSWorkspace.shared.open(file.url) } label: {
                    Text("Открыть в программе").tw(13, .medium, lh: 18).padding(.horizontal, 14).frame(height: 30)
                        .background(p.secondary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Markdown и текст

/// Текст файла: Markdown — оформленным, остальное — моноширинным. Выделение уходит наверх (цитата в чат)
struct TextFileViewer: NSViewRepresentable {
    let url: URL
    let name: String
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let script = WKUserScript(source: """
            document.addEventListener('selectionchange', function () {
              clearTimeout(window.__lumenSel);
              window.__lumenSel = setTimeout(function () { window.webkit.messageHandlers.sel.postMessage(String(window.getSelection())); }, 120);
            });
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(script)
        cfg.userContentController.add(context.coordinator, name: "sel")
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        context.coordinator.onSelect = onSelect
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        let text = (try? String(contentsOf: url, encoding: .utf8)).map { String($0.prefix(2_000_000)) } ?? "Файл не читается как текст."
        v.loadHTMLString(MarkdownHTML.page(name: name, text: text), baseURL: url.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onSelect: (String) -> Void = { _ in }
        var loaded: URL?

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            onSelect((message.body as? String) ?? "")
        }
    }
}

// MARK: PDF

struct PDFFileViewer: NSViewRepresentable {
    let url: URL
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = .clear
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: v, queue: .main) { [weak v] _ in
            let text = v?.currentSelection?.string ?? ""
            MainActor.assumeIsolated { context.coordinator.onSelect(text) }
        }
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        context.coordinator.onSelect = onSelect
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }

    final class Coordinator {
        var onSelect: (String) -> Void = { _ in }
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

// MARK: картинка: показать курсором

/// Картинка по ширине панели; тянешь курсором — выделяется фрагмент, его можно сразу отправить в чат
struct ImagePointViewer: NSViewRepresentable {
    let url: URL
    let onRegion: (NSImage?) -> Void

    func makeNSView(context: Context) -> ImagePointView {
        let v = ImagePointView()
        v.onRegion = onRegion
        v.image = NSImage(contentsOf: url)
        return v
    }

    func updateNSView(_ v: ImagePointView, context: Context) {
        v.onRegion = onRegion
        if v.sourceURL != url { v.sourceURL = url; v.image = NSImage(contentsOf: url); v.region = nil; v.needsDisplay = true }
    }
}

final class ImagePointView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var sourceURL: URL?
    var region: CGRect?
    var onRegion: (NSImage?) -> Void = { _ in }
    private var start: CGPoint?

    override var isFlipped: Bool { true }

    /// Где картинка лежит в этом виде: по размеру, по центру, не больше исходного
    private var fitted: CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let pad: CGFloat = 16
        let box = bounds.insetBy(dx: pad, dy: pad)
        let k = min(box.width / image.size.width, box.height / image.size.height, 1)
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let r = fitted
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: r)
        guard let region else { return }
        NSColor.black.withAlphaComponent(0.45).setFill()
        let path = NSBezierPath(rect: r)
        path.append(NSBezierPath(rect: region))
        path.windingRule = .evenOdd
        path.fill()
        NSColor.controlAccentColor.setStroke()
        let edge = NSBezierPath(rect: region)
        edge.lineWidth = 1.5
        edge.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        start = p
        if region != nil { region = nil; onRegion(nil); needsDisplay = true }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        region = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y)).intersection(fitted)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        guard let r = region, r.width > 6, r.height > 6, let image else { region = nil; needsDisplay = true; return }
        let f = fitted
        // в координатах исходной картинки
        let k = image.size.width / f.width
        let crop = CGRect(x: (r.minX - f.minX) * k, y: (r.minY - f.minY) * k, width: r.width * k, height: r.height * k)
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return }
        // пикселей у картинки может быть больше, чем «точек»
        let pk = CGFloat(cg.width) / image.size.width
        let px = CGRect(x: crop.minX * pk, y: crop.minY * pk, width: crop.width * pk, height: crop.height * pk).integral
        guard let part = cg.cropping(to: px) else { return }
        onRegion(NSImage(cgImage: part, size: NSSize(width: crop.width, height: crop.height)))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}

// MARK: видео и звук

struct MediaFileViewer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.player = AVPlayer(url: url)
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if (v.player?.currentItem?.asset as? AVURLAsset)?.url != url { v.player = AVPlayer(url: url) }
    }

    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause() }
}

// MARK: презентации, документы, 3D — системное превью

/// Quick Look: Keynote, PowerPoint, Word, Excel, Pages, USDZ, OBJ, STL — как в Finder по пробелу
struct QuickLookViewer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL)?.absoluteURL != url { v.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
