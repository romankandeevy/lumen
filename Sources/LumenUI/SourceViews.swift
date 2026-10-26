import LumenCore
import SwiftUI

/// Источники ответа (вариант A «Чипы», Рома 23.10): под ответом — строка «Источники» и чипы: значок сайта, домен, номер.
/// В тексте у ссылок на эти страницы стоят такие же маленькие номера. Нажатие — страница откроется сбоку.
struct SourceStrip: View {
    let sources: [SourceLink]
    let open: (SourceLink) -> Void

    @Environment(\.palette) private var p
    @State private var all = false

    private static let visible = 4

    var body: some View {
        let shown = all ? sources : Array(sources.prefix(Self.visible))
        VStack(alignment: .leading, spacing: 8) {
            Text("Источники").tw(13, .semibold, lh: 16).foregroundStyle(p.mutedFg)
            FlowWrap(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                    SourceChip(source: s, number: i + 1) { open(s) }
                }
                if sources.count > Self.visible {
                    Button { withAnimation(.easeOut(duration: 0.18)) { all.toggle() } } label: {
                        Text(all ? "Свернуть" : "ещё \(sources.count - Self.visible)")
                            .font(.geist(12)).foregroundStyle(p.mutedFg)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(p.borderBase.opacity(0.04), in: Capsule())
                            .overlay(Capsule().strokeBorder(p.line))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct SourceChip: View {
    let source: SourceLink
    let number: Int
    let action: () -> Void

    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            // пилюля хендоффа (1.7.4): h24, 12/17, кружок сайта 16 серым, номер тусклым
            HStack(spacing: 6) {
                SiteTile(host: source.host, size: 16)
                Text(source.host).font(.geist(12)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(hover ? p.foreground : p.textSoft)
                    .frame(maxWidth: 190, alignment: .leading)
                Text("\(number)").font(.geist(11)).foregroundStyle(p.faint).monospacedDigit()
            }
            .padding(.leading, 4).padding(.trailing, 9).frame(height: 24)
            .background(hover ? p.hover : p.borderBase.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(hover ? p.borderBase.opacity(0.14) : p.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help((source.title.map { $0 + "\n" } ?? "") + source.url)
        .accessibilityLabel("Источник \(number): \(source.title ?? source.host)")
    }
}

/// Значок сайта: серый кружок с первой буквой (без запросов в сеть за настоящими значками).
/// Раньше квадрат был цветным по домену — пёстро и дёшево рядом с текстом (1.7.4)
struct SiteTile: View {
    let host: String
    var size: CGFloat = 18

    @Environment(\.palette) private var p

    var body: some View {
        Text(String(host.first.map(String.init)?.uppercased() ?? "·"))
            .font(.system(size: size * 0.56, weight: .bold)).foregroundStyle(p.foreground)
            .frame(width: size, height: size)
            .background(p.foreground.opacity(0.12), in: Circle())
    }
}

// MARK: номера в тексте

private struct SourceNumbersKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

extension EnvironmentValues {
    /// Адрес источника (SourceLinks.key) → его номер: у такой ссылки в тексте ответа стоит маленький номер
    var sourceNumbers: [String: Int] {
        get { self[SourceNumbersKey.self] }
        set { self[SourceNumbersKey.self] = newValue }
    }
}

/// Источники считаются один раз на ответ: перерисовка при наведении мыши не гоняет разбор текста
@MainActor enum SourceCache {
    private static var cache: [String: [SourceLink]] = [:]

    static func sources(for m: ChatMessage) -> [SourceLink] {
        let key = "\(m.id ?? -1)|\(m.text.hashValue)|\(m.steps.count)"
        if let hit = cache[key] { return hit }
        let found = SourceLinks.extract(text: NextStep.split(m.text).text, steps: m.steps)
        if cache.count > 300 { cache.removeAll() }
        cache[key] = found
        return found
    }
}
