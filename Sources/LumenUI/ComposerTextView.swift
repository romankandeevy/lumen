import AppKit
import LumenCore
import SwiftUI

/// Чип в поле ввода: позванный бот или выбранный навык. Живёт в самом тексте — на одном уровне с буквами:
/// переносится вместе с ними, не ограничивает ширину строки, стирается ⌫ как обычный символ.
struct FieldChip: Identifiable, Equatable {
    let id: String
    let title: String
    let tint: Color
    var bot: Bot?
    var symbol: String?

    static func == (a: FieldChip, b: FieldChip) -> Bool { a.id == b.id && a.title == b.title }
}

/// Как чип выглядит: значок и имя в цвете, на тонкой подложке; крестик — только подсказка, что можно убрать
private struct FieldChipView: View {
    let chip: FieldChip

    var body: some View {
        HStack(spacing: 5) {
            if let bot = chip.bot { BotAvatar(bot: bot, size: 16) }
            else if let symbol = chip.symbol { Icon(symbol, 12).foregroundStyle(chip.tint) }
            Text(chip.title).font(.geist(13, .medium)).foregroundStyle(chip.tint)
            Icon("x", 11).foregroundStyle(chip.tint.opacity(0.7))
        }
        .padding(.leading, 4).padding(.trailing, 7).frame(height: 24)
        .background(chip.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(chip.tint.opacity(0.3)))
        // справа зазор до текста — часть картинки, чтобы ⌫ стирал чип целиком
        .padding(.trailing, FieldChipAttachment.gap)
    }
}

/// Символ-вставка чипа в тексте поля
final class FieldChipAttachment: NSTextAttachment {
    static let gap: CGFloat = 6
    var chipID = ""
    /// Ширина самого чипа без зазора — по ней ловим щелчок по крестику
    var chipWidth: CGFloat = 0
}

/// Поле ввода сообщения: текст и чипы бота и навыка в одной строке. Вместо `TextField`, который чипы внутрь не пускает.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let chips: [FieldChip]
    let palette: Palette
    let placeholder: String
    @Binding var focused: Bool
    let minLines: Int
    let maxLines: Int
    var accessibilityLabel = "Сообщение"
    /// Return: (shift, command) → обработано ли; нет — вставится перенос строки
    var onReturn: (Bool, Bool) -> Bool = { _, _ in false }
    var onArrow: (Bool) -> Bool = { _ in false }
    var onTab: () -> Bool = { false }
    var onEscape: () -> Bool = { false }
    var onRemoveChip: (String) -> Void = { _ in }
    /// Вставили или бросили файлы и картинки
    var onFiles: ([NSItemProvider]) -> Void = { _ in }

    private static let lineGap: CGFloat = 4.5

    func makeNSView(context: Context) -> NSScrollView {
        let tv = FieldTextView()
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 2
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.setAccessibilityLabel(accessibilityLabel)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        tv.placeholder = placeholder
        tv.placeholderColor = NSColor(palette.mutedFg)
        tv.insertionPointColor = NSColor(palette.glow)
        tv.font = c.font
        tv.textColor = NSColor(palette.foreground)
        tv.defaultParagraphStyle = c.paragraph
        tv.typingAttributes = c.attributes
        c.sync(tv)
        if focused, tv.window != nil, tv.window?.firstResponder !== tv {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let tv = context.coordinator.textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let width = max(40, proposal.width ?? 400)
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let line = lm.defaultLineHeight(for: context.coordinator.font) + Self.lineGap
        let used = lm.usedRect(for: tc).height
        return CGSize(width: width, height: ceil(min(line * CGFloat(maxLines), max(line * CGFloat(minLines), used))))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: FieldTextView?
        private var syncing = false

        init(_ parent: ComposerTextView) { self.parent = parent }

        var font: NSFont {
            let size = 16.5 * Font.uiScale
            return NSFont(name: "Geist-Regular", size: size) ?? .systemFont(ofSize: size)
        }

        var paragraph: NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = ComposerTextView.lineGap
            return p
        }

        var attributes: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: NSColor(parent.palette.foreground), .paragraphStyle: paragraph]
        }

        // MARK: модель → поле

        /// Приводит поле к «чипы, потом текст»: вызывается при каждом обновлении SwiftUI
        func sync(_ tv: FieldTextView) {
            guard !syncing else { return }
            let (ids, plain) = Self.split(tv.textStorage)
            guard ids != parent.chips.map(\.id) || plain != parent.text else { return }
            let selection = tv.selectedRange()
            let before = Self.plainOffset(tv.textStorage, upTo: selection.location)
            let external = plain != parent.text
            syncing = true
            tv.textStorage?.setAttributedString(canonical(chips: parent.chips, text: parent.text))
            let caret = external ? tv.textStorage?.length ?? 0 : parent.chips.count + min(before, (parent.text as NSString).length)
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            syncing = false
            tv.needsDisplay = true
        }

        private func canonical(chips: [FieldChip], text: String) -> NSAttributedString {
            let out = NSMutableAttributedString()
            for chip in chips {
                let att = FieldChipAttachment()
                att.chipID = chip.id
                let renderer = ImageRenderer(content: FieldChipView(chip: chip).environment(\.palette, parent.palette))
                renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
                if let image = renderer.nsImage {
                    att.image = image
                    att.chipWidth = image.size.width - FieldChipAttachment.gap
                    att.bounds = CGRect(x: 0, y: -6, width: image.size.width, height: image.size.height)
                }
                let piece = NSMutableAttributedString(attachment: att)
                piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
                out.append(piece)
            }
            out.append(NSAttributedString(string: text, attributes: attributes))
            return out
        }

        /// Какие чипы в поле (по порядку) и что напечатано
        static func split(_ storage: NSTextStorage?) -> (ids: [String], plain: String) {
            guard let storage else { return ([], "") }
            var ids: [String] = []
            var plain = ""
            let s = storage.string as NSString
            for i in 0..<s.length {
                if let att = storage.attribute(.attachment, at: i, effectiveRange: nil) as? FieldChipAttachment {
                    ids.append(att.chipID)
                } else if s.character(at: i) != 0xFFFC {
                    plain.append(String(utf16CodeUnits: [s.character(at: i)], count: 1))
                }
            }
            return (ids, plain)
        }

        static func plainOffset(_ storage: NSTextStorage?, upTo location: Int) -> Int {
            guard let storage else { return 0 }
            let s = storage.string as NSString
            var n = 0
            for i in 0..<min(location, s.length) where s.character(at: i) != 0xFFFC { n += 1 }
            return n
        }

        // MARK: поле → модель

        func textDidChange(_ notification: Notification) {
            guard !syncing, let tv = textView else { return }
            let (ids, plain) = Self.split(tv.textStorage)
            let known = parent.chips.map(\.id)
            // ⌫ стёрло чип — сказать, какой
            for gone in known where !ids.contains(gone) { parent.onRemoveChip(gone) }
            if plain != parent.text { parent.text = plain }
            // что-то напечатали левее чипов — вернуть порядок «чипы, потом текст»
            let leading = Self.leadingChipCount(tv.textStorage)
            if leading != ids.count {
                let selection = tv.selectedRange()
                let offset = Self.plainOffset(tv.textStorage, upTo: selection.location)
                syncing = true
                let kept = parent.chips.filter { ids.contains($0.id) }
                tv.textStorage?.setAttributedString(canonical(chips: kept, text: plain))
                tv.setSelectedRange(NSRange(location: kept.count + offset, length: 0))
                syncing = false
            }
            tv.needsDisplay = true
        }

        static func leadingChipCount(_ storage: NSTextStorage?) -> Int {
            guard let storage else { return 0 }
            var n = 0
            while n < storage.length, storage.attribute(.attachment, at: n, effectiveRange: nil) is FieldChipAttachment { n += 1 }
            return n
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return parent.onReturn(flags.contains(.shift), flags.contains(.command))
            case #selector(NSResponder.moveDown(_:)): return parent.onArrow(true)
            case #selector(NSResponder.moveUp(_:)): return parent.onArrow(false)
            case #selector(NSResponder.insertTab(_:)): return parent.onTab()
            case #selector(NSResponder.cancelOperation(_:)): return parent.onEscape()
            default: return false
            }
        }

        func focusChanged(_ on: Bool) {
            DispatchQueue.main.async { [self] in if parent.focused != on { parent.focused = on } }
        }
    }
}

