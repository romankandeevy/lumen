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
        Rectangle()
            .fill(hover || start != nil ? p.glow.opacity(0.35) : .clear)
            .frame(width: hover || start != nil ? 2 : 1)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    let s = start ?? width
                    start = s
                    let dx = Double(v.translation.width) * (side == .trailing ? 1 : -1)
                    width = Self.clamp(s + dx, min: minWidth, window: Double(windowWidth))
                }
                .onEnded { _ in
                    start = nil
                    save()
                })
            .onTapGesture(count: 2) { } // двойной щелчок не роняет край
            .help("Потяни, чтобы изменить ширину")
            .animation(.easeOut(duration: 0.12), value: hover)
    }

    /// Не уже минимума и не шире половины окна
    static func clamp(_ w: Double, min: Double, window: Double) -> Double {
        Swift.max(min, Swift.min(w, window / 2))
    }
}
