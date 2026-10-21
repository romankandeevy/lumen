import AppKit
import LumenCore
import SwiftUI

/// Текст переписки с настоящими ссылками (Рома, 18.10): ссылка открывается обычным кликом, без ⌘;
/// под курсором подчёркивается — видно, где она начинается и кончается; адрес — во всплывающей подсказке.
/// Где открыть — по настройке («Отображение чата» → «Ссылки»), ⌘-клик — в другом месте. Текст выделяется и копируется.
/// SwiftUI-`Text` с выделением открывал ссылки только по ⌘-клику и не умел подсвечивать ссылку под курсором.
struct LinkText: NSViewRepresentable {
    let text: AttributedString
    var size: CGFloat = 15
    var lineHeight: CGFloat = 24.75

    @Environment(\.palette) private var p
    @Environment(\.chatText) private var t
    @Environment(\.openURL) private var openURL

    func makeNSView(context: Context) -> LinkTextView {
        let v = LinkTextView()
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ v: LinkTextView, context: Context) {
        context.coordinator.open = { openURL($0) }
        let m = metrics
        let key = "\(t.font)|\(t.scale)|\(Font.uiScale)|\(p.foreground)|\(p.glow)"
        guard context.coordinator.text != text || context.coordinator.key != key else { return }
        context.coordinator.text = text
        context.coordinator.key = key
        v.linkTextAttributes = [.foregroundColor: NSColor(p.glow), .cursor: NSCursor.pointingHand]
        v.textContainerInset = NSSize(width: 0, height: m.extra / 2)
        v.setText(Self.styled(text, base: m.font, size: m.size, extra: m.extra, color: NSColor(p.textBody)))
        v.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: LinkTextView, context: Context) -> CGSize? {
        if let w = proposal.width, w.isFinite, w > 0 { return CGSize(width: w, height: v.height(for: w)) }
        let natural = v.naturalSize()
        return natural
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var open: (URL) -> Void = { _ in }
        var text: AttributedString?
        var key = ""

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            open(url)
            return true
        }
    }

    /// Шрифт и высота строки — как у `chatTw`: «Шрифты и масштаб» и масштаб интерфейса
    private var metrics: (font: NSFont, size: CGFloat, extra: CGFloat) {
        let scale = CGFloat(t.scale)
        switch t.font {
        case .geist:
            let s = size * scale * Font.uiScale, l = lineHeight * scale * Font.uiScale
            return (NSFont(name: "Geist-Regular", size: s) ?? .systemFont(ofSize: s), s, max(0, l - LineMetrics.geistHeight(s)))
        case .system, .serif, .mono:
            let s = size * scale, l = lineHeight * scale
            let sys = NSFont.systemFont(ofSize: s)
            let extra = max(0, l - ceil(sys.ascender - sys.descender + sys.leading))
            switch t.font {
            case .serif: return (sys.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: s) } ?? sys, s, extra)
            case .mono: return (.monospacedSystemFont(ofSize: s * 0.92, weight: .regular), s, extra)
            default: return (sys, s, extra)
            }
        }
    }

    /// Markdown (жирный, курсив, код, зачёркнутый, ссылки) — в атрибуты AppKit
    static func styled(_ text: AttributedString, base: NSFont, size: CGFloat, extra: CGFloat, color: NSColor) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = extra
        let out = NSMutableAttributedString()
        for run in text.runs {
            var font = base
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: para]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = .monospacedSystemFont(ofSize: size * 0.9, weight: .regular) }
                if intent.contains(.stronglyEmphasized) { font = bold(font) }
                if intent.contains(.emphasized) {
                    let it = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    if it.fontName == font.fontName { attrs[.obliqueness] = 0.18 } else { font = it }
                }
                if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            attrs[.font] = font
            if let link = run.link { attrs[.link] = link }
            out.append(NSAttributedString(string: String(text[run.range].characters), attributes: attrs))
        }
        return out
    }

    private static func bold(_ f: NSFont) -> NSFont {
        if f.fontName.hasPrefix("Geist") { return NSFont(name: "Geist-SemiBold", size: f.pointSize) ?? f }
        let b = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
        return b.fontName == f.fontName ? .boldSystemFont(ofSize: f.pointSize) : b
    }
}

/// NSTextView только для чтения: клик по ссылке открывает её, ссылка под курсором подчёркивается
final class LinkTextView: NSTextView {
    private var hovered: NSRange?

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        displaysLinkToolTips = true
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) { nil }

    func setText(_ s: NSAttributedString) {
        setHovered(nil)
        textStorage?.setAttributedString(s)
    }

    /// Высота текста при этой ширине
    func height(for width: CGFloat) -> CGFloat {
        guard let c = textContainer, let l = layoutManager else { return 0 }
        c.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        l.ensureLayout(for: c)
        return ceil(l.usedRect(for: c).height + textContainerInset.height * 2)
    }

    /// Размер в одну строку (когда ширину не предлагают)
    func naturalSize() -> CGSize {
        guard let c = textContainer, let l = layoutManager else { return .zero }
        c.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        l.ensureLayout(for: c)
        let r = l.usedRect(for: c)
        return CGSize(width: ceil(r.width), height: ceil(r.height + textContainerInset.height * 2))
    }

    // MARK: ссылка под курсором

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas where a.owner === self && a.userInfo?["lumenLink"] != nil { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: ["lumenLink": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(link(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(nil)
    }

    /// Диапазон ссылки под точкой; не ссылка — nil
    func link(at point: NSPoint) -> NSRange? {
        guard let l = layoutManager, let c = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let pt = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = l.glyphIndex(for: pt, in: c, fractionOfDistanceThroughGlyph: &fraction)
        guard l.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: c).contains(pt) else { return nil }
        let i = l.characterIndexForGlyph(at: glyph)
        var range = NSRange()
        guard i < storage.length, storage.attribute(.link, at: i, effectiveRange: &range) != nil else { return nil }
        return range
    }

    private func setHovered(_ r: NSRange?) {
        guard r != hovered, let l = layoutManager else { return }
        let length = textStorage?.length ?? 0
        if let old = hovered, NSMaxRange(old) <= length { l.removeTemporaryAttribute(.underlineStyle, forCharacterRange: old) }
        if let r { l.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: r) }
        hovered = r
    }
}
