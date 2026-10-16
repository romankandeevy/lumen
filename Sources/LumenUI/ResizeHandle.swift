import AppKit
import SwiftUI

/// Ширина окна — чтобы панели не становились шире половины
private struct WindowWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1180 }

extension EnvironmentValues {
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }
}

/// Край панели, за который её тянут. Пока тянут — ширина меняется в памяти, отпустили — сохраняется.
struct ResizeHandle: View {
    enum Side { case trailing, leading }
    /// trailing — край справа (левая панель), leading — край слева (правая панель)
    let side: Side
    @Binding var width: Double
    let minWidth: Double
    let save: () -> Void

    @Environment(\.windowWidth) private var windowWidth
    @Environment(\.palette) private var p
    @State private var start: Double?
    @State private var hover = false

    var body: some View {
        // широкая невидимая зона за краем; при наведении — тонкая линия, без свечения
        Color.clear
            .frame(width: 10)
            .overlay { Rectangle().fill(p.foreground.opacity(hover || start != nil ? 0.25 : 0)).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else if start == nil { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    let s = start ?? width
                    if start == nil { start = s }
                    let dx = Double(v.translation.width) * (side == .trailing ? 1 : -1)
                    // без анимации: панель идёт ровно за мышью
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { width = Self.clamp((s + dx).rounded(), min: minWidth, window: Double(windowWidth)) }
                }
                .onEnded { _ in
                    start = nil
                    if !hover { NSCursor.pop() }
                    save()
                })
            .help("Потяни, чтобы изменить ширину")
    }

    /// Не уже минимума и не шире половины окна
    static func clamp(_ w: Double, min: Double, window: Double) -> Double {
        Swift.max(min, Swift.min(w, window / 2))
    }
}
