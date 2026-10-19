import Foundation
import LumenCore

/// Автовыбор модели (Рома, 19.10: «иногда может кончиться лимит, и это неприятно»).
/// Перегрузка и недоступность — запасные модели прямо в claude (`--fallback-model`); лимит подписки на модель
/// за неделю — Lumen видит его в `/usage` и берёт следующую по силе модель, у которой лимит ещё есть.
public enum ModelChoice {
    /// Запасные по силе: сначала ближайшая
    public static func chain(after m: ChatModel) -> [ChatModel] {
        let order: [ChatModel] = [.fable, .opus, .sonnet, .haiku]
        guard let i = order.firstIndex(of: m) else { return [] }
        return Array(order[(i + 1)...])
    }

    /// Окно лимита именно этой модели («Current week (Opus)»)
    static func window(for m: ChatModel, in usage: [UsageWindow]) -> UsageWindow? {
        let family = m.name.split(separator: " ").first.map { $0.lowercased() } ?? ""
        return usage.first { if case .weekModel(let n) = $0.kind { return n.lowercased().contains(family) } else { return false } }
    }

    /// Модель на этот ход и почему не та, что выбрана (nil — та же). Общий лимит (5 часов, неделя на все модели)
    /// другая модель не обойдёт — тогда остаётся выбранная, а ночью Lumen дождётся сброса.
    public static func pick(_ wanted: ChatModel, usage: [UsageWindow], threshold: Int = 98) -> (model: ChatModel, why: String?) {
        guard !wanted.isGPT else { return (wanted, nil) }
        let shared = usage.filter { $0.kind == .session || $0.kind == .week }
        if shared.contains(where: { $0.percent >= 100 }) { return (wanted, nil) }
        guard let w = window(for: wanted, in: usage), w.percent >= threshold else { return (wanted, nil) }
        for alt in chain(after: wanted) where (window(for: alt, in: usage)?.percent ?? 0) < threshold {
            return (alt, "Лимит \(wanted.name) на неделю исчерпан — отвечает \(alt.name)")
        }
        return (wanted, nil)
    }
}
