import SwiftUI

/// Знак Люмена — светящаяся сфера (`components/lumen-orb.tsx`).
/// Покой: медленно дышит. Думает: дышит чаще. Запомнил: вспышка и кольцо света.
struct Orb: View {
    enum State { case idle, thinking, remember }

    var state: State = .idle
    var size: CGFloat = 28

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion
    @SwiftUI.State private var breathe = false
    @SwiftUI.State private var ring = false

    private var period: Double { state == .thinking ? 1.8 : 5.5 }

    var body: some View {
        ZStack {
            // ореол
            Circle()
                .fill(RadialGradient(colors: [p.glowSoft, .clear], center: .center, startRadius: 0, endRadius: size * 1.05))
                .frame(width: size * 2.2, height: size * 2.2)
                .scaleEffect(lessMotion ? 1 : (breathe ? 1.08 : 0.85))
                .opacity(lessMotion ? 0.8 : (breathe ? 1 : 0.55))
            // тело: блик сверху слева и свечение
            Circle()
                .fill(RadialGradient(colors: [p.glow, p.glow.opacity(0.4), .clear], center: .init(x: 0.5, y: 0.55),
                                     startRadius: 0, endRadius: size * 0.72))
                .overlay(Circle().fill(RadialGradient(colors: [p.glowCore, .clear], center: .init(x: 0.35, y: 0.3),
                                                      startRadius: 0, endRadius: size * 0.45)))
                .shadow(color: p.glowSoft, radius: size * 0.25)
                .frame(width: size, height: size)
                .scaleEffect(state == .thinking && !lessMotion ? (breathe ? 1.04 : 0.9) : 1)
                .brightness(state == .remember && ring ? 0.25 : 0)
            // кольцо «запомнил»
            Circle()
                .stroke(p.glow, lineWidth: 1)
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(ring ? 1.6 : 0.6)
                .opacity(ring ? 0 : (state == .remember ? 0.9 : 0))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear(perform: animate)
        .onChange(of: state) { animate() }
        .onChange(of: lessMotion) { animate() }
    }

    private func animate() {
        breathe = false
        guard !lessMotion else { return }
        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) { breathe = true }
        if state == .remember {
            ring = false
            withAnimation(.easeOut(duration: 1.1)) { ring = true }
        }
    }
}