/// `NSTextView` с подсказкой, щелчком по крестику чипа и вставкой файлов отдельно от текста
final class FieldTextView: NSTextView {
    weak var coordinator: ComposerTextView.Coordinator?
    var placeholder = ""
    var placeholderColor: NSColor = .secondaryLabelColor

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { coordinator?.focusChanged(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { coordinator?.focusChanged(false) }
        return ok
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let coordinator, coordinator.parent.focused, window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    // MARK: подсказка

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !placeholder.isEmpty, let storage = textStorage, let lm = layoutManager, let tc = textContainer else { return }
        let (_, plain) = ComposerTextView.Coordinator.split(storage)
        guard plain.isEmpty else { return }
        // после чипов — на их строке; без чипов — в начале
        let chips = ComposerTextView.Coordinator.leadingChipCount(storage)
        var x = tc.lineFragmentPadding
        var y: CGFloat = 0
        if chips > 0 {
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: 0, length: chips), in: tc)
            x = rect.maxX
            y = rect.minY
        }
        let font = coordinator?.font ?? .systemFont(ofSize: 16.5)
        let lineH = lm.defaultLineHeight(for: font)
        let lineRect = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let top = chips > 0 ? lineRect.minY + (lineRect.height - lineH) / 2 : y
        NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: placeholderColor])
            .draw(at: NSPoint(x: x + textContainerOrigin.x, y: top + textContainerOrigin.y))
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    // MARK: крестик на чипе

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, let storage = textStorage {
            let origin = textContainerOrigin
            let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            let glyph = lm.glyphIndex(for: local, in: tc)
            let index = lm.characterIndexForGlyph(at: glyph)
            if index < storage.length, let att = storage.attribute(.attachment, at: index, effectiveRange: nil) as? FieldChipAttachment {
                let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
                // правый край самого чипа — крестик; остальное — просто курсор рядом
                if local.x >= rect.minX + att.chipWidth - 22, local.x <= rect.minX + att.chipWidth + 2 {
                    coordinator?.parent.onRemoveChip(att.chipID)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: вставка и перенос файлов

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let providers = Self.providers(from: pb) {
            coordinator?.parent.onFiles(providers)
        } else {
            pasteAsPlainText(sender)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let providers = Self.providers(from: sender.draggingPasteboard) {
            coordinator?.parent.onFiles(providers)
            return true
        }
        return super.performDragOperation(sender)
    }

    /// Файлы и картинки с буфера — отдельными вложениями; обычный текст — nil
    private static func providers(from pb: NSPasteboard) -> [NSItemProvider]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.compactMap { NSItemProvider(contentsOf: $0) }
        }
        if pb.string(forType: .string) == nil, let image = NSImage(pasteboard: pb) {
            return [NSItemProvider(object: image)]
        }
        return nil
    }
}
