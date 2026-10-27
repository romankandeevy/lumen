import AppKit
import SwiftUI

// Общие элементы — как в макете (shadcn `components/ui/*` + `components/page.tsx`).
// Скругления из `--radius: 0.75rem`: sm 7.2, md 9.6, lg 12, xl 16.8, 2xl 21.6, 3xl 26.4.

enum R {
    static let sm: CGFloat = 7.2
    static let md: CGFloat = 9.6
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16.8
    static let xxl: CGFloat = 21.6
    static let xxxl: CGFloat = 26.4
}

/// Подложка строки списка (макет 21.10): выбранная — мягкая заливка без рамки (Рома, 27.10), под курсором — едва заметная.
/// Цветной черты слева нет нигде
struct RowBackground: ViewModifier {
    let active: Bool
    let hover: Bool
    var radius: CGFloat = 11

    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if active {
                shape.fill(p.activeFill)
            } else if hover {
                shape.fill(p.hover)
            }
        }
    }
}

extension View {
    func rowBackground(active: Bool, hover: Bool, radius: CGFloat = 11) -> some View {
        modifier(RowBackground(active: active, hover: hover, radius: radius))
    }
}

/// Кнопка shadcn. Размеры: default h36 px10 text14, sm h32 px12 text14→13, xs h24 px8 text12.
struct LButton: View {
    enum Kind { case glow, primary, secondary, outline, ghost }
    enum Size { case lg, normal, sm, xs }

    let title: String
    var icon: String?
    var kind: Kind = .outline
    var size: Size = .normal
    var busy = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    init(title: String, icon: String? = nil, kind: Kind = .outline, size: Size = .normal, small: Bool = false,
         busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.size = small ? .sm : size
        self.busy = busy
        self.action = action
    }

    /// Шкала кнопок хендоффа (1.7.3): 40 / 32 / 28 / 24, скругление 8 (у большой 10)
    private var height: CGFloat {
        switch size { case .lg: 40; case .normal: 32; case .sm: 28; case .xs: 24 }
    }

    private var font: Font {
        switch size { case .xs: .geist(12, .medium); default: .geist(14, .medium) }
    }

    private var radius: CGFloat { size == .lg ? 10 : (size == .xs ? 6 : 8) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .xs ? 4 : 6) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                } else if let icon {
                    Icon(icon, size == .xs ? 12 : 16)
                }
                Text(title).font(font)
            }
            .foregroundStyle(enabled ? fg : p.mutedFg.opacity(0.7))
            .padding(.horizontal, size == .lg ? 16 : (size == .xs ? 8 : 10))
            .frame(height: height)
            // неактивная — не бледный бежевый, а спокойная серая плашка: видно, что нажать пока нельзя
            .background(enabled ? bg : (kind == .ghost ? .clear : p.foreground.opacity(0.06)), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(kind == .outline || (!enabled && kind != .ghost) ? p.input : .clear))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var fg: Color {
        switch kind {
        // синяя заливка, белый текст; у монохрома — светлая заливка, тёмный текст
        case .glow: p.isMono ? p.onGlow : .white
        case .primary: p.primaryFg
        case .secondary, .outline: p.foreground
        case .ghost: p.foreground
        }
    }

    private var bg: Color {
        switch kind {
        case .glow: (p.isMono ? p.glow : p.accent).opacity(hover ? 0.88 : 1)
        case .primary: hover ? p.primary.opacity(0.8) : p.primary
        case .secondary: hover ? p.secondary.opacity(0.8) : p.secondary
        case .outline: hover ? p.input.opacity(0.5) : p.input.opacity(0.3)
        case .ghost: hover ? p.muted.opacity(0.5) : .clear
        }
    }
}

/// Сегменты-переключатель («ты / вы»): равные части во всю ширину, тот же вид, что у всех сегментов (1.7.3).
struct Segmented<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]

    @Environment(\.palette) private var p
    @Namespace private var pill

    var body: some View {
        // один вид сегментов на всё приложение (хендофф, 1.7.3): обёртка h28 с отступом 1 и r8, сегмент h26 r6
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { id, name in
                let active = id == value
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { value = id }
                } label: {
                    Text(name)
                        .font(.geist(13, .medium))
                        // узко — текст ужимается, но не переносится по слогам
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(active ? p.foreground : p.mutedFg)
                        .frame(maxWidth: .infinity)
                        .segmentPill(active, namespace: pill)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .segmentTrack()
    }
}

