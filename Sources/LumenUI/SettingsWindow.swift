import AppKit
import SwiftUI

/// Настройки — отдельное окно поверх главного (как в Claude), а не страница вместо чата (как в Codex): открылись, поправил, закрыл —
/// чат под ним остаётся на месте. Окно стоит над главным, двигается и тянется, Esc или ⌘W закрывают.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(_ app: AppModel, section: SettingsView.Section? = nil) {
        if let section { app.settingsSection = section }
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: SettingsRoot(app: app) { [weak self] in self?.window?.performClose(nil) })
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.title = "Настройки"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 800, height: 540)
        w.setContentSize(NSSize(width: 1000, height: 720))
        w.delegate = self
        // размер и место прошлого раза — если были; иначе по центру главного окна
        if !w.setFrameUsingName("LumenSettings") {
            if let parent = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                let f = parent.frame, s = w.frame.size
                w.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2))
            } else {
                w.center()
            }
        }
        w.setFrameAutosaveName("LumenSettings")
        // дочернее окно главного: всегда над ним и вместе с ним сворачивается
        if let parent = NSApp.mainWindow ?? NSApp.keyWindow, parent !== w { parent.addChildWindow(w, ordered: .above) }
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let w = window { w.parent?.removeChildWindow(w) }
        window = nil
    }
}

/// Содержимое окна настроек: то же оформление, что у главного окна (тема, шрифты, «меньше движения»)
struct SettingsRoot: View {
    @Bindable var app: AppModel
    let close: () -> Void

    var body: some View {
        let p = app.palette
        SettingsView(app: app)
            .frame(minWidth: 800, minHeight: 540)
            .background(p.background.ignoresSafeArea())
            .environment(\.palette, p)
            .environment(\.chatText, ChatText(font: app.prefs.chatFont, scale: app.prefs.textScale, code: app.prefs.codeFontSize))
            .environment(\.lessMotion, app.lessMotion)
            .preferredColorScheme(p.scheme)
            .tint(p.glow)
            .id(app.prefs.uiFontSize)
            .onExitCommand(perform: close)
    }
}
