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

    private var height: CGFloat {
        switch size { case .lg: 40; case .normal: 36; case .sm: 32; case .xs: 24 }
    }

    private var font: Font {
        switch size { case .xs: .geist(12, .medium); case .sm: .geist(13, .medium); default: .geist(14, .medium) }
    }

    private var radius: CGFloat { size == .xs ? R.md : R.lg }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .xs ? 4 : 6) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: size == .xs ? 11 : 13, weight: .medium))
                }
                Text(title).font(font)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, size == .lg ? 16 : (size == .xs ? 8 : (size == .sm ? 12 : 10)))
            .frame(height: height)
            .background(bg, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(kind == .outline ? p.input : .clear))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var fg: Color {
        switch kind {
        case .glow: .black
        case .primary: p.primaryFg
        case .secondary, .outline: p.foreground
        case .ghost: p.foreground
        }
    }

    private var bg: Color {
        switch kind {
        case .glow: hover ? p.glow.opacity(0.85) : p.glow
        case .primary: hover ? p.primary.opacity(0.8) : p.primary
        case .secondary: hover ? p.secondary.opacity(0.8) : p.secondary
        case .outline: hover ? p.input.opacity(0.5) : p.input.opacity(0.3)
        case .ghost: hover ? p.muted.opacity(0.5) : .clear
        }
    }
}

/// Сегменты-переключатель («ты / вы»): равные половины, выбранная светится как карточки выбора.
/// Здесь сознательно не как в макете: Рома попросил сделать этот выбор красивее (16.10).
struct Segmented<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]

    @Environment(\.palette) private var p
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { id, name in
                let active = id == value
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { value = id }
                } label: {
                    Text(name)
                        .font(.geist(14, active ? .medium : .regular))
                        .foregroundStyle(active ? p.foreground : p.mutedFg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: R.md)
                                    .fill(p.glow.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: R.md).strokeBorder(p.glow.opacity(0.4)))
                                    .shadow(color: p.glowSoft, radius: 10)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg).strokeBorder(p.border))
    }
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
                            Text(title).font(.geist(14, .medium))
                            Spacer()
                            if active { check }
                        }
                        Text(note).font(.geist(12)).lineSpacing(3.5).foregroundStyle(p.mutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 12) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 36, height: 36)
                                .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.lg))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.geist(14, .medium))
                            Text(note).font(.geist(12)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
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
        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.glow)
    }

    private var background: Color {
        if active { return p.glow.opacity(0.06) }
        if settingsStyle { return hover ? p.card : p.card.opacity(0.4) }
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
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 36, height: 36)
                    .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: R.xl))
                Text(title).font(.geist(14, .medium))
                Spacer()
                status
            }
            content.padding(.top, 20)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: R.xxl))
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
            Text(text).font(.geist(14, .medium))
            Spacer()
            if let aside { Text(aside).font(.geist(12)).foregroundStyle(p.mutedFg) }
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
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12, design: .monospaced) : .geist(16))
            .focused($focused)
            .onSubmit(onSubmit)
            trailing
        }
        .padding(.horizontal, mono ? 12 : 16)
        .frame(height: mono ? 36 : 44)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: R.lg))
        .overlay(RoundedRectangle(cornerRadius: R.lg)
            .strokeBorder(focused ? p.glow.opacity(mono ? 0.35 : 0.5) : p.border))
        .shadow(color: focused && mono ? p.glowSoft : .clear, radius: 16)
        .animation(.easeOut(duration: 0.4), value: focused)
    }
}

extension GlowField where Trailing == EmptyView {
    init(placeholder: String, text: Binding<String>, secure: Bool = false, mono: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, secure: secure, mono: mono, onSubmit: onSubmit) { EmptyView() }
    }
}

/// Переключатель shadcn: 32×18, светится, когда включён
struct LSwitch: View {
    @Binding var isOn: Bool

    @Environment(\.palette) private var p

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Capsule()
                .fill(isOn ? p.primary : p.input.opacity(0.8))
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? p.primaryFg : p.foreground).frame(width: 14, height: 14).padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

/// Пункт меню-поповера (`Option` в pickers.tsx): иконка, название, пояснение, галочка
struct PopoverOption<Icon: View>: View {
    let name: String
    let note: String
    let active: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.geist(14, .medium))
                    Text(note).font(.geist(12)).foregroundStyle(p.mutedFg)
                }
                Spacer(minLength: 0)
                if active { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.glow) }
            }
            .foregroundStyle(p.foreground)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(active ? p.muted : (hover ? p.muted.opacity(0.6) : .clear), in: RoundedRectangle(cornerRadius: R.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
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
            Text(title).font(.geist(12)).foregroundStyle(p.mutedFg).padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
            content
        }
        .padding(6)
        .frame(width: width)
        .background(p.popover)
        .preferredColorScheme(.dark)
    }
}
