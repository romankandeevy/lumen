import AppKit
import LumenCore
import SwiftUI

/// Текст переписки с настоящими ссылками (Рома, 18.10): ссылка открывается обычным кликом, без ⌘;
/// под курсором подчёркивается — видно, где она начинается и кончается; адрес — во всплывающей подсказке.
/// Где открыть — по настройке («Отображение чата» → «Ссылки»), ⌘-клик — в другом месте. Текст выделяется и копируется.
/// SwiftUI-`Text` с выделением открывал ссылки только по ⌘-клику и не умел подсвечивать ссылку под курсором.
struct LinkText: NSViewRepresentable {
    /// Markdown целиком: заголовки, списки, цитаты и линии рисуются здесь же — один выделяемый текст, а не по абзацу на вид
    let source: String
    var size: CGFloat = 15
    var lineHeight: CGFloat = 24.75
    /// Пока ответ печатается — в конце мигает светящийся курсор
    var caret = false

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
        v.barColor = NSColor(p.foreground.opacity(0.22))
        v.ruleColor = NSColor(p.borderBase.opacity(0.14))
        v.setCaret(caret, color: NSColor(p.glow), height: m.size * 1.1)
        guard context.coordinator.text != source || context.coordinator.key != key else { return }
        context.coordinator.text = source
        context.coordinator.key = key
        v.linkTextAttributes = [.foregroundColor: NSColor(p.glow), .cursor: NSCursor.pointingHand]
        v.textContainerInset = NSSize(width: 0, height: m.extra / 2)
        v.setText(Self.styledBlocks(source, base: m.font, size: m.size, extra: m.extra, color: NSColor(p.textBody), muted: NSColor(p.mutedFg)))
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
        var text: String?
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
        return runs(text, base: base, size: size, para: para, color: color)
    }

    /// Строчная разметка одного блока с заданным стилем абзаца
    static func runs(_ text: AttributedString, base: NSFont, size: CGFloat, para: NSParagraphStyle, color: NSColor, bold forceBold: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in text.runs {
            var font = forceBold ? bold(base) : base
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: para]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = .monospacedSystemFont(ofSize: size * 0.9, weight: forceBold ? .semibold : .regular) }
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

    /// Весь ответ одним текстом: заголовки крупнее и жирно, списки с отступом и маркерами, цитата с чертой, линия «---».
    /// Выделяется и копируется целиком — через абзацы, списки и заголовки
    @MainActor static func styledBlocks(_ source: String, base: NSFont, size: CGFloat, extra: CGFloat, color: NSColor, muted: NSColor) -> NSAttributedString {
        let blocks = MarkdownBlocks.parse(source)
        let out = NSMutableAttributedString()
        for (i, b) in blocks.enumerated() {
            let last = i == blocks.count - 1
            let next: MDBlock? = last ? nil : blocks[i + 1]
            let para = NSMutableParagraphStyle()
            para.lineSpacing = extra
            var extraAttrs: [NSAttributedString.Key: Any] = [:]
            var piece: NSAttributedString
            switch b {
            case .paragraph(let t):
                para.paragraphSpacing = last ? 0 : 12
                piece = runs(RichText.inline(t), base: base, size: size, para: para, color: color)
            case .heading(let level, let t):
                let k: CGFloat = level == 1 ? 1.38 : level == 2 ? 1.22 : level == 3 ? 1.1 : 1.0
                let f = scaled(bold(base), k)
                para.paragraphSpacingBefore = i == 0 ? 0 : 6
                para.paragraphSpacing = last ? 0 : 6
                piece = runs(RichText.inline(t), base: f, size: size * k, para: para, color: color, bold: true)
            case .bullet(let depth, let t):
                piece = item(marker: depth == 0 ? "•" : "◦", depth: depth, hang: 16, text: t, base: base, size: size, para: para, color: color, muted: muted, next: next, last: last)
            case .ordered(let depth, let num, let t):
                piece = item(marker: num + ".", depth: depth, hang: 22, text: t, base: base, size: size, para: para, color: color, muted: muted, next: next, last: last)
            case .quote(let t):
                para.firstLineHeadIndent = 14
                para.headIndent = 14
                para.paragraphSpacing = last ? 0 : 12
                piece = runs(RichText.inline(t), base: base, size: size, para: para, color: muted)
                extraAttrs[.lumenQuote] = true
            case .rule:
                para.minimumLineHeight = 26
                para.maximumLineHeight = 26
                para.paragraphSpacing = last ? 0 : 12
                piece = NSAttributedString(string: "\u{200B}", attributes: [.font: base, .foregroundColor: color, .paragraphStyle: para])
                extraAttrs[.lumenRule] = true
            }
            let mutable = NSMutableAttributedString(attributedString: piece)
            // конец абзаца несёт тот же стиль (а у линии и цитаты — ещё и отметку для рисования)
            let style = (piece.length > 0 ? piece.attribute(.paragraphStyle, at: piece.length - 1, effectiveRange: nil) : nil) ?? para
            if !last { mutable.append(NSAttributedString(string: "\n", attributes: [.font: base, .foregroundColor: color, .paragraphStyle: style])) }
            if !extraAttrs.isEmpty { mutable.addAttributes(extraAttrs, range: NSRange(location: 0, length: mutable.length)) }
            out.append(mutable)
        }
        return out
    }

    /// Пункт списка: маркер, табуляция, текст; перенос строки встаёт под текст, а не под маркер
    @MainActor private static func item(marker: String, depth: Int, hang: CGFloat, text: String, base: NSFont, size: CGFloat,
                                        para: NSMutableParagraphStyle, color: NSColor, muted: NSColor, next: MDBlock?, last: Bool) -> NSAttributedString {
        let indent = CGFloat(depth) * 20
        para.firstLineHeadIndent = indent
        para.headIndent = indent + hang
        para.tabStops = [NSTextTab(textAlignment: .left, location: indent + hang)]
        para.defaultTabInterval = hang
        para.paragraphSpacing = last ? 0 : ((next?.isListItem ?? false) ? 4 : 12)
        let out = NSMutableAttributedString(string: marker + "\t", attributes: [.font: base, .foregroundColor: muted, .paragraphStyle: para])
        out.append(runs(RichText.inline(text), base: base, size: size, para: para, color: color))
        return out
    }

    private static func scaled(_ f: NSFont, _ k: CGFloat) -> NSFont {
        k == 1 ? f : (NSFont(descriptor: f.fontDescriptor, size: f.pointSize * k) ?? f)
    }

    private static func bold(_ f: NSFont) -> NSFont {
        if f.fontName.hasPrefix("Geist") { return NSFont(name: "Geist-SemiBold", size: f.pointSize) ?? f }
        let b = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
        return b.fontName == f.fontName ? .boldSystemFont(ofSize: f.pointSize) : b
    }
}

