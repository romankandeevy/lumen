import AppKit
import LumenCore
import SwiftUI

// Питомец (1.5): пиксельный зверёк или капля. Сидит поверх окон, вместо точек «работает» в переписке,
// у ботов вместо значка — их капля. Настройки → Внешний вид → Питомец.

private struct PetMarkKey: EnvironmentKey {
    static let defaultValue: PetPrefs? = nil
}

extension EnvironmentValues {
    /// Питомец вместо точек «работает»: задан, когда он включён и выбрано «вместо точек»
    var petMark: PetPrefs? {
        get { self[PetMarkKey.self] }
        set { self[PetMarkKey.self] = newValue }
    }
}

/// Питомец по настройкам: пиксельный зверёк или капля. У капли можно задать любое из 14 состояний
struct PetView: View {
    let pet: PetPrefs
    var mood: PetMood = .idle
    /// Состояние капли вместо `mood` (превью в настройках)
    var blobAnim: BlobAnim?
    var size: CGFloat = 64
    var animated = true
    var followsCursor = false

    var body: some View {
        if pet.kind.isPixel {
            PixelPetView(kind: pet.kind, mood: mood, size: size, animated: animated)
        } else {
            BlobView(look: pet.blob, anim: blobAnim ?? mood.blob, size: size, animated: animated, followsCursor: followsCursor)
        }
    }
}

/// Знак «работает» в переписке: капля бота, питомец или, если он выключен, четыре точки
struct WorkMark: View {
    var color: Color
    var bot: Bot?
    var mood: PetMood = .thinking

    @Environment(\.petMark) private var pet

    var body: some View {
        if let pet {
            // у капли «думает» — три точки: рисуем крупнее, чтобы они читались рядом с текстом
            if let bot {
                BlobView(look: bot.blobLook, anim: mood.blob, size: 40).padding(-10)
            } else if pet.kind.isPixel {
                PixelPetView(kind: pet.kind, mood: mood, size: 32).padding(-6)
            } else {
                BlobView(look: pet.blob, anim: mood.blob, size: 40).padding(-10)
            }
        } else {
            DotsSpinner(color: color, plain: true)
        }
    }
}

extension AppModel {
    /// Что сейчас делает питомец: как сфера Lumen, а после 10 минут тишины — спит
    var petMood: PetMood {
        let m = PetMood(orb)
        if m == .idle && Date().timeIntervalSince(petBusyAt) > 600 { return .sleep }
        return m
    }
}

// MARK: поверх окон

/// Маленькое окно без рамки поверх всех окон и рабочих столов: в нём питомец. Тянется мышью,
/// щелчок открывает Lumen, правый щелчок — меню. Место запоминается.
@MainActor final class PetPanel {
    static let shared = PetPanel()

    private var panel: NSPanel?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    func sync(_ app: AppModel) {
        let pet = app.prefs.pet
        guard pet.enabled, pet.floating else { panel?.orderOut(nil); return }
        let side = CGFloat(pet.size.points)
        let p = panel ?? make(app, side: side)
        panel = p
        if abs(p.frame.width - side) > 0.5 {
            var f = p.frame
            f.origin.x += (f.width - side) / 2
            f.origin.y += (f.height - side) / 2
            f.size = CGSize(width: side, height: side)
            p.setFrame(f, display: true)
        }
        p.orderFrontRegardless()
    }

    private func make(_ app: AppModel, side: CGFloat) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: FloatingPet(app: app))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        p.contentView = host
        if !p.setFrameUsingName("LumenPet") {
            // впервые — в правом нижнем углу экрана
            let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            p.setFrameOrigin(NSPoint(x: v.maxX - side - 28, y: v.minY + 28))
        }
        p.setFrameAutosaveName("LumenPet")
        return p
    }

    func dragChanged() {
        guard let p = panel else { return }
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (m, p.frame.origin) }
        guard let s = dragStart else { return }
        p.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
    }

    func dragEnded() { dragStart = nil }

    /// Открыть Lumen: главное окно — вперёд
    static func openLumen() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.frameAutosaveName != "LumenPet" && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}

/// Питомец в своём окне: следит за курсором, засыпает в тишине
struct FloatingPet: View {
    let app: AppModel

    var body: some View {
        let pet = app.prefs.pet
        let side = CGFloat(pet.size.points)
        // раз в 15 секунд — проверить, не пора ли спать
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            PetView(pet: pet, mood: app.petMood, size: side, followsCursor: true)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { PetPanel.openLumen() }
        .gesture(DragGesture(minimumDistance: 3).onChanged { _ in PetPanel.shared.dragChanged() }.onEnded { _ in PetPanel.shared.dragEnded() })
        .contextMenu {
            Button("Открыть Lumen") { PetPanel.openLumen() }
            Button("Настройки питомца") {
                app.page = .settings(.pet)
                PetPanel.openLumen()
            }
            Divider()
            Button("Убрать с экрана") { app.update { $0.pet.floating = false } }
        }
        .help("\(pet.kind.name): \(app.petMood.name.lowercased()). Щелчок — открыть Lumen, перетащи — переставить")
        .environment(\.palette, app.palette)
        .environment(\.lessMotion, app.lessMotion)
    }
}

// MARK: настройки

/// Настройки → Внешний вид → Питомец: включить, где показывать, кто, как выглядит сейчас, капля — своя
struct PetSettingsContent: View {
    @Bindable var app: AppModel

    @Environment(\.palette) private var p
    @State private var mood: PetMood = .idle
    @State private var anim: BlobAnim = .idle

