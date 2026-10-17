import Foundation

/// Встроенный браузер Lumen — панель сбоку окна (Рома, 17.10). В нём работают Lumen, агент и все боты:
/// инструменты как у браузера Claude (прочитать страницу с метками, нажать, ввести, клавиша, прокрутка, снимок),
/// плюс «показать» — открыть человеку макет, картинку, рендер или локальный сайт. Входы в аккаунты — общие:
/// человек входит в панели сам, агенты действуют от его имени.
///
/// Связь: lumen-mcp (процесс у claude) → сокет `run/browser.sock` → Lumen → WKWebView. Одна строка JSON туда и обратно.
public enum BrowserTools {
    public static let names: [String] = definitions.map(\.name)

    /// Инструменты для claude (имена — как в lumen-mcp, у claude они станут `mcp__lumen__browser_…`)
    nonisolated(unsafe) public static let definitions: [(name: String, description: String, schema: [String: Any])] = [
        ("browser_navigate", "Открыть адрес во встроенном браузере Lumen (панель сбоку, человек видит). url может быть back, forward или reload. Возвращает снимок страницы.",
         obj(["url": str("Адрес; без схемы — https://")], required: ["url"])),
        ("browser_show", "Показать человеку файл или локальный сайт в браузере сбоку: макет HTML, картинку, рендер (Blender и т. п.), PDF, SVG, видео или адрес localhost.",
         obj(["path": str("Путь к файлу на этом Маке или адрес http://localhost:…")], required: ["path"])),
        ("browser_read_page", "Прочитать страницу: элементы с метками eN (ссылки, кнопки, поля, заголовки, текст). Метки нужны для click, type, select.",
         obj(["filter": ["type": "string", "enum": ["interactive", "all"], "description": "interactive — только то, на что можно нажать и что заполнить"]])),
        ("browser_find", "Найти на странице элементы по словам (текст, подпись, placeholder). Возвращает метки eN.",
         obj(["query": str("Что искать")], required: ["query"])),
        ("browser_click", "Нажать на элемент по метке eN (или по точке x, y из снимка экрана). Возвращает снимок страницы после нажатия.",
         obj(["ref": str("Метка eN"), "x": ["type": "number"], "y": ["type": "number"]])),
        ("browser_type", "Ввести текст в поле по метке eN (без метки — в поле с фокусом). Старый текст заменяется. submit: true — потом Enter.",
         obj(["ref": str("Метка eN"), "text": str("Текст"), "submit": ["type": "boolean"]], required: ["text"])),
        ("browser_select", "Выбрать вариант в списке (select) или поставить/снять галочку по метке eN.",
         obj(["ref": str("Метка eN"), "value": str("Текст или значение варианта; для галочки true/false")], required: ["ref", "value"])),
        ("browser_key", "Нажать клавишу в поле с фокусом: Enter, Escape, Tab, Backspace, ArrowDown, ArrowUp, PageDown, PageUp.",
         obj(["key": str("Клавиша")], required: ["key"])),
        ("browser_scroll", "Прокрутить страницу (down/up, amount — сколько экранов) или до элемента по метке.",
         obj(["direction": ["type": "string", "enum": ["down", "up"]], "amount": ["type": "number"], "ref": str("Метка eN")])),
        ("browser_screenshot", "Снимок видимой части страницы — чтобы посмотреть на вид, вёрстку, макет.", obj([:])),
        ("browser_text", "Весь текст страницы — чтобы прочитать статью, письмо, документ.", obj([:])),
        ("browser_js", "Выполнить JavaScript на странице и вернуть результат (выражение или тело функции с return).",
         obj(["code": str("Код")], required: ["code"])),
        ("browser_wait", "Подождать: пока на странице появится текст или несколько секунд (до 20).",
         obj(["text": str("Какой текст ждать"), "seconds": ["type": "number"]])),
    ]

    /// Строчка в правила модели: что есть и как этим пользоваться
    public static let rules = """
        Встроенный браузер Lumen — панель сбоку окна, человек видит всё, что ты там делаешь (инструменты browser_*). \
        В нём его входы в аккаунты: действуй от его имени аккуратно — ничего не покупай, не отправляй, не публикуй и не удаляй \
        без его явного OK в разговоре; пароли не вводи — войти человек может сам в этой панели. Порядок: browser_navigate → \
        browser_read_page (метки eN) → browser_click / browser_type по меткам; после действий снимок страницы приходит сам. \
        Показать человеку макет, картинку, рендер Blender, PDF, вёрстку или локальный сайт — browser_show с путём к файлу или адресом localhost \
        (в своих HTML ставь <meta charset="utf-8">, иначе русский текст сломается).
        """

    static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }

    static func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var o: [String: Any] = ["type": "object", "additionalProperties": false, "properties": props]
        if !required.isEmpty { o["required"] = required }
        return o
    }

    /// Запрос и ответ по сокету
    public struct Reply: Sendable {
        public var text: String
        /// PNG снимка экрана
        public var image: Data?
        public var error: Bool

        public init(text: String, image: Data? = nil, error: Bool = false) {
            self.text = text
            self.image = image
            self.error = error
        }

        public var json: Data {
            var o: [String: Any] = ["text": text, "error": error]
            if let image { o["image"] = image.base64EncodedString() }
            var d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
            d.append(0x0A)
            return d
        }

        public init?(json: Data) {
            guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
            text = o["text"] as? String ?? ""
            error = o["error"] as? Bool ?? false
            image = (o["image"] as? String).flatMap { Data(base64Encoded: $0) }
        }
    }

    public static func request(tool: String, args: [String: Any], who: String) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: ["tool": tool, "args": args, "who": who])) ?? Data()
        d.append(0x0A)
        return d
    }
}