/// Обёртка сегментов: h28, отступ 1, r8, тонкая подложка и кольцо
struct SegmentTrack: ViewModifier {
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content.padding(1)
            .background(p.foreground.opacity(p.isLight ? 0.05 : 0.04), in: shape)
            .overlay(shape.strokeBorder(p.foreground.opacity(0.06)))
    }
}

/// Сегмент: h26, по бокам 10, r6; выбранный — светлее, с тонким кольцом и тенью в 1 pt
struct SegmentPill: ViewModifier {
    let on: Bool
    var namespace: Namespace.ID?

    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content.padding(.horizontal, 10).frame(height: 26)
            .background {
                if on {
                    let fill = shape.fill(p.isLight ? Color.white : p.foreground.opacity(0.1))
                        .overlay(shape.strokeBorder(p.foreground.opacity(p.isLight ? 0.06 : 0.08)))
                        .shadow(color: .black.opacity(p.isLight ? 0.08 : 0.3), radius: 1, y: 1)
                    if let namespace { fill.matchedGeometryEffect(id: "pill", in: namespace) } else { fill }
                }
            }
    }
}

extension View {
    func segmentTrack() -> some View { modifier(SegmentTrack()) }
    func segmentPill(_ on: Bool, namespace: Namespace.ID? = nil) -> some View { modifier(SegmentPill(on: on, namespace: namespace)) }
}

/// Карточка выбора (`Option` в знакомстве, «Через что отвечать» в настройках)
struct ChoiceCard: View {
    let title: String
    let note: String
    var icon: String?
    let active: Bool
    /// В настройках карточка чуть светится и без выбора лежит на card/40
    var settingsStyle = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Group {
                if settingsStyle {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title).tw(14, .medium, lh: 20)
                            Spacer()
                            if active { check }
                        }
                        Text(note).tw(12, lh: 19.5).foregroundStyle(p.mutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 12) {
                        if let icon {
                            Icon(icon, 16)
                                .frame(width: 36, height: 36)
                                .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.lg))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).tw(14, .medium, lh: 20)
                            Text(note).tw(12, lh: 16).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if active { check }
                    }
                }
            }
            .foregroundStyle(p.foreground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(background, in: RoundedRectangle(cornerRadius: R.xl))
            .overlay(RoundedRectangle(cornerRadius: R.xl).strokeBorder(active ? p.glow.opacity(0.5) : p.border))
            .shadow(color: active && settingsStyle ? p.glowSoft : .clear, radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: R.xl))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var check: some View {
        Icon("check", 16).foregroundStyle(p.glow)
    }

    private var background: Color {
        if active { return p.glow.opacity(0.06) }
        if settingsStyle { return hover ? p.card : p.card.opacity(0.85) }
        return hover ? p.foreground.opacity(0.05) : .clear
    }
}

/// Карточка настроек с иконкой, заголовком и статусом справа (`Card` в settings-page)
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let status: AnyView
    @ViewBuilder let content: Content

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Icon(icon, 16)
                    .frame(width: 36, height: 36)
                    .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.xl))
                Text(title).tw(14, .medium, lh: 20)
                Spacer()
                status
            }
            content.padding(.top, 20)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(p.card.opacity(0.85), in: RoundedRectangle(cornerRadius: R.xxl))
        .overlay(RoundedRectangle(cornerRadius: R.xxl).strokeBorder(p.border))
    }
}

/// Точка-статус: зелёная светится, серая — нет
struct StatusDot: View {
    let on: Bool
    let text: String
    var bad = false

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(bad ? Palette.destructive : (on ? Palette.ok : p.foreground.opacity(0.25)))
                .frame(width: 6, height: 6)
                .shadow(color: on ? Palette.ok : .clear, radius: 4)
            Text(text).font(.geist(12)).foregroundStyle(on ? p.foreground : p.mutedFg)
        }
    }
}

