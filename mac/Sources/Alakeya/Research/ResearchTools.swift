import Foundation

// ============================================================
// ResearchTools.swift — ToolHandler for all research tools.
// Provides: research_plan, extract_search_results,
// extract_business_cards, extract_hotel_cards,
// extract_contact_cards, extract_article, quality_score_results.
// ============================================================

struct ResearchTools: ToolHandler {

    var toolNames: [String] { Self.allNames }

    var toolSchemas: [[String: Any]] { Self.schemas }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        switch toolName {
        case "search_internet":
            return Action(type: .searchInternet,
                          title: "Поиск в интернете",
                          description: "Ищу «\(args["query"] ?? "")» в интернете без открытия браузера.",
                          target: args["query"] ?? "", scope: "Search", args: args)
        case "research_plan":
            return Action(type: .researchPlan,
                          title: "Составить план поиска",
                          description: "Анализирую задачу и генерирую стратегию поиска: запросы, источники, данные.",
                          target: args["query"] ?? "", scope: "Research", args: args)
        case "extract_search_results":
            return Action(type: .extractSearchResults,
                          title: "Извлечь результаты поиска",
                          description: "Разбираю страницу поисковой выдачи на структурированный список результатов.",
                          target: "SERP", scope: "Браузер", args: args)
        case "extract_business_cards":
            return Action(type: .extractBusinessCards,
                          title: "Извлечь карточки бизнесов",
                          description: "Извлекаю название, телефон, адрес, сайт, рейтинг бизнесов.",
                          target: "Страница", scope: "Браузер", args: args)
        case "extract_hotel_cards":
            return Action(type: .extractHotelCards,
                          title: "Извлечь карточки отелей",
                          description: "Извлекаю название, рейтинг, цену, отзывы отелей.",
                          target: "Страница", scope: "Браузер", args: args)
        case "extract_contact_cards":
            return Action(type: .extractContactCards,
                          title: "Извлечь контакты",
                          description: "Извлекаю контактные данные: телефоны, email, адреса.",
                          target: "Страница", scope: "Браузер", args: args)
        case "extract_article":
            return Action(type: .extractArticle,
                          title: "Прочитать статью",
                          description: "Извлекаю основной текст статьи без рекламы и навигации.",
                          target: "Страница", scope: "Браузер", args: args)
        case "quality_score_results":
            return Action(type: .qualityScoreResults,
                          title: "Оценить качество источников",
                          description: "Оцениваю и ранжирую список источников по качеству.",
                          target: "Источники", scope: "Research", args: args)
        default:
            return nil
        }
    }

    private static let allNames = [
        "search_internet", "research_plan", "extract_search_results", "extract_business_cards",
        "extract_hotel_cards", "extract_contact_cards", "extract_article",
        "quality_score_results",
    ]

    // MARK: - Schemas

    private static let schemas: [[String: Any]] = [
        fn("search_internet",
           "ВЫПОЛНИТЬ ПОИСК В ИНТЕРНЕТЕ без открытия браузера. Используй для: поиска информации, фактов, новостей, контактов, компаний, рейтингов. НЕ используй browser_open для простого поиска — только для скрапинга конкретной страницы. search_internet возвращает структурированные результаты (title, url, snippet) из поисковой выдачи.",
           ["query": str("Поисковый запрос (на русском или английском)"),
            "max_results": int("Максимум результатов, по умолчанию 15")],
           ["query"]),
        fn("research_plan",
           "ВСЕГДА вызывай первым для задач поиска, рейтингов, контактов, отелей, фактов. Возвращает структурированный план: запросы, источники, цель извлечения. Затем последовательно выполняй запросы через browser_open и extract_* инструменты.",
           ["query": str("Запрос пользователя точно как написан")],
           ["query"]),
        fn("extract_search_results",
           "Извлекает список результатов поиска из текущей SERP-страницы (Google, Яндекс, Bing). Вызывать ПОСЛЕ browser_open с поисковым запросом. Возвращает title, url, snippet для каждого результата.",
           [:], []),
        fn("extract_business_cards",
           "Извлекает карточки локального бизнеса (2GIS, Яндекс.Карты, Avito, каталог). Поля: name, phone, address, website, rating, reviewCount, category, workingHours.",
           ["max_results": int("Максимум карточек, по умолчанию 10")],
           []),
        fn("extract_hotel_cards",
           "Извлекает карточки отелей / гостиниц (Ostrovok, 101hotels, Booking, TripAdvisor). Поля: name, location, stars, rating, reviewCount, priceFrom, amenities, source.",
           ["max_results": int("Максимум карточек, по умолчанию 10")],
           []),
        fn("extract_contact_cards",
           "Извлекает контактные данные: телефоны, email, мессенджеры, адреса. Полезен для страниц 'Контакты'. Возвращает структурированный JSON.",
           [:], []),
        fn("extract_article",
           "Извлекает основной текст статьи / новости / страницы без рекламы, навигации и боковых блоков. Компактный, читаемый текст ≤8000 символов.",
           ["max_chars": int("Максимум символов, по умолчанию 6000")],
           []),
        fn("quality_score_results",
           "Оценивает и ранжирует список источников по качеству. Передай JSON-массив {url, title, snippet}. Возвращает тот же массив с полем score.",
           ["sources_json": str("JSON-массив [{url, title, snippet}]")],
           ["sources_json"]),
    ]

    private static func fn(_ name: String, _ description: String,
                            _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": description,
                      "parameters": ["type": "object", "properties": props,
                                     "required": required, "additionalProperties": false]]]
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
}
