import AppKit
import SwiftUI
import LumenCore
import Testing
@testable import LumenUI

/// Кнопки окна на линии шапки (26.10): дальше от края, центр на TitleBar.lineY; нажимаются; после ресайза — на месте
@MainActor @Test(.serialized) func trafficLightsSitOnTheTitleLine() async throws {
    let size = CGRect(x: 0, y: 0, width: 900, height: 600)
    let window = NSWindow(contentRect: size, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: Color.clear.background(TrafficLights().frame(width: 0, height: 0)))
    window.orderFront(nil)
    defer { window.close() }

    func check(_ label: String) async throws {
        for _ in 0..<6 { window.contentView?.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50)) }
        let height = window.contentLayoutRect.maxY > 0 ? window.frame.height : 600
        for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            let b = try #require(window.standardWindowButton(t))
            let r = b.convert(b.bounds, to: nil)           // в окне, y — от низа
            let fromTop = height - r.midY
            print("\(label) кнопка \(i): x=\(r.minX) центр от верха=\(fromTop)")
            #expect(abs(r.minX - (TitleBar.lightsX + TitleBar.lightsGap * CGFloat(i))) < 1)
            #expect(abs(fromTop - TitleBar.lineY) < 1.5)
            // щелчок по центру кнопки попадает в неё
            let hit = window.contentView?.superview?.hitTest(NSPoint(x: r.midX, y: r.midY))
            #expect(hit === b || hit?.isDescendant(of: b) == true, "\(label): кнопка \(i) не нажимается")
        }
    }
    try await check("сразу")
    window.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 700), display: true)
    try await check("после ресайза")
}

/// Шапка окна стала выше — «панель» и «поиск» под ней по-прежнему нажимаются (клик доходит до Lumen, а не до заголовка)
@MainActor @Test(.serialized) func titleBarDoesNotSwallowPanelButtons() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lumen-tb-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let app = try AppModel(paths: AppPaths(root: home))
    app.finishOnboarding(name: "Рома", address: .ty, backend: .subscription, theme: .lumen)
    let size = CGRect(x: 0, y: 0, width: 1100, height: 700)
    let window = NSWindow(contentRect: size, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: RootView(app: app))
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(60)) }
    for x in [TitleBar.controlsX + 16, TitleBar.controlsX + 52] {
        let point = NSPoint(x: x, y: window.frame.height - TitleBar.lineY)
        let hit = window.contentView?.superview?.hitTest(point)
        #expect(hit?.isDescendant(of: host) == true, "клик по x=\(x) ушёл в \(String(describing: hit))")
    }
}
