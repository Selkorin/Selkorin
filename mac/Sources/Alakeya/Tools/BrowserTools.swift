import Foundation

struct BrowserTools: ToolHandler {
    var toolNames: [String] {
        [
            "browser_open",
            "browser_read_page",
            "browser_click",
            "browser_type",
            "browser_back",
            "browser_reload",
            "browser_scroll",
            "browser_select",
            "browser_submit",
            "browser_wait",
            "browser_screenshot",
            "browser_hard_reload",
            "browser_zoom",
            "browser_clear_cookies",
            "browser_clear_cache",
            "browser_highlight_element",
            "browser_extract_data",
            "browser_seo_audit",
        ]
    }

    var toolSchemas: [[String: Any]] { Self.schemas }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        switch toolName {
        case "browser_open":
            let value = args["url"] ?? args["query"] ?? "https://www.google.com"
            return Action(
                type: .browserOpen,
                title: "Открыть браузер",
                description: "Открыть во встроенном браузере: \(value)",
                target: value, scope: "Браузер Алакеи", args: args
            )
        case "browser_read_page":
            return Action(
                type: .browserReadPage,
                title: "Прочитать страницу",
                description: "Получить видимый текст и элементы текущей страницы.",
                target: "Текущая страница", scope: "Только чтение", args: args
            )
        case "browser_click":
            let text = args["text"] ?? ""
            let elementID = args["element_id"] ?? ""
            return Action(
                type: .browserClick,
                title: "Нажать на сайте",
                description: "Нажать элемент \(elementID.isEmpty ? "«\(text)»" : elementID) во встроенном браузере.",
                target: elementID.isEmpty ? text : elementID,
                scope: "Браузер Алакеи", args: args
            )
        case "browser_type":
            let field = args["field"] ?? ""
            return Action(
                type: .browserType,
                title: "Ввести текст на сайте",
                description: "Ввести текст в поле «\(field)».",
                target: field, scope: "Браузер Алакеи", args: args
            )
        case "browser_back":
            return Action(
                type: .browserBack,
                title: "Вернуться назад",
                description: "Открыть предыдущую страницу.",
                target: "История", scope: "Браузер Алакеи", args: args
            )
        case "browser_reload":
            return Action(
                type: .browserReload,
                title: "Обновить страницу",
                description: "Перезагрузить текущую страницу.",
                target: "Текущая страница", scope: "Браузер Алакеи", args: args
            )
        case "browser_scroll":
            return Action(
                type: .browserScroll,
                title: "Прокрутить страницу",
                description: "Прокрутить страницу \(args["direction"] ?? "вниз").",
                target: args["direction"] ?? "down",
                scope: "Браузер Алакеи", args: args
            )
        case "browser_select":
            return Action(
                type: .browserSelect,
                title: "Выбрать значение",
                description: "Выбрать «\(args["value"] ?? "")» в списке.",
                target: args["element_id"] ?? "",
                scope: "Браузер Алакеи", args: args
            )
        case "browser_submit":
            return Action(
                type: .browserSubmit,
                title: "Отправить форму",
                description: "Нажать кнопку отправки на сайте.",
                target: args["element_id"] ?? args["text"] ?? "",
                scope: "Браузер Алакеи", reversible: false, args: args
            )
        case "browser_wait":
            return Action(
                type: .browserWait,
                title: "Дождаться страницы",
                description: "Подождать загрузку или обновление страницы.",
                target: "Текущая страница", scope: "Только чтение", args: args
            )
        case "browser_screenshot":
            return Action(
                type: .browserScreenshot,
                title: "Снимок страницы",
                description: "Сделать снимок видимой области браузера.",
                target: "Текущая страница", scope: "Только чтение", args: args
            )
        case "browser_hard_reload":
            return Action(
                type: .browserHardReload,
                title: "Принудительная перезагрузка",
                description: "Перезагрузить страницу без кеша.",
                target: "Текущая страница", scope: "Браузер Алакеи", args: args
            )
        case "browser_zoom":
            let factor = args["factor"] ?? "1.0"
            return Action(
                type: .browserZoom,
                title: "Масштаб браузера",
                description: "Установить масштаб \(factor).",
                target: factor, scope: "Браузер Алакеи", args: args
            )
        case "browser_clear_cookies":
            return Action(
                type: .browserClearCookies,
                title: "Очистить cookie",
                description: "Удалить файлы cookie. Вы можете выйти из всех аккаунтов.",
                target: "Файлы cookie", scope: "Браузер Алакеи",
                reversible: false, args: args
            )
        case "browser_clear_cache":
            return Action(
                type: .browserClearCache,
                title: "Очистить кеш",
                description: "Удалить кеш страниц. Страницы будут загружаться медленнее.",
                target: "Кеш браузера", scope: "Браузер Алакеи",
                reversible: false, args: args
            )
        case "browser_highlight_element":
            let target = args["element_id"] ?? args["text"] ?? ""
            return Action(
                type: .browserHighlightElement,
                title: "Подсветить элемент",
                description: "Визуально выделить элемент на странице: \(target)",
                target: target, scope: "Браузер Алакеи", args: args
            )
        case "browser_extract_data":
            return Action(
                type: .browserExtractData,
                title: "Извлечь данные страницы",
                description: "Получить структурированные данные: контакты, ссылки, цены, соцсети.",
                target: "Текущая страница", scope: "Только чтение", args: args
            )
        case "browser_seo_audit":
            return Action(
                type: .browserSeoAudit,
                title: "SEO-аудит страницы",
                description: "Проверить title, description, H1, alt-теги, ссылки и структуру.",
                target: "Текущая страница", scope: "Только чтение", args: args
            )
        default:
            return nil
        }
    }

    private static let schemas: [[String: Any]] = [
        fn(
            "browser_open",
            "Открыть URL или поисковый запрос во встроенном браузере Алакеи.",
            ["url": ["type": "string", "description": "URL или поисковый запрос"]],
            ["url"]
        ),
        fn(
            "browser_read_page",
            "Прочитать текущую страницу перед любыми кликами или вводом.",
            [:],
            []
        ),
        fn(
            "browser_click",
            "Нажать конкретный элемент. Используй element_id из последнего browser_read_page; text — только запасной вариант.",
            [
                "element_id": ["type": "string", "description": "ID вида ak-1 из browser_read_page"],
                "text": ["type": "string", "description": "Видимый текст как запасной вариант"],
            ],
            []
        ),
        fn(
            "browser_type",
            "Ввести текст в поле. Не используй для паролей, кодов, платёжных или других секретных данных.",
            [
                "field": ["type": "string", "description": "Placeholder, aria-label, name или id поля"],
                "element_id": ["type": "string", "description": "ID поля вида ak-1 из browser_read_page"],
                "text": ["type": "string", "description": "Текст для ввода"],
            ],
            ["text"]
        ),
        fn("browser_back", "Вернуться на предыдущую страницу.", [:], []),
        fn("browser_reload", "Обновить текущую страницу.", [:], []),
        fn(
            "browser_scroll",
            "Прокрутить страницу вверх или вниз.",
            [
                "direction": ["type": "string", "enum": ["up", "down"]],
                "amount": ["type": "integer", "description": "Расстояние 120–1600 пикселей"],
            ],
            ["direction"]
        ),
        fn(
            "browser_select",
            "Выбрать значение в элементе select по ID из browser_read_page.",
            [
                "element_id": ["type": "string"],
                "value": ["type": "string"],
            ],
            ["element_id", "value"]
        ),
        fn(
            "browser_submit",
            "Отправить форму или нажать подтверждающую кнопку. Всегда требует подтверждения пользователя.",
            [
                "element_id": ["type": "string"],
                "text": ["type": "string"],
            ],
            []
        ),
        fn(
            "browser_wait",
            "Подождать динамическое обновление или завершение загрузки.",
            ["milliseconds": ["type": "integer", "description": "200–10000"]],
            []
        ),
        fn("browser_screenshot", "Сделать снимок видимой области страницы и скопировать в буфер обмена.", [:], []),
        fn("browser_hard_reload", "Принудительно перезагрузить страницу без кеша.", [:], []),
        fn(
            "browser_zoom",
            "Установить масштаб страницы.",
            ["factor": ["type": "number", "description": "Масштаб: 0.25–5.0, обычно 1.0"]],
            ["factor"]
        ),
        fn("browser_clear_cookies",
           "Очистить файлы cookie. Требует подтверждения — пользователь может выйти из аккаунтов.",
           [:], []),
        fn("browser_clear_cache",
           "Очистить кеш браузера. Требует подтверждения пользователя.",
           [:], []),
        fn(
            "browser_highlight_element",
            "Визуально выделить элемент на странице цветной рамкой. Безопасно — только наложение, не меняет сайт. Использовать для: «выдели кнопку Войти», «подсвети блок».",
            [
                "element_id": ["type": "string", "description": "ID вида ak-1 из browser_read_page"],
                "text": ["type": "string", "description": "Видимый текст элемента для поиска"],
                "color": ["type": "string", "description": "CSS-цвет рамки, например rgba(89,196,250,0.9)"],
                "duration_ms": ["type": "integer", "description": "Длительность подсветки в мс (0 = навсегда)"],
                "label": ["type": "string", "description": "Подпись над рамкой"],
            ],
            []
        ),
        fn(
            "browser_extract_data",
            "Извлечь структурированные данные со страницы: контакты, соцсети, услуги, цены, формы, ссылки, JSON-LD. Компактный JSON ≤20KB. Использовать вместо browser_read_page для анализа сайта клиента.",
            [:],
            []
        ),
        fn(
            "browser_seo_audit",
            "SEO-аудит текущей страницы: title, description, H1-H3, canonical, alt-теги изображений, внутренние/внешние ссылки, structured data. Возвращает список проблем и quick wins.",
            [:],
            []
        ),
    ]

    private static func fn(
        _ name: String,
        _ description: String,
        _ properties: [String: Any],
        _ required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}
