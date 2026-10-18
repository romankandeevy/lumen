import AppKit
import Foundation
import Testing
@testable import LumenCore
@testable import LumenUI

@MainActor @Test func bareAddressesBecomeLinksButFileNamesDoNot() {
    let a = RichText.markdown("Сайт https://kandeev.com/about, зеркало www.example.org и файл README.md, код `https://x.dev` и [доки](https://docs.dev)")
    let links = a.runs.compactMap { run in run.link.map { (String(a[run.range].characters), $0.absoluteString) } }
    #expect(links.contains { $0.0 == "https://kandeev.com/about" && $0.1 == "https://kandeev.com/about" })
    #expect(links.contains { $0.0 == "www.example.org" })
    #expect(links.contains { $0.0 == "доки" && $0.1 == "https://docs.dev" })
    #expect(!links.contains { $0.0.contains("README") })
    #expect(!links.contains { $0.0.contains("x.dev") }) // в коде не трогаем
}

@MainActor @Test func linkTextKeepsLinksAndStylesAndFindsLinkUnderCursor() throws {
    let a = RichText.markdown("Открой **сайт** https://kandeev.com сейчас")
    let base = NSFont(name: "Geist-Regular", size: 15) ?? .systemFont(ofSize: 15)
    let s = LinkText.styled(a, base: base, size: 15, extra: 4, color: .white)
    let ns = s.string as NSString
    let at = ns.range(of: "https://kandeev.com")
    #expect((s.attribute(.link, at: at.location, effectiveRange: nil) as? URL)?.absoluteString == "https://kandeev.com")
    let bold = s.attribute(.font, at: ns.range(of: "сайт").location, effectiveRange: nil) as? NSFont
    #expect(bold?.fontName != base.fontName)

    let v = LinkTextView()
    v.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
    v.setText(s)
    let h = v.height(for: 600)
    #expect(h > 10 && h < 60)
    let l = try #require(v.layoutManager), c = try #require(v.textContainer)
    let glyphs = l.glyphRange(forCharacterRange: NSRange(location: at.location + 3, length: 1), actualCharacterRange: nil)
    let r = l.boundingRect(forGlyphRange: glyphs, in: c)
    let inside = NSPoint(x: r.midX + v.textContainerOrigin.x, y: r.midY + v.textContainerOrigin.y)
    #expect(v.link(at: inside) == at)
    #expect(v.link(at: NSPoint(x: 2, y: r.midY + v.textContainerOrigin.y)) == nil)
}

@Test func linkTargetDefaultsToSideBrowser() throws {
    let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(old.linkTarget == .side)
    var p = old
    p.linkTarget = .system
    let back = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
    #expect(back.linkTarget == .system)
}

/// Курсор над ссылкой — она подчёркивается целиком; ушёл — подчёркивание пропадает
@MainActor @Test func hoveredLinkIsUnderlined() throws {
    let a = RichText.markdown("Смотри https://kandeev.com/about и дальше")
    let s = LinkText.styled(a, base: .systemFont(ofSize: 15), size: 15, extra: 4, color: .white)
    let at = (s.string as NSString).range(of: "https://kandeev.com/about")
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    let v = LinkTextView()
    v.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
    w.contentView = v
    v.setText(s)
    _ = v.height(for: 600)
    let l = try #require(v.layoutManager), c = try #require(v.textContainer)
    let r = l.boundingRect(forGlyphRange: l.glyphRange(forCharacterRange: NSRange(location: at.location + 5, length: 1), actualCharacterRange: nil), in: c)
    func move(to p: NSPoint) throws {
        let e = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: v.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                                 windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        v.mouseMoved(with: e)
    }
    try move(to: NSPoint(x: r.midX + v.textContainerOrigin.x, y: r.midY + v.textContainerOrigin.y))
    var eff = NSRange()
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: at.location + 1, effectiveRange: &eff) != nil)
    #expect(eff == at)
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: 1, effectiveRange: nil) == nil)
    try move(to: NSPoint(x: 1, y: r.midY + v.textContainerOrigin.y))
    #expect(l.temporaryAttribute(.underlineStyle, atCharacterIndex: at.location + 1, effectiveRange: nil) == nil)
}
