import AppKit
import SwiftUI

/// Ширина окна — чтобы панели не становились шире половины
private struct WindowWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1180 }

private struct WindowHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 760 }

extension EnvironmentValues {
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }

    /// Высота окна — чтобы всплывающие меню не вылезали за его рамку
    var windowHeight: CGFloat {
        get { self[WindowHeightKey.self] }
        set { self[WindowHeightKey.self] = newValue }
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
        // широкая невидимая зона за краем; при наведении — тонкая линия, ручка посередине и подсказка
        Color.clear
            .frame(width: 10)
            .overlay { Rectangle().fill(p.foreground.opacity(hover || start != nil ? 0.25 : 0)).frame(width: 1) }
            .overlay {
                Capsule()
                    .fill(p.mutedFg.opacity(0.9))
                    .frame(width: 4, height: 44)
                    .overlay(alignment: .leading) {
                        Text("Изменить размер")
                            .font(.geist(13)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: R.md))
                            .fixedSize()
                            .offset(x: 14)
                    }
                    .opacity(hover || start != nil ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .zIndex(1)
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
    }

    /// Не уже минимума и не шире половины окна
    static func clamp(_ w: Double, min: Double, window: Double) -> Double {
        Swift.max(min, Swift.min(w, window / 2))
    }
}