/// Полоска лимита подписки
struct Meter: View {
    let label: String
    let value: Int
    let note: String

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                Text(note.isEmpty ? "\(value)%" : "\(value)%, \(note)").foregroundStyle(p.mutedFg).monospacedDigit()
            }
            .font(.geist(12))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.muted)
                    Capsule().fill(p.glow)
                        .frame(width: g.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                        .shadow(color: p.glowSoft, radius: 4)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Подпись группы внутри страницы — обычным регистром (`GroupTitle`)
struct GroupTitle: View {
    let text: String
    var aside: String?

    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).tw(14, .medium, lh: 20)
            Spacer()
            if let aside { Text(aside).tw(12, lh: 16).foregroundStyle(p.mutedFg) }
        }
        .padding(.bottom, 10)
    }
}

/// Поле ввода: светится по краю в фокусе (`.glow-field`)
struct GlowField<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    /// Значок слева (поиск, ссылка)
    var icon: String? = nil
    /// Невысокое поле в ряд с кнопками h28 (хендофф, 1.7.3)
    var compact = false
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Icon(icon, 16).foregroundStyle(focused ? p.glow : p.faint) }
            Group {
                // подсказка приглушённая — чтобы не путалась с введённым текстом
                if secure {
                    SecureField(text: $text, prompt: Text(placeholder).foregroundStyle(p.faint)) { EmptyView() }
                } else {
                    TextField(text: $text, prompt: Text(placeholder).foregroundStyle(p.faint)) { EmptyView() }
                }
            }
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12.5, design: .monospaced) : .geist(compact ? 14 : 15))
            .focused($focused)
            .onSubmit(onSubmit)
            trailing
        }
        .padding(.horizontal, compact ? 10 : 14)
        .frame(height: compact ? 28 : (mono ? 38 : 44))
        .fieldGlass(focused: focused)
    }
}

extension GlowField where Trailing == EmptyView {
    init(placeholder: String, text: Binding<String>, secure: Bool = false, mono: Bool = false, icon: String? = nil,
         compact: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, secure: secure, mono: mono, icon: icon, compact: compact, onSubmit: onSubmit) { EmptyView() }
    }
}

/// Стекло поля ввода (как у поля сообщения, только мельче): мягкий градиент, кольцо 1px внутри, светлая кромка сверху;
/// в фокусе кольцо синее и вокруг 3px мягкого синего — без неонового свечения
struct FieldGlass: ViewModifier {
    let focused: Bool
    var radius: CGFloat = 12

    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(p.isLight ? AnyShapeStyle(p.card)
                           : AnyShapeStyle(LinearGradient(colors: [p.borderBase.opacity(0.05), p.borderBase.opacity(0.025)], startPoint: .top, endPoint: .bottom)))
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(focused ? p.glow.opacity(0.42) : p.borderBase.opacity(0.09))
                    shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(p.isLight ? 0 : 0.05), .clear],
                                                                  startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)))
                    if focused {
                        RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                            .strokeBorder(p.accent.opacity(0.10), lineWidth: 3).padding(-3)
                    }
                }
                .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.2), value: focused)
    }
}

extension View {
    func fieldGlass(focused: Bool, radius: CGFloat = 12) -> some View { modifier(FieldGlass(focused: focused, radius: radius)) }
}

struct LSwitch: View {
    @Binding var isOn: Bool

    @Environment(\.palette) private var p

