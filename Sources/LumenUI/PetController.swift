import AppKit
import LumenCore
import QuartzCore

/// Питомец в окне поверх всех: над обычными окнами, полноэкранными приложениями и на всех рабочих столах.
/// Окно не активируется, так что печать в другом приложении не сбивается. Помнит место, бродит, спит,
/// радуется концу задачи. Раз в 5 с проверяет только время — кадры не перерисовывает.
@MainActor
final class PetController {
    static let side: CGFloat = 96

    private let panel: NSPanel
    private let view = PetView()
    private weak var app: AppModel?
    private var mood: PetMood = .idle
    private var lastOrb: Orb.State = .idle
    private var lastTouch = Date()
    private var nextWander = Date().addingTimeInterval(15)
    private var celebration: Task<Void, Never>?
    private var loop: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view

        view.spec = app.petSpec
        view.moving = !app.lessMotion
        view.onPoke = { [weak self] in self?.poke() }
        view.onDragEnd = { [weak self] in self?.savePlace() }

        let saved = app.prefs.petX.flatMap { x in app.prefs.petY.map { NSPoint(x: x, y: $0) } }
        panel.setFrameOrigin(Self.onScreen(saved) ?? Self.corner())
        panel.orderFrontRegardless()

        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.tick()
            }
        }
    }

    /// Открыть заново: питомец мог поменяться в настройках
    func refresh() {
        guard let app else { return }
        view.spec = app.petSpec
        view.moving = !app.lessMotion
    }

    func close() {
        loop?.cancel()
        celebration?.cancel()
        panel.orderOut(nil)
    }

    /// В правый нижний угол основного экрана — если сохранённое место пропало (экран отключили)
    func moveToCorner() {
        panel.setFrameOrigin(Self.corner())
        savePlace()
    }

    // MARK: настроение

    /// Состояние агента из сферы: думает и пишет — питомец тоже; закончил — радуется
    func orbChanged(_ orb: Orb.State) {
        let was = lastOrb
        lastOrb = orb
        touch()
        switch orb {
        case .thinking: set(.thinking)
        case .writing: set(.writing)
        case .remember: celebrate()
        case .idle, .sleep:
            if was == .thinking || was == .writing { celebrate() } else if mood != .happy { set(.idle) }
        }
    }

    private func poke() {
        touch()
        celebrate()
    }

    private func celebrate() {
        set(.happy)
        celebration?.cancel()
        celebration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.set(.idle)
        }
    }

    private func set(_ new: PetMood) {
        if new != .happy {
            celebration?.cancel()
            celebration = nil
        }
        guard new != mood else { return }
        mood = new
        view.mood = new
    }

    /// Любое дело будит: сон — только когда тихо
    private func touch() {
        lastTouch = Date()
        if mood == .sleep { set(.idle) }
    }

    // MARK: раз в 5 секунд

    private func tick() {
        guard let app else { return }
        view.moving = !app.lessMotion
        let now = Date()
        // четыре минуты без дела — спит
        if mood == .idle, now.timeIntervalSince(lastTouch) > 240 { set(.sleep) }
        // бродит короткими прогулками, не чаще раза в 15–30 с
        if mood == .idle, view.moving, now >= nextWander {
            wander()
            nextWander = now.addingTimeInterval(.random(in: 15...30))
        }
    }

    /// Шаг в сторону на несколько десятков точек, плавно и не выходя за экран
    private func wander() {
        let frame = panel.frame
        guard let area = Self.screen(for: frame)?.visibleFrame else { return }
        var target = NSPoint(x: frame.minX + CGFloat.random(in: -70...70), y: frame.minY + CGFloat.random(in: -40...40))
        target.x = min(max(target.x, area.minX), area.maxX - Self.side)
        target.y = min(max(target.y, area.minY), area.maxY - Self.side)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 2.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(target)
        }
    }

    private func savePlace() {
        app?.savePetPlace(panel.frame.origin)
    }

    // MARK: место

    /// Сохранённое место, если оно ещё на каком-то экране
    private static func onScreen(_ p: NSPoint?) -> NSPoint? {
        guard let p else { return nil }
        let frame = NSRect(origin: p, size: NSSize(width: side, height: side))
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? p : nil
    }

    private static func corner() -> NSPoint {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSPoint(x: area.maxX - side - 24, y: area.minY + 24)
    }

    private static func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
    }
}
