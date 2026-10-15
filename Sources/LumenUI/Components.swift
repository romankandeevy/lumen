import SwiftUI

// Общие элементы из макета (`components/page.tsx`, `components/ui/button`, карточки настроек)

/// Кнопка в стиле shadcn: основная светится, обводка, без фона
struct LButton: View {
    enum Kind { case glow, primary, outline, ghost }

    let title: String
    var icon: String?
    var kind: Kind = .outline
    var small = false
    var busy = false
    let action: () -> Void

    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(fg)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: small ? 11 : 12, weight: .medium))
                }
                Text(title).font(.geist(small ? 12.5 : 13.5, .medium))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 30 : 36)
            .background(bg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(kind == .outline ? p.input : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var fg: Color {
        switch kind {
        case .glow: .black
        case .primary: p.background
        case .outline: p.foreground
        case .ghost: hover ? p.foreground : p.mutedFg
        }
    }

    private var bg: Color {
        switch kind {
        case .glow: hover ? p.glow.opacity(0.85) : p.glow
        case .primary: hover ? p.foreground.opacity(0.9) : p.foreground
        case .outline: hover ? p.foreground.opacity(0.06) : p.input.opacity(0.3)
        case .ghost: hover ? p.foreground.opacity(0.05) : .clear
        }
    }
}

/// Сегменты-переключатель («ты / вы» и т. п.)
struct Segmented<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]

    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { id, name in
                Button { value = id } label: {
                    Text(name)
                        .font(.geist(12))
                        .foregroundStyle(id == value ? p.foreground : p.mutedFg)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(id == value ? p.background : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(id == value ? p.border : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(p.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Карточка выбора: иконка, заголовок, пояснение, галочка; выбранная светится
struct ChoiceCard: View {
    let title: String
    let note: String
    var icon: String?
    let active: Bool
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 36, height: 36)
                        .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(13.5, .medium))
                    Text(note).font(.geist(12)).foregroundStyle(p.mutedFg).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if active { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.glow) }
            }
            .foregroundStyle(p.foreground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? p.glow.opacity(0.06) : (hover ? p.foreground.opacity(0.05) : p.card.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? p.glow.opacity(0.5) : p.border))
            .shadow(color: active ? p.glowSoft : .clear, radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Карточка настроек с иконкой, заголовком и статусом справа
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
                    .font(.system(size: 13))
                    .frame(width: 36, height: 36)
                    .background(p.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.geist(13.5, .medium))
                Spacer()
                status
            }
            content.padding(.top, 18)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(p.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.border))
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                Text("\(value) %, \(note)").foregroundStyle(p.mutedFg).monospacedDigit()
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

/// Подпись группы внутри раздела — обычным регистром
struct GroupTitle: View {
    let text: String
    var aside: String?

    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.geist(13.5, .medium))
            Spacer()
            if let aside { Text(aside).font(.geist(12)).foregroundStyle(p.mutedFg) }
        }
        .padding(.bottom, 10)
    }
}

/// Поле ввода в стиле макета: светится по краю в фокусе
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
            .font(mono ? .system(size: 12, design: .monospaced) : .geist(15))
            .focused($focused)
            .onSubmit(onSubmit)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: mono ? 36 : 44)
        .background(p.input.opacity(0.3), in: RoundedRectangle(cornerRadius: mono ? 9 : 12))
        .overlay(RoundedRectangle(cornerRadius: mono ? 9 : 12)
            .strokeBorder(focused ? p.glow.opacity(0.35) : p.border))
        .shadow(color: focused ? p.glowSoft : .clear, radius: 14)
        .animation(.easeOut(duration: 0.3), value: focused)
    }
}

extension GlowField where Trailing == EmptyView {
    init(placeholder: String, text: Binding<String>, secure: Bool = false, mono: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, secure: secure, mono: mono, onSubmit: onSubmit) { EmptyView() }
    }
}
