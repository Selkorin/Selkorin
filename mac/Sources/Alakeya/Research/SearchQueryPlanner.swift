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
        let year  = Calendar.current.component(.year, from: Date())

        switch intent {
        case .hotelResearch, .travelResearch:
            let location = extractLocation(from: query)
            var queries = [
                "\(query) \(year)",
                "топ отели \(location) рейтинг \(year)",
                "лучшие отели \(location) отзывы \(year)",
                "site:ostrovok.ru отели \(location)",
                "site:101hotels.com отели \(location)",
                "site:tripadvisor.com \(location) hotels best",
                "отели \(location) официальный сайт контакты",
            ]

            // Add price-related queries if not explicitly mentioned
            if !query.lowercased().contains("цен") && !query.lowercased().contains("дешев") && !query.lowercased().contains("дорог") {
                queries += [
                    "отели \(location) цены \(year)",
                    "дешевые отели \(location)",
                    "лучшие соотношение цена качество \(location)"
                ]
            }

            // Add location-specific queries
            if !location.isEmpty {
                queries += [
                    "гостиницы \(location) центр",
                    "отели \(location) побережье",
                    "\(location) проживание"
                ]
            }

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .localBusinessSearch, .contactResearch:
            let what = extractBusinessType(from: query)
            let where_ = extractLocation(from: query)
            var queries = [
                "\(what) \(where_) телефон",
                "\(what) \(where_) рейтинг \(year)",
                "\(what) \(where_) отзывы",
                "site:2gis.ru \(what) \(where_)",
                "\(what) \(where_) официальный сайт контакты",
                "\(what) \(where_) адрес телефон",
                "\(what) \(where_) сайт контакты",
            ]

            // Add additional context-aware queries
            if !where_.isEmpty {
                queries += [
                    "\(what) рядом \(where_)",
                    "\(what) в центре \(where_)",
                    "\(what) адрес \(where_)"
                ]
            }

            // Add working hours queries for businesses
            if what.contains("магазин") || what.contains("ресторан") || what.contains("кафе") {
                queries += [
                    "\(what) \(where_) режим работы",
                    "\(what) \(where_) время работы"
                ]
            }

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .clientResearch:
            let topic = query.replacingOccurrences(of: #"(?i)(клиент|лид|база|потенциальн)"#,
                                                    with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            var queries = [
                "\(topic) компании список",
                "\(topic) контакты email телефон",
                "site:2gis.ru \(topic)",
                "\(topic) официальный сайт",
                "\(topic) каталог компаний",
            ]

            // Add industry-specific queries
            queries += [
                "\(topic) рынок\(year)",
                "\(topic) поставщики производители",
                "\(topic) компании крупные"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .socialProfileResearch:
            var queries = [
                "\(query) ВКонтакте профиль",
                "\(query) Instagram",
                "\(query) LinkedIn",
                "\(query) официальный сайт",
                "\(query) интервью",
                "\(query) биография",
            ]

            // Add platform-specific variations
            queries += [
                "\(query) vk.com",
                "\(query) личный сайт",
                "\(query) блог",
                "\(query) соцсети"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .topList:
            var queries = [
                "\(query) \(year)",
                "\(query) рейтинг лучших",
                "\(query) топ 10 \(year)",
                "\(query) топ 20 \(year)",
                "\(query) сравнение обзор \(year)",
                "site:rbc.ru \(query)",
                "site:vc.ru \(query)",
                "\(query) выбор рекомендаци",
                "\(query) рейтинг экспертов",
            ]

            // Add comparison queries
            queries += [
                "\(query) что лучше",
                "\(query) сравнение вариантов",
                "\(query) плюсы минусы"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .factualQuestion:
            var queries = [
                query,
                "\(query) официальный источник",
                "\(query) wikipedia",
                "\(query) \(year)",
                "\(query) исследование данные",
            ]

            // Add authority source queries
            queries += [
                "\(query) научные исследования",
                "\(query) экспертное мнение",
                "\(query) статистика данные",
                "\(query) официальные данные"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .academicResearch:
            // Graduate/postgraduate-level coverage: peer-reviewed sources in
            // Russian AND English, reviews/meta-analyses first, then primary
            // studies, methodology and critique. Works for any profession —
            // the scholarly databases below are cross-disciplinary.
            let queries = [
                query,
                "\(query) систематический обзор",
                "\(query) мета-анализ",
                "\(query) диссертация автореферат",
                "\(query) site:cyberleninka.ru",
                "\(query) site:elibrary.ru",
                "\(query) review \(year)",
                "\(query) state of the art",
                "\(query) systematic review OR meta-analysis",
                "\(query) site:scholar.google.com",
                "\(query) site:arxiv.org",
                "\(query) site:pubmed.ncbi.nlm.nih.gov",
                "\(query) методология исследования критика",
                "\(query) нерешённые проблемы открытые вопросы",
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .currentInfo:
            var queries = [
                "\(query) \(year)",
                "\(query) последние данные",
                "\(query) актуально \(year)",
                "\(query) новости \(year)",
                "\(query) сегодня",
            ]

            // Add news source queries
            queries += [
                "\(query) последние новости",
                "site:rbc.ru \(query)",
                "site:ria.ru \(query)",
                "site:interfax.ru \(query)"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .seoResearch:
            return [
                query,
                "\(query) seo аудит",
                "\(query) технический анализ",
                "\(query) анализ конкурентов",
                "site:ahrefs.com \(query)",
                "site:semrush.com \(query)"
            ]

        case .productResearch:
            var queries = [
                "\(query) \(year)",
                "\(query) обзор сравнение",
                "\(query) рейтинг лучших \(year)",
                "\(query) отзывы покупателей",
                "site:market.yandex.ru \(query)",
                "site:ozon.ru \(query)",
                "site:wb.ru \(query)",
            ]

            // Add purchase-related queries
            queries += [
                "\(query) купить",
                "\(query) цена",
                "\(query) где дешевле",
                "\(query) обзор характеристик"
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        case .exportTask, .documentResearch, .tableResearch:
            return [query]

        case .general:
            let queries = [
                query,
                "\(query) \(year)",
                "\(query) обзор",
                "\(query) что это",
                "\(query) как работает",
            ]

            return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    // MARK: - Preferred sources

    private static func preferredSources(intent: ResearchIntent, query: String) -> [String] {
        switch intent {
        case .hotelResearch, .travelResearch:
            return ["ostrovok.ru", "101hotels.com", "tripadvisor.com", "votpusk.ru", "official sites"]
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return ["2gis.ru", "official sites", "company contact pages", "schema.org/json-ld"]
        case .factualQuestion:
            return ["wikipedia.org", "rbc.ru", "ria.ru", "interfax.ru"]
        case .academicResearch:
            return ["scholar.google.com", "cyberleninka.ru", "elibrary.ru",
                    "arxiv.org", "pubmed.ncbi.nlm.nih.gov", "semanticscholar.org",
                    "nature.com", "sciencedirect.com", "link.springer.com", "jstor.org"]
        case .socialProfileResearch:
            return ["vk.com", "instagram.com", "linkedin.com"]
        case .topList:
            return ["rbc.ru", "kommersant.ru", "vc.ru", "habr.com"]
        default:
            return ["duckduckgo", "bing", "official sites", "trusted publications"]
        }
    }

    // MARK: - Extraction goal + fields

    private static func extractionProfile(intent: ResearchIntent) -> (String, [String]) {
        switch intent {
        case .hotelResearch, .travelResearch:
            return ("ranked_hotel_table", ["rank", "name", "location", "rating", "reviewCount", "phone", "priceRange", "whySelected", "source"])
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return ("business_cards", ["name", "phone", "address", "website", "rating", "category", "source"])
        case .socialProfileResearch:
            return ("profile_info", ["name", "platform", "url", "bio", "followers"])
        case .topList:
            return ("list_items", ["name", "rank", "description", "rating", "source"])
        case .seoResearch:
            return ("seo_data", ["title", "description", "h1", "canonical", "robotsMeta", "problems", "quickWins"])
        case .academicResearch:
            return ("scholarly_synthesis", ["claim", "evidence", "methodology", "sampleOrScope",
                                            "limitations", "competingViews", "sourceTier", "citation", "openQuestions"])
        default:
            return ("article_content", ["title", "summary", "keyFacts", "source"])
        }
    }

    // MARK: - Instructions

    private static func buildInstructions(intent: ResearchIntent, query: String) -> String {
        switch intent {
        case .hotelResearch, .travelResearch:
            return "Выполни спокойный поиск через search_internet/browser_agent_search без открытия UI-браузера; для рейтингов и подборок извлекай страницы, а не только SERP. Не используй Яндекс/Google как массовый источник по умолчанию. Не отвечай списком ссылок. Собери кандидатов из нескольких источников, отфильтруй антибот/капчу/тонкие страницы, дедуплицируй по названию, выбери лучшие и дай конечный ответ таблицей: № | Отель | Локация | Почему выбран | Рейтинг/отзывы | Телефон/контакты | Доверие | Источник. Если телефона или рейтинга нет — ставь «—», не выдумывай. Ниже блок «Источники» с Markdown-ссылками и короткая строка о частичности данных."
        case .localBusinessSearch, .contactResearch, .clientResearch:
            return "Начни с 2ГИС/официальных сайтов/contact pages через browser_agent_search/search_internet без открытия UI-браузера. UI-карты используй только если пользователь явно просит карты или headless-поиск не дал контакты. Не используй Яндекс по умолчанию. Собери имя, телефон, адрес, сайт, доверие/статус источника. Отбрасывай строки без реального названия организации. Источники оформляй как [Название](url), без голых длинных URL. Предложи экспорт в CSV или Google Sheets."
        case .factualQuestion:
            return "Сначала проверь официальный источник. Затем минимум 1 независимый. Если данные расходятся — укажи это. Добавь ссылки в источники."
        case .academicResearch:
            return """
            Работай на уровне аспирантского обзора литературы, независимо от дисциплины. Протокол:
            1) Иерархия источников: сначала систематические обзоры и мета-анализы, затем рецензируемые статьи и диссертации, затем монографии/стандарты; новостные и блоговые источники — только как иллюстрация, не как доказательство. Ищи и на русском, и на английском.
            2) Для каждого ключевого утверждения фиксируй: доказательство, методологию (как получены данные, выборка/охват), ограничения и уровень доверия к источнику (обзор > статья > препринт > СМИ).
            3) Покажи конкурирующие школы/подходы и в чём именно они расходятся — не сглаживай противоречия. Если консенсуса нет, скажи это прямо.
            4) Используй точную терминологию профессии из запроса, дай определения ключевых понятий при первом употреблении.
            5) Заверши разделами: «Методологические ограничения», «Открытые вопросы» (что ещё не решено в области) и «Источники» — оформленными Markdown-ссылками [Автор/Название (год)](url). Не выдумывай DOI и цитаты: если точной ссылки нет — укажи, где её искать (база, журнал, автор).
            """
        case .socialProfileResearch:
            return "Ищи только публичную информацию. Не пытайся получить приватные данные. Укажи источник каждого факта."
        case .seoResearch:
            return "Открой URL, вызови browser_seo_audit, затем browser_extract_data. Сформируй структурированный отчёт с проблемами и рекомендациями."
        case .topList:
            return "Собери минимум 5–10 позиций из разных источников через search_internet/browser_agent_search с извлечением страниц. Не отвечай списком найденных ссылок. Дедуплицируй, выбери лучшее, ранжируй и оформи конечный ответ таблицей с колонками: № | Название | Почему выбрано | Ключевые данные | Источник. Ниже отдельный блок «Источники» с Markdown-ссылками [Название](url), без голых URL."
        default:
            return "Выполни поиск по всем запросам через search_internet или browser_agent_search без открытия UI-браузера. Синтезируй ответ с источниками. Ссылки оформляй как [Название](url), без голых длинных URL."
        }
    }

    // MARK: - NLP helpers

    private static func extractLocation(from query: String) -> String {
        // Enhanced location database with regions and alternative names
        let locationPatterns = [
            // Major cities
            "крым", "москва", "москве", "санкт-петербург", "питер", "спб",
            "севастополь", "ялта", "сочи", "краснодар", "екатеринбург",
            "новосибирск", "казань", "нижний новгород", "самара", "уфа",
            "омск", "ростов-на-дону", "воронеж", "челябинск", "алушта",
            "феодосия", "евпатория", "симферополь", "калининград",

            // Additional major cities
            "красноярск", "пермь", "волгоград", "саратов", "тольятти",
            "барнаул", "иркутск", "ульяновск", "хабаровск", "владивосток",
            "махачкала", "томск", "оренбург", "кемерово", "новокузнецк",
            "рязань", "астрахань", "набережные челны", "пенза", "липецк",
            "киров", "чебоксары", "тула", "калуга", "брянск", "курск",
            "иваново", "смоленск", "владимир", "тверь", "саратов",

            // Crimean region specific
            "керчь", "джанкой", "белогорск", "алушка", "PARTERITE",
            "гаспра", "гурзуф", "ноксарита", "oppo", "мисхор", "симеиз",

            // Regions and areas
            "московская область", "подмосковье", "ленинградская область",
            "краснодарский край", "ростовская область", "сврдловская область",

            // Alternative names and common misspellings
            "спб", "питер", "московской", "екатеринбурге", "новосибирске",
            "нижнем новгороде", "самаре", "уфе", "омске", "ростове", "воронеже",
            "челябинске", "калининграде", "красноярске", "перми", "волгограде"
        ]

        let lower = query.lowercased()

        // Check for multi-word locations first
        for loc in locationPatterns.filter({ $0.contains(" ") }) {
            if lower.contains(loc) {
                return formatLocationName(loc)
            }
        }

        // Then check single-word locations
        for loc in locationPatterns.filter({ !$0.contains(" ") }) {
            if lower.contains(loc) {
                return formatLocationName(loc)
            }
        }

        // Try to extract location using word boundaries
        let words = query.components(separatedBy: " ")
        for (index, word) in words.enumerated() {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if locationPatterns.contains(cleanWord) {
                // Look ahead for multi-word locations
                if index < words.count - 1 {
                    let nextWord = words[index + 1].lowercased().trimmingCharacters(in: .punctuationCharacters)
                    let multiWord = "\(cleanWord) \(nextWord)"
                    if locationPatterns.contains(multiWord) {
                        return formatLocationName(multiWord)
                    }
                }
                return formatLocationName(cleanWord)
            }
        }

        return ""
    }

    private static func formatLocationName(_ location: String) -> String {
        let words = location.components(separatedBy: " ")
        return words.map { word in
            let prefix = word.prefix(1).uppercased()
            let rest = word.dropFirst()
            return prefix + rest
        }.joined(separator: " ")
    }

    private static func extractBusinessType(from query: String) -> String {
        // Enhanced business type database with categories
        let businessCategories: [String: [String]] = [
            "Beauty & Wellness": [
                "салон красоты", "парикмахерская", "барбершоп", "салон", "парикмахер",
                "косметолог", "ногтевой", "маникюр", " pedicure", "татаж", "визаж",
                "солярий", "спа", "массаж", "фитнес", "трениров", "йога", "спортзал"
            ],
            "Food & Dining": [
                "ресторан", "кафе", "столовая", "буфет", "бар", "паб", "клуб",
                "пиццерия", "суши", "караоке", "кофейня", "conditor", "пекарня",
                "гостиный двор", "столовая", "доставка еды", "еда"
            ],
            "Health & Medical": [
                "стоматолог", "зуб", "дантист", "клиника", "больниц", "аптек",
                "врач", "терапевт", "педиатр", "хирург", "офтальмолог", "окулист",
                "медицинск", "здрав", "диспансер", "диагност", "анализ"
            ],
            "Auto & Transport": [
                "автосервис", "автомойк", "шиномонтаж", "авто", "сто", "вто",
                "такси", "перевозк", "грузоперевозк", "логист", "курьер",
                "автомагазол", "запчаст", "масл", "шина", "disk"
            ],
            "Retail & Shopping": [
                "магазин", "супермаркет", "гипермаркет", "торгов", " бутик",
                "одежда", "обувь", "детск", "продукт", "продовольствен",
                "хозтовар", "electronics", "электрон", "technique"
            ],
            "Services": [
                "услуг", "сервис", "ремонт", "чистк", "клининг", "уборк",
                "химчистк", "prache", "юрист", "нотариус", "адвокат", "консульт",
                "обучен", "курс", "репетитор", "школ", "детск сад"
            ],
            "Entertainment": [
                "развлечен", "игорн", "казин", "клуб", "дискотек", " Bowling",
                "бильярд", "кино", "театр", "concert", "выстав", "музей",
                "парк", "attraction", "развлекатель"
            ],
            "Professional": [
                "компани", "фирм", "предприят", "организ", "офис", "бизнес",
                "consulting", "консалтинг", "marketing", "маркетинг", "reklama",
                "design", "дизайн", "it", "разработк", "программ"
            ]
        ]

        let lower = query.lowercased()

        // Check for specific business types
        for (_, types) in businessCategories {
            for type in types {
                if lower.contains(type) {
                    return type
                }
            }
        }

        // Extract first meaningful noun phrase (improved heuristic)
        let words = query.components(separatedBy: " ")
        var businessWords: [String] = []

        for word in words {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            // Skip common stop words
            let stopWords = ["найди", "найти", "покажи", "список", "все", "лучшие", "хорошие", "хорош", "лучш", "топ", "рейтинг", "близ", "ряд", "около"]
            if !stopWords.contains(cleanWord) && cleanWord.count > 2 {
                businessWords.append(cleanWord)
            }
        }

        return businessWords.prefix(3).joined(separator: " ")
    }
}
