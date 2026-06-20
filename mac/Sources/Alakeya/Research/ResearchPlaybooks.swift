import Foundation

// ============================================================
// ResearchPlaybooks.swift — predefined research workflows.
// Each playbook defines the step sequence, data schema,
// and response format for a specific research task type.
// ============================================================

struct ResearchPlaybook {
    let name: String
    let description: String
    let intentTypes: [ResearchIntent]
    let steps: [String]
    let preferredTools: [String]
    let outputSchema: [String: String]
    let exportSuggestion: String
    let responseTemplate: String
}

enum ResearchPlaybooks {

    // MARK: - All playbooks

    static let all: [ResearchPlaybook] = [
        topHotels,
        localBusinessContacts,
        factCheck,
        seoResearch,
        documentReport,
        peopleResearch,
        general,
    ]

    static func playbook(for intent: ResearchIntent) -> ResearchPlaybook {
        all.first { $0.intentTypes.contains(intent) } ?? general
    }

    // MARK: - Definitions

    static let topHotels = ResearchPlaybook(
        name: "TopHotelsPlaybook",
        description: "Найти, оценить и ранжировать отели или туристические объекты",
        intentTypes: [.hotelResearch, .travelResearch],
        steps: [
            "1. Вызвать research_plan для генерации запросов",
            "2. Выполнить 3–5 поисков через browser_open",
            "3. На каждой странице вызвать extract_hotel_cards",
            "4. Дедуплицировать по названию, ранжировать по рейтингу",
            "5. Собрать ≥5 отелей с источниками",
            "6. Предложить экспорт: PDF, Excel, Word",
        ],
        preferredTools: ["research_plan", "browser_open", "extract_hotel_cards", "quality_score_results", "export_pdf", "export_csv"],
        outputSchema: [
            "name": "string", "location": "string", "stars": "int",
            "rating": "float", "reviewCount": "int", "priceFrom": "string", "source": "string",
        ],
        exportSuggestion: "PDF, Excel/CSV, Word",
        responseTemplate: """
        **Топ отелей: [место]**
        | Название | Расположение | Рейтинг | Отзывы | Класс |
        |----------|-------------|---------|--------|-------|
        | ...      | ...         | ...     | ...    | ...   |

        > Источники: [chips]
        > Предложение: Выгрузить в PDF / Excel
        """
    )

    static let localBusinessContacts = ResearchPlaybook(
        name: "LocalBusinessContactsPlaybook",
        description: "Собрать контакты местных бизнесов, клиентов, компаний",
        intentTypes: [.localBusinessSearch, .contactResearch, .clientResearch],
        steps: [
            "1. research_plan → generate queries",
            "2. Поиск по 2GIS, Яндекс.Карты, Avito, VK",
            "3. extract_business_cards на каждом источнике",
            "4. Дедуплицировать по названию и телефону",
            "5. Собрать N контактов (сколько запросил пользователь)",
            "6. Предложить экспорт в CSV / Google Sheets",
        ],
        preferredTools: ["research_plan", "browser_open", "extract_business_cards", "extract_contact_cards", "export_csv", "export_docx"],
        outputSchema: [
            "name": "string", "phone": "string", "address": "string",
            "website": "string", "rating": "float", "category": "string",
        ],
        exportSuggestion: "CSV, Google Sheets, Excel",
        responseTemplate: """
        **Найдено [N] контактов: [категория] в [город]**
        | Название | Телефон | Адрес | Сайт | Рейтинг |
        |----------|---------|-------|------|---------|
        | ...      | ...     | ...   | ...  | ...     |

        > Источники: [chips]
        > Выгрузить: CSV / Google Sheets
        """
    )

    static let factCheck = ResearchPlaybook(
        name: "FactCheckPlaybook",
        description: "Проверить факт или найти актуальную информацию",
        intentTypes: [.factualQuestion, .currentInfo, .academicResearch],
        steps: [
            "1. Поиск официального источника",
            "2. Поиск независимого источника",
            "3. Если данные расходятся — пометить как спорное",
            "4. Сформулировать ответ с указанием источников",
        ],
        preferredTools: ["research_plan", "browser_open", "extract_article", "browser_extract_data"],
        outputSchema: ["fact": "string", "confidence": "string", "sources": "[string]"],
        exportSuggestion: "",
        responseTemplate: """
        **Факт:** ...
        **Уверенность:** Высокая / Средняя / Требует проверки
        **Источники:** [chips]
        """
    )

    static let seoResearch = ResearchPlaybook(
        name: "SEOResearchPlaybook",
        description: "SEO-аудит страницы или сайта",
        intentTypes: [.seoResearch],
        steps: [
            "1. browser_open(url)",
            "2. browser_seo_audit()",
            "3. browser_extract_data()",
            "4. Сформировать SEO-отчёт с проблемами и рекомендациями",
            "5. Предложить экспорт в PDF/DOCX",
        ],
        preferredTools: ["browser_open", "browser_seo_audit", "browser_extract_data", "export_pdf", "export_docx"],
        outputSchema: [
            "title": "string", "titleLength": "int", "description": "string",
            "h1Count": "int", "problems": "[string]", "quickWins": "[string]",
        ],
        exportSuggestion: "PDF отчёт, DOCX",
        responseTemplate: """
        **SEO-аудит: [url]**

        **Проблемы:**
        - ...

        **Quick wins:**
        - ...

        > Экспорт: PDF-отчёт / Word
        """
    )

    static let documentReport = ResearchPlaybook(
        name: "DocumentReportPlaybook",
        description: "Создать и экспортировать структурированный документ",
        intentTypes: [.exportTask, .documentResearch, .tableResearch],
        steps: [
            "1. Собрать данные из контекста или предыдущих результатов",
            "2. Структурировать в разделы",
            "3. Вызвать export_pdf / export_docx / export_csv",
            "4. Показать file card в чате",
        ],
        preferredTools: ["export_pdf", "export_docx", "export_csv"],
        outputSchema: ["filePath": "string", "format": "string", "sizeKB": "int"],
        exportSuggestion: "PDF, DOCX, CSV",
        responseTemplate: "📄 Файл создан: [filename] ([size]KB)\nСохранён в: [path]"
    )

    static let peopleResearch = ResearchPlaybook(
        name: "PeopleResearchPlaybook",
        description: "Публичный поиск информации о персоне",
        intentTypes: [.socialProfileResearch],
        steps: [
            "1. Поиск по имени в публичных источниках",
            "2. VK, LinkedIn, официальный сайт",
            "3. Новости и упоминания",
            "4. Синтез с указанием источников",
            "5. НЕ собирать приватную информацию",
        ],
        preferredTools: ["research_plan", "browser_open", "browser_extract_data", "extract_article"],
        outputSchema: ["name": "string", "bio": "string", "profiles": "[url]", "mentions": "[url]"],
        exportSuggestion: "",
        responseTemplate: "**Публичная информация о [имя]:**\n...\n> Источники: [chips]"
    )

    static let general = ResearchPlaybook(
        name: "GeneralResearchPlaybook",
        description: "Общий интернет-поиск",
        intentTypes: [.general],
        steps: [
            "1. research_plan → queries",
            "2. browser_open + browser_extract_data",
            "3. Синтез ответа с источниками",
        ],
        preferredTools: ["research_plan", "browser_open", "browser_extract_data", "extract_article"],
        outputSchema: ["summary": "string", "keyFacts": "[string]", "sources": "[url]"],
        exportSuggestion: "",
        responseTemplate: "**Ответ:**\n...\n\nИсточники: [chips]"
    )
}