    private var pet: PetPrefs { app.prefs.pet }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Питомец") {
                row("Показывать питомца", "Повторяет, что делает Lumen: думает, пишет, запомнил; в тишине засыпает", icon: "paw-print") {
                    LSwitch(isOn: bind(\.enabled))
                }
                row("Поверх всех окон", "Маленькое окно без рамки: тянется мышью, щелчок открывает Lumen", icon: "app-window") {
                    LSwitch(isOn: bind(\.floating)).disabled(!pet.enabled).opacity(pet.enabled ? 1 : 0.4)
                }
                row("Вместо точек «работает»", "В переписке вместо четырёх точек — питомец, у ботов — их капля", icon: "message-circle") {
                    LSwitch(isOn: bind(\.inChat)).disabled(!pet.enabled).opacity(pet.enabled ? 1 : 0.4)
                }
                row("Размер поверх окон", nil, icon: "layers") {
                    PillPicker(value: bind(\.size), options: [(.small, "Маленький"), (.medium, "Средний"), (.large, "Большой")])
                        .disabled(!pet.enabled).opacity(pet.enabled ? 1 : 0.4)
                }
            }

            SettingsGroup(title: "Кто") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(PetKind.allCases, id: \.self) { k in kindTile(k) }
                }
                .padding(.vertical, 14)
            }

            SettingsGroup(title: "Как выглядит", aside: pet.kind.isPixel ? mood.name : anim.name) {
                VStack(spacing: 14) {
                    PetView(pet: pet, mood: mood, blobAnim: pet.kind.isPixel ? nil : anim, size: pet.kind.isPixel ? 160 : 180, followsCursor: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(
                            RadialGradient(colors: [p.glow.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 200),
                            in: RoundedRectangle(cornerRadius: R.xl))
                    if pet.kind.isPixel {
                        chips(PetMood.allCases, selected: mood, name: \.name) { mood = $0 }
                    } else {
                        chips(BlobAnim.allCases, selected: anim, name: \.name) { anim = $0 }
                        Text("В Lumen: \(anim.role).").tw(12, lh: 16).foregroundStyle(p.mutedFg).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 14)
            }

            if pet.kind == .blob {
                SettingsGroup(title: "Капля") {
                    BlobLookEditor(look: Binding(get: { app.prefs.pet.blob }, set: { v in app.update { $0.pet.blob = v } }))
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private func bind<T>(_ key: WritableKeyPath<PetPrefs, T>) -> Binding<T> {
        Binding(get: { app.prefs.pet[keyPath: key] }, set: { v in app.update { $0.pet[keyPath: key] = v } })
    }

    private func kindTile(_ k: PetKind) -> some View {
        let on = pet.kind == k
        return Button { app.update { $0.pet.kind = k } } label: {
            VStack(spacing: 6) {
                PetView(pet: PetPrefs.with(k, blob: pet.blob), mood: .idle, size: 64)
                    .frame(height: 68)
                Text(k.name).tw(13, .medium, lh: 18)
                Text(k.note).tw(11, lh: 14).foregroundStyle(p.mutedFg).multilineTextAlignment(.center).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(on ? p.glow.opacity(0.08) : p.foreground.opacity(0.02), in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(on ? p.glow.opacity(0.7) : p.border))
            .contentShape(RoundedRectangle(cornerRadius: R.xl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chips<T: Hashable>(_ items: [T], selected: T, name: KeyPath<T, String>, pick: @escaping (T) -> Void) -> some View {
        FlowWrap(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button { pick(item) } label: {
                    Text(item[keyPath: name]).tw(12, lh: 16)
                        .foregroundStyle(on ? p.foreground : p.mutedFg)
                        .padding(.horizontal, 11).frame(height: 26)
                        .background(on ? p.glow.opacity(0.14) : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? p.glow.opacity(0.6) : p.border))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row<C: View>(_ title: String, _ note: String?, icon: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Icon(icon, 15).foregroundStyle(p.foreground.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tw(14, lh: 20)
                if let note { Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { p.border.frame(height: 1) }
    }
}

extension PetPrefs {
    /// Те же настройки, но другой питомец (для плиток выбора)
    static func with(_ kind: PetKind, blob: BlobLook) -> PetPrefs {
        var p = PetPrefs()
        p.kind = kind
        p.blob = blob
        return p
    }
}

/// Капля на выбор: форма, лицо, цвет — у питомца и у бота
struct BlobLookEditor: View {
    @Binding var look: BlobLook

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Форма") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(BlobShape.allCases, id: \.self) { s in
                        tile(BlobLook(shape: s, face: look.face, color: look.color), s.name, on: look.shape == s) { look.shape = s }
                    }
                }
            }
            section("Лицо") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(BlobFace.allCases, id: \.self) { f in
                        tile(BlobLook(shape: look.shape, face: f, color: look.color), f.name, on: look.face == f) { look.face = f }
                    }
                }
            }
            section("Цвет") {
                HStack(spacing: 8) {
                    ForEach(BlobLook.palette, id: \.hex) { c in
                        let on = look.color == c.hex
                        Button { look.color = c.hex } label: {
                            Circle()
                                .fill(RadialGradient(gradient: BlobColor.ramp(c.hex), center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: 30))
                                .frame(width: 28, height: 28)
                                .padding(3)
                                .overlay(Circle().strokeBorder(on ? p.foreground : .clear, lineWidth: 2))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(c.name)
                        .accessibilityLabel(c.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).tw(12, .medium, lh: 16).foregroundStyle(p.mutedFg)
            c()
        }
    }

    private func tile(_ l: BlobLook, _ name: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(spacing: 2) {
                BlobView(look: l, size: 50, animated: false)
                Text(name).tw(11, lh: 14).foregroundStyle(on ? p.foreground : p.mutedFg).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(on ? p.glow.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: R.lg))
            .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(on ? p.glow.opacity(0.7) : p.border))
            .contentShape(RoundedRectangle(cornerRadius: R.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