extension NSAttributedString.Key {
    /// Абзац-цитата: слева рисуется черта
    static let lumenQuote = NSAttributedString.Key("lumenQuote")
    /// Абзац-линия «---»: через всю ширину рисуется тонкая черта
    static let lumenRule = NSAttributedString.Key("lumenRule")
}

/// NSTextView только для чтения: клик по ссылке открывает её, ссылка под курсором подчёркивается
final class LinkTextView: NSTextView {
    private var hovered: NSRange?
    var barColor: NSColor = .tertiaryLabelColor
    var ruleColor: NSColor = .separatorColor
    private let caretLayer = CALayer()
    private var showsCaret = false
    private var caretHeight: CGFloat = 18

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
        needsDisplay = true
        updateCaret()
    }

    // MARK: черта цитаты, линия и курсор

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let l = layoutManager, let c = textContainer, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let all = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.lumenQuote, in: all) { v, range, _ in
            guard v != nil else { return }
            let glyphs = l.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = l.boundingRect(forGlyphRange: glyphs, in: c)
            r.origin.x += origin.x; r.origin.y += origin.y
            barColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: r.minY + 2, width: 3, height: max(4, r.height - 4)), xRadius: 1.5, yRadius: 1.5).fill()
        }
        storage.enumerateAttribute(.lumenRule, in: all) { v, range, _ in
            guard v != nil else { return }
            let g = l.glyphIndexForCharacter(at: range.location)
            var r = l.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
            r.origin.y += origin.y
            ruleColor.setFill()
            NSRect(x: 0, y: (r.midY).rounded(), width: bounds.width, height: 1).fill()
        }
    }

    func setCaret(_ on: Bool, color: NSColor, height: CGFloat) {
        showsCaret = on
        caretHeight = height
        caretLayer.backgroundColor = color.cgColor
        caretLayer.cornerRadius = 1
        if on {
            wantsLayer = true
            if caretLayer.superlayer == nil { layer?.addSublayer(caretLayer) }
            if caretLayer.animation(forKey: "blink") == nil {
                // мигает 1 с «шагами»: полсекунды горит, полсекунды нет (`.caret` в макете)
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [1, 0]
                a.keyTimes = [0, 0.5]
                a.calculationMode = .discrete
                a.duration = 1
                a.repeatCount = .infinity
                caretLayer.add(a, forKey: "blink")
            }
        } else {
            caretLayer.removeAnimation(forKey: "blink")
        }
        updateCaret()
    }

    /// Курсор — сразу за последней буквой
    private func updateCaret() {
        caretLayer.isHidden = !showsCaret
        guard showsCaret, let l = layoutManager, let c = textContainer else { return }
        l.ensureLayout(for: c)
        let n = l.numberOfGlyphs
        var x: CGFloat = 0, y: CGFloat = 0, h = caretHeight
        if n > 0 {
            let r = l.lineFragmentUsedRect(forGlyphAt: n - 1, effectiveRange: nil)
            x = r.maxX + 3
            h = min(caretHeight, max(8, r.height))
            y = r.minY + max(0, (r.height - h) / 2)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.frame = CGRect(x: x + textContainerOrigin.x, y: y + textContainerOrigin.y, width: 2, height: h)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateCaret()
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
