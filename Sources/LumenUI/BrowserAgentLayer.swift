import SwiftUI

/// Присутствие агента на странице: плавный курсор едет к тому, что он нажимает, круг при нажатии, рамка с названием
/// вокруг элемента, подсветка при вводе и тонкое свечение по краю, пока агент работает. Слой лежит поверх страницы и
/// не ловит мышь. Координаты — в точках вида страницы (у WKWebView они совпадают с CSS-пикселями при масштабе 100 %).
@MainActor @Observable
final class AgentPresence {
    struct Ripple: Identifiable, Equatable {
        let id = UUID()
        let point: CGPoint
    }

    /// Куда смотрит агент
    var cursor: CGPoint = .zero
    var cursorShown = false
    var highlight: CGRect?
    /// Подпись у курсора и рамки: «designer», «Lumen»
    var label = ""
    /// Подпись у рамки: что за элемент («кнопка «Войти»»)
    var target = ""
    var typing = false
    var key: String?
    var ripples: [Ripple] = []
    /// Свечение по краю страницы
    var glowing = false
    /// Движение выключено в настройках — всё появляется сразу
    var calm = false
    /// Курсор агента включён в настройках
    var enabled = true

    @ObservationIgnored private var clearTask: Task<Void, Never>?

    func move(to p: CGPoint, rect: CGRect?, who: String, target: String) {
        label = who
        self.target = target
        glowing = true
        if !cursorShown || calm {
            cursor = p
            cursorShown = true
        } else {
            withAnimation(Motion.cursor) { cursor = p }
        }
        withAnimation(calm ? nil : Motion.highlight) { highlight = rect }
        scheduleClear()
    }

    func click(at p: CGPoint) {
        guard !calm else { return }
        let r = Ripple(point: p)
        ripples.append(r)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.ripples.removeAll { $0 == r }
        }
    }

    func type() {
        typing = true
        scheduleClear()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            self?.typing = false
        }
    }

    func press(_ k: String) {
        key = k
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            if self?.key == k { self?.key = nil }
        }
    }

    /// Агент занят: свечение горит, курсор остаётся там, где был
    func engage() {
        glowing = true
        scheduleClear()
    }

    /// Агент закончил: рамка, курсор и свечение плавно гаснут
    func rest() {
        clearTask?.cancel()
        withAnimation(calm ? nil : Motion.page) {
            glowing = false
            highlight = nil
            cursorShown = false
            typing = false
        }
    }

    /// Пока агент что-то делает, всё держится; через несколько секунд тишины — гаснет
    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.rest() }
        }
    }
}

struct AgentLayer: View {
    var presence: AgentPresence
    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .topLeading) {
            // свечение по краю страницы
            RoundedRectangle(cornerRadius: R.xl - 2)
                .strokeBorder(p.glow.opacity(0.55), lineWidth: 2)
                .blur(radius: 5)
                .opacity(presence.glowing ? 1 : 0)
                .animation(presence.calm ? nil : Motion.page, value: presence.glowing)
            if let r = presence.highlight {
                HighlightBox(rect: r, typing: presence.typing, label: presence.target)
                    .transition(.opacity)
            }
            ForEach(presence.ripples) { r in
                RippleView().position(r.point)
            }
            if presence.cursorShown {
                CursorView(who: presence.label, key: presence.key)
                    .position(presence.cursor)
                    .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(presence.calm ? nil : Motion.page, value: presence.cursorShown)
    }
}

/// Рамка вокруг элемента: мягкая заливка, кольцо и подпись; при вводе пульсирует
private struct HighlightBox: View {
    let rect: CGRect
    let typing: Bool
    let label: String
    @Environment(\.palette) private var p

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(p.glow.opacity(typing ? 0.16 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.glow.opacity(typing ? 0.95 : 0.6), lineWidth: typing ? 2 : 1.5))
            .shadow(color: p.glow.opacity(typing ? 0.5 : 0.25), radius: typing ? 8 : 5)
            .frame(width: max(8, rect.width + 6), height: max(8, rect.height + 6))
            .offset(x: rect.minX - 3, y: rect.minY - 3)
            .animation(.easeOut(duration: 0.18), value: typing)
            .overlay(alignment: .topLeading) {
                if !label.isEmpty {
                    Text(label).font(.geist(11, .medium)).lineLimit(1)
                        .foregroundStyle(p.onGlow)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(p.glow, in: RoundedRectangle(cornerRadius: 5))
                        .offset(x: rect.minX - 3, y: max(0, rect.minY - 3 - 21))
                        .fixedSize()
                }
            }
    }
}

private struct RippleView: View {
    @Environment(\.palette) private var p
    @State private var go = false

    var body: some View {
        Circle().strokeBorder(p.glow, lineWidth: 2)
            .background(Circle().fill(p.glow.opacity(0.25)))
            .frame(width: 44, height: 44)
            .scaleEffect(go ? 1 : 0.2)
            .opacity(go ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 0.6)) { go = true } }
    }
}

/// Курсор агента: стрелка цвета света и подпись «кто»
private struct CursorView: View {
    let who: String
    let key: String?
    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .topLeading) {
            CursorArrow()
                .fill(p.glow)
                .overlay(CursorArrow().stroke(.white.opacity(0.95), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .frame(width: 15, height: 21)
            HStack(spacing: 5) {
                Text(who).font(.geist(11, .medium)).lineLimit(1)
                if let key {
                    Text(key).font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4).frame(height: 14)
                        .background(p.onGlow.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(p.onGlow)
            .padding(.horizontal, 7).frame(height: 18)
            .background(p.glow, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .offset(x: 12, y: 17)
            .fixedSize()
            .animation(.easeOut(duration: 0.15), value: key)
        }
        // острие стрелки — ровно в точке
        .offset(x: -1, y: -1)
    }
}

private struct CursorArrow: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let w = r.width, h = r.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h * 0.86))
        path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.47, y: h))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.59))
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.58))
        path.closeSubpath()
        return path
    }
}