    var body: some View {
        // один тумблер на всё приложение (хендофф, 1.7.3): 36×20, ручка 16 белая, включён — акцентный цвет темы
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Capsule()
                .fill(isOn ? p.accent : p.foreground.opacity(p.isLight ? 0.16 : 0.14))
                .frame(width: 36, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .frame(width: 16, height: 16).padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

/// Пункт меню-поповера (`Option` в pickers.tsx): иконка, название, пояснение, галочка
struct PopoverOption<Leading: View>: View {
    let name: String
    let note: String
    let active: Bool
    @ViewBuilder let icon: Leading
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.geist(14, .medium))
                    Text(note).font(.geist(12.5)).foregroundStyle(p.mutedFg)
                }
                Spacer(minLength: 0)
                if active { Icon("check", 16).foregroundStyle(p.glow) }
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(hover ? p.borderBase.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Список-выбор во всплывающем меню (модель, «сколько думать»): название, пояснение, галочка у выбранного.
/// ↑↓ — подсветка, ↩ — выбрать, Esc и щелчок мимо — закрыть (DismissMonitor у PickerButton)
struct ListboxPanel<ID: Hashable>: View {
    struct Item {
        let id: ID
        let name: String
        let note: String
        /// Разделитель над строкой
        var gap = false
    }

    let items: [Item]
    let selected: ID
    var width: CGFloat = 252
    let pick: (ID) -> Void

    @Environment(\.palette) private var p
    @State private var hi: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                if it.gap { p.line.frame(height: 1).padding(.vertical, 5).padding(.horizontal, 4) }
                Button { pick(it.id) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(it.name).font(.geist(14, .medium)).foregroundStyle(p.foreground)
                            Text(it.note).font(.geist(12.5)).foregroundStyle(p.mutedFg)
                        }
                        Spacer(minLength: 0)
                        if it.id == selected { Icon("check", 16).foregroundStyle(p.glow) }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(hi == i ? p.borderBase.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hi = i } }
                .accessibilityAddTraits(it.id == selected ? [.isSelected] : [])
            }
        }
        .padding(6)
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .background(KeyMonitor { key in
            switch key {
            case 125: hi = ((hi ?? -1) + 1) % items.count; return true // ↓
            case 126: hi = ((hi ?? items.count) - 1 + items.count) % items.count; return true // ↑
            case 36, 76: // ↩
                if let h = hi, items.indices.contains(h) { pick(items[h].id) }
                return true
            default: return false
            }
        })
        .onAppear { hi = items.firstIndex { $0.id == selected } }
    }
}

/// Облик всплывающего меню (макет 21.10): фон popover, скругление 16, кольцо внутри и глубокая тень
struct PopoverChrome: ViewModifier {
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        // всплывашка хендоффа (1.7.3): r14, кольцо 1 pt и две мягкие тени — «0 8 24» и «0 2 6»
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(p.popover)
            .clipShape(shape)
            .overlay(shape.strokeBorder(p.borderBase.opacity(p.isLight ? 0.08 : 0.09)))
            .shadow(color: .black.opacity(p.isLight ? 0.12 : 0.42), radius: 12, y: 8)
            .shadow(color: .black.opacity(p.isLight ? 0.08 : 0.3), radius: 3, y: 2)
    }
}

extension View {
    func popoverChrome() -> some View { modifier(PopoverChrome()) }

    /// Меню не выше места до края окна (Рома, 27.10: «Из GitHub» вылезало за рамку, как у Claude так нельзя): выше — листается внутри.
    /// `anchor` — рамка кнопки в окне; меню растёт от неё вверх или (`down`) вниз
    func fitInWindow(anchor: CGRect, down: Bool = false) -> some View { modifier(FitInWindow(anchor: anchor, down: down)) }
}

struct FitInWindow: ViewModifier {
    let anchor: CGRect
    let down: Bool

    @Environment(\.windowHeight) private var windowHeight
    @State private var natural: CGFloat = 0

    func body(content: Content) -> some View {
        // зазор от кнопки 8 и поле у края окна 12
        let room = max(160, (down ? windowHeight - anchor.maxY : anchor.minY) - 20)
        ScrollView(.vertical, showsIndicators: false) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
        }
        .frame(height: natural > 0 ? min(natural, room) : nil)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Закрыть плавающее меню: щелчок мимо него (по своим границам) или Esc
struct DismissMonitor: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView()
        v.close = close
        return v
    }

    func updateNSView(_ v: MonitorView, context: Context) { v.close = close }

    static func dismantleNSView(_ v: MonitorView, coordinator: ()) { v.stop() }

    final class MonitorView: NSView {
        var close: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                guard let self, let w = self.window else { return e }
                if e.type == .keyDown {
                    guard e.keyCode == 53 else { return e } // Esc
                    self.close()
                    return nil
                }
                guard e.window === w else { return e }
                if !self.bounds.contains(self.convert(e.locationInWindow, from: nil)) {
                    DispatchQueue.main.async { self.close() }
                }
                return e
            }
        }

        func stop() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
    }
}

