import SwiftUI

/// Знак Люмена — светящаяся сфера, точно как `.orb` в макете (`ui/src/index.css`).
/// Покой: медленно дышит (5,5 с) и плавает (9 с). Думает: дышит за 1,8 с.
/// Пишет: разгорается. Запомнил: вспышка и кольцо света. Спит: тускнеет.
struct Orb: View {
    enum State { case idle, thinking, writing, remember, sleep }

    var state: State = .idle
    var size: CGFloat = 28
    /// Сферы в старых сообщениях стоят: анимация 30 кадров в секунду на каждую — лишняя работа
    var animated = true

    @Environment(\.palette) private var p
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        // слои Core Animation (Layers.swift): анимацию крутит система, не наш процесс
        OrbLayers(state: state, size: size, moving: animated && !lessMotion, palette: p)
            .frame(width: size, height: size)
            .overlay { Ring(active: state == .remember, size: size).environment(\.palette, p) }
            .accessibilityHidden(true)
    }
}

/// `.orb-ring`: кольцо света «запомнил» — inset −20%, расходится 0.8 → 2.2 за 1,1 с, вместе со вспышкой
private struct Ring: View {
    let active: Bool
    let size: CGFloat

    @Environment(\.palette) private var p
    @State private var go = false

    var body: some View {
        Circle()
            .strokeBorder(p.glow, lineWidth: 1)
            .frame(width: size * 1.4, height: size * 1.4)
            .scaleEffect(go ? 2.2 : 0.8)
            .opacity(go ? 0 : (active ? 0.9 : 0))
            .allowsHitTesting(false)
            .onChange(of: active) { _, on in
                guard on else { return }
                go = false
                withAnimation(.easeOut(duration: 1.1)) { go = true }
            }
    }
}
