import Foundation
import Testing
@testable import LumenUI

/// Таблицы в ответах (19.10): длинные ячейки не наезжают на соседние строки — ширина колонок считается по тексту и фиксируется

@MainActor @Test func tableColumnsAreSizedByTextWithinLimits() {
    let rows = [["Сценарий", "Было", "Шаги"],
                ["**1. Новый способ**", "A + B", String(repeating: "Инструкция → пример → вставь → ", count: 6)]]
    let w = MarkdownTable.columnWidths(rows)
    #expect(w.count == 3)
    #expect(w.allSatisfy { $0 >= MarkdownTable.minColumn && $0 <= MarkdownTable.maxColumn })
    // длинная ячейка упирается в потолок (дальше — перенос), короткая «Было» узкая
    #expect(w[2] == MarkdownTable.maxColumn)
    #expect(w[1] < w[2])
}

@MainActor @Test func wideTableShrinksToAvailableWidthBeforeScrolling() {
    let natural: [CGFloat] = [200, 80, 340, 300]
    // места хватает — как есть
    #expect(MarkdownTable.fitted(natural, to: 1000) == natural)
    #expect(MarkdownTable.fitted(natural, to: 0) == natural)
    // тесно — сжимаются самые широкие, узкие остаются
    let tight = MarkdownTable.fitted(natural, to: 700)
    #expect(abs(tight.reduce(0, +) - 700) < 0.5)
    #expect(tight[1] == 80)
    #expect(tight[2] < 340 && tight[3] < 300)
    // совсем тесно — ниже пола не уходят, остаётся прокрутка вбок
    let tiny = MarkdownTable.fitted(natural, to: 100)
    #expect(tiny.min() == 80 && tiny[0] == 130 && tiny[2] == 130 && tiny[3] == 130)
}

/// Время хода: секунды, минуты и — для ночной работы — часы
@MainActor @Test func turnClockFormatsSecondsMinutesAndHours() {
    #expect(LiveStepLine.elapsed(7) == "7 с")
    #expect(LiveStepLine.elapsed(134) == "2 мин 14 с")
    #expect(LiveStepLine.elapsed(2 * 3600 + 14 * 60 + 5) == "2 ч 14 мин")
    #expect(LiveStepLine.elapsed(-3) == "0 с")
}