/// Клавиши для открытого меню, пока фокус в поле ввода: true — клавиша съедена
struct KeyMonitor: NSViewRepresentable {
    let handle: (UInt16) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView()
        v.handle = handle
        return v
    }

    func updateNSView(_ v: MonitorView, context: Context) { v.handle = handle }

    static func dismantleNSView(_ v: MonitorView, coordinator: ()) { v.stop() }

    final class MonitorView: NSView {
        var handle: (UInt16) -> Bool = { _ in false }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.window === self.window else { return e }
                return self.handle(e.keyCode) ? nil : e
            }
        }

        func stop() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
    }
}

/// Поповер в цветах темы (`PopoverContent`): заголовок сверху, отступ 6
struct PopoverPanel<Content: View>: View {
    let title: String
    var width: CGFloat = 288
    @ViewBuilder let content: Content

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title).font(.geist(12.5)).foregroundStyle(p.mutedFg).padding(.horizontal, 11).padding(.top, 4).padding(.bottom, 8)
            }
            content
        }
        .padding(6)
        .frame(width: width)
        .background(p.popover)
        .preferredColorScheme(p.scheme)
    }
}

/// Иконка Lucide и подпись — замена Label(systemImage:)
struct IconLabel: View {
    let text: String
    let icon: String
    var size: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Icon(icon, size).alignmentGuide(.firstTextBaseline) { d in d[.bottom] * 0.8 }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Идёт работа — мигающая точка, как в Claude (вместо крутилки)
struct LiveDot: View {
    var color: Color
    var size: CGFloat = 7

    @State private var on = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 1 : 0.25)
            .shadow(color: color.opacity(on ? 0.8 : 0), radius: on ? 4 : 0)
            .frame(width: 14, height: 14)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true } }
            .accessibilityLabel("Работает")
    }
}

/// Текст «думает» переливается светом, как в Claude: по буквам проходит блик
struct Shimmer: ViewModifier {
    var color: Color
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, color.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(40, g.size.width * 0.45))
                        .offset(x: phase * g.size.width)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.2 } }
    }
}

extension View {
    func shimmer(_ color: Color) -> some View { modifier(Shimmer(color: color)) }

    /// Название разговора, пока идёт ход: текст чуть притушен, а в одном месте он мягко светлеет, и это место плывёт
    /// по строке (вместо точки справа; Рома, 27.10: без тени и свечения вокруг, просто немного светлее в одном месте)
    @ViewBuilder func runningGlow(_ on: Bool, _ color: Color) -> some View {
        if on { modifier(TextGlint(color: color)) } else { self }
    }
}

struct TextGlint: ViewModifier {
    let color: Color
    @State private var start = Date()

    func body(content: Content) -> some View {
        content
            .opacity(0.62)
            .overlay {
                TimelineView(.animation) { ctx in
                    // 2,6 с на проход, из них 1,8 с свет идёт по строке, остальное — пауза
                    let t = ctx.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 2.6) / 1.8
                    GeometryReader { g in
                        let w = max(36, g.size.width * 0.3)
                        let x = -w + (g.size.width + w) * min(1, t)
                        LinearGradient(stops: [.init(color: color.opacity(0), location: 0),
                                               .init(color: color.opacity(0.9), location: 0.5),
                                               .init(color: color.opacity(0), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w)
                            .offset(x: x)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

/// Место, за которое тянут окно: пустая полоса шапки двигает окно, двойной щелчок — по-системному (развернуть или свернуть)
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2, let window else { super.mouseDown(with: event); return }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        }
    }
}

/// Крутящаяся дуга 13 pt — «идёт работа» в таблетке задач
struct PillSpinner: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(color.opacity(0.3), lineWidth: 1.6)
                Circle().trim(from: 0, to: 0.28).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees((t * 360).truncatingRemainder(dividingBy: 360)))
            }
        }
        .frame(width: 13, height: 13)
    }
}
