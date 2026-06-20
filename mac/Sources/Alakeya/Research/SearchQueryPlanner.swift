import Foundation

// ============================================================
// SearchQueryPlanner.swift — generates multiple search queries
// for a user request. Returns structured plan the AI executes.
// ============================================================

struct SearchPlan: Codable {
    var intent: String
    var playbook: String
    var queries: [String]
    var preferredSources: [String]
    var extractionGoal: String
    var dataFields: [String]
    var minResults: Int
    var instructions: String
}

enum SearchQueryPlanner {

    // MARK: - Public

    static func plan(for query: String) -> SearchPlan {
        let intent = ResearchIntent.detect(from: query)
        let queries = generateQueries(query: query, intent: intent)
        let sources = preferredSources(intent: intent, query: query)
        let (goal, fields) = extractionProfile(intent: intent)
        let instructions = buildInstructions(intent: intent, query: query)

        return SearchPlan(
            intent: intent.rawValue,
            playbook: intent.playbook,
            queries: queries,
            preferredSources: sources,
            extractionGoal: goal,
            dataFields: fields,
            minResults: intent.minResults,
            instructions: instructions
        )
    }

    // MARK: - Query generation

    private static func generateQueries(query: String, intent: ResearchIntent) -> [String] {
        let lower = query.lowercased()
        let year  = Calendar.current.component(.year, from: Date())

        switch intent {
        case .hotelResearch, .travelResearch:
            let location = extractLocation(from: query)
            return [
                "\(query) \(year)",
                "топ отелей \(location) рейтинг \(year)",
                "лучшие отели \(location) отзывы",
                "site:ostrovok.ru отели \(location)",
                "site:101hotels.com \(location)",
                "site:yandex.ru/travel отели \(location) рейтинг",
                "site:tripadvisor.com \(location) hotels best",
            ].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .localBusinessSearch, .contactResearch:
            let what = extractBusinessType(from: query)
            let where_ = extractLocation(from: query)
            return [
                "\(what) \(where_) телефон",
                "\(what) \(where_) рейтинг \(year)",
                "site:2gis.ru \(what) \(where_)",
                "site:yandex.ru/maps \(what) \(where_)",
                "site:avito.ru \(what) \(where_)",
                "site:vk.com \(what) \(where_)",
                "\(what) \(where_) сайт контакты",
            ]

        case .clientResearch:
            let topic = query.replacingOccurrences(of: #"(?i)(клиент|лид|база|потенциальн)"#,
                                                    with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return [
                "\(topic) компании список",
                "\(topic) контакты email",
                "site:2gis.ru \(topic)",
                "site:avito.ru \(topic)",
                "\(topic) официальный сайт",
            ]

        case .socialProfileResearch:
            return [
                "\(query) ВКонтакте",
                "\(query) Instagram",
                "\(query) LinkedIn",
                "\(query) официальный сайт",
                "\(query) интервью",
            ]

        case .topList:
            return [
                "\(query) \(year)",
                "\(query) рейтинг лучших",
                "\(query) топ 10",
                "\(query) сравнение обзор \(year)",
                "site:rbc.ru \(query)",
            ]

        case .factualQuestion, .academicResearch:
            return [
                query,
                "\(query) официальный источник",
                "\(query) wikipedia",
                "\(query) \(year)",
                "\(query) исследование данные",
            ]

        case .currentInfo:
            return [
                "\(query) \(year)",
                "\(query) последние данные",
                "\(query) актуально",
                "\(query) новости",
            ]

        case .seoResearch:
            return [query]

        case .productResearch:
            return [
                "\(query) \(year)",
                "\(query) обзор сравнение",
                "\(query) лучший рейтинг",
                "\(query) отзывы покупателей",
                "site:market.yandex.ru \(query)",
            ]

        case .exportTask, .documentResearch, .tableResearch:
            return [query]

        case .general:
            return [
                query,
                "\(query) \(year)",
                "\(query) обзор",
            ]
        }
    }

    // MARK: - Preferred sources

    private static func preferredSources(intent: ResearchIntent, query: String) -> [String] {
        switch intent {
        case .hotelResearch, .travelResearch:
            return ["ostrovok.ru", "101hotels.com", "yandex.ru/travel", "tripadvisor.com", "booking.com", "votpusk.ru"]
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return ["2gis.ru", "yandex.ru/maps", "avito.ru", "vk.com"]
        case .factualQuestion, .academicResearch:
            return ["wikipedia.org", "rbc.ru", "ria.ru", "interfax.ru"]
        case .socialProfileResearch:
            return ["vk.com", "instagram.com", "linkedin.com"]
        case .topList:
            return ["rbc.ru", "kommersant.ru", "vc.ru", "habr.com"]
        default:
            return ["yandex.ru", "google.com"]
        }
    }

    // MARK: - Extraction goal + fields

    private static func extractionProfile(intent: ResearchIntent) -> (String, [String]) {
        switch intent {
        case .hotelResearch, .travelResearch:
            return ("hotel_cards", ["name", "location", "rating", "reviewCount", "priceRange", "stars", "source"])
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return ("business_cards", ["name", "phone", "address", "website", "rating", "category", "source"])
        case .socialProfileResearch:
            return ("profile_info", ["name", "platform", "url", "bio", "followers"])
        case .topList:
            return ("list_items", ["name", "rank", "description", "rating", "source"])
        case .seoResearch:
            return ("seo_data", ["title", "description", "h1", "canonical", "robotsMeta", "problems", "quickWins"])
        default:
            return ("article_content", ["title", "summary", "keyFacts", "source"])
        }
    }

    // MARK: - Instructions

    private static func buildInstructions(intent: ResearchIntent, query: String) -> String {
        switch intent {
        case .hotelResearch, .travelResearch:
            return "Выполни каждый запрос в браузере. Используй extract_hotel_cards на каждой странице с результатами. Собери ≥5 отелей. Дедуплицируй по названию. Отсортируй по рейтингу. Добавь источники."
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return "Ищи по картам и справочникам. Используй extract_business_cards. Собери имя, телефон, адрес, сайт для каждого. Предложи экспорт в CSV или Google Sheets."
        case .factualQuestion, .academicResearch:
            return "Сначала проверь официальный источник. Затем минимум 1 независимый. Если данные расходятся — укажи это. Добавь ссылки в источники."
        case .socialProfileResearch:
            return "Ищи только публичную информацию. Не пытайся получить приватные данные. Укажи источник каждого факта."
        case .seoResearch:
            return "Открой URL, вызови browser_seo_audit, затем browser_extract_data. Сформируй структурированный отчёт с проблемами и рекомендациями."
        case .topList:
            return "Собери минимум 5–10 позиций из разных источников. Дедуплицируй. Ранжируй. Добавь критерии оценки в ответ."
        default:
            return "Выполни поиск по всем запросам. Используй extract_article или browser_extract_data. Синтезируй ответ с источниками."
        }
    }

    // MARK: - NLP helpers

    private static func extractLocation(from query: String) -> String {
        let locationPatterns = ["крым", "москва", "москве", "санкт-петербург", "питер", "спб",
                                "севастополь", "ялта", "сочи", "краснодар", "екатеринбург",
                                "новосибирск", "казань", "нижний новгород", "самара", "уфа",
                                "омск", "ростов-на-дону", "воронеж", "челябинск", "алушта",
                                "феодосия", "евпатория", "симферополь", "калининград"]
        let lower = query.lowercased()
        for loc in locationPatterns {
            if lower.contains(loc) {
                return loc.prefix(1).uppercased() + loc.dropFirst()
            }
        }
        return ""
    }

    private static func extractBusinessType(from query: String) -> String {
        let types = ["салон красоты", "парикмахерская", "ресторан", "кафе", "стоматология",
                     "клиника", "автосервис", "магазин", "барбершоп", "спа", "фитнес"]
        let lower = query.lowercased()
        for t in types {
            if lower.contains(t) { return t }
        }
        // Extract first noun-ish chunk (heuristic)
        let words = query.components(separatedBy: " ")
        return words.prefix(3).joined(separator: " ")
    }
}
