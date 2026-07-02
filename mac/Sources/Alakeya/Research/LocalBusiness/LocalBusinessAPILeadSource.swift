import Foundation

// ============================================================
// LocalBusinessAPILeadSource.swift — lead generation through
// structured search APIs (Google Custom Search / Yandex Search API).
// No browser, no captcha: queries are targeted like a media buyer
// would write them, contacts are extracted from titles/snippets and
// validated by LocalBusinessLeadValidator.
// ============================================================

struct APILeadSourceOutcome {
    let attempted: Bool
    let providerNames: [String]
    let leads: [LocalBusinessLead]
    let status: String
}

enum LocalBusinessAPILeadSource {

    /// True when at least one structured search API is configured.
    static var isConfigured: Bool {
        !SearchProviderRegistry.shared.apiProviders.isEmpty
    }

    // MARK: - Entry

    static func collect(query: LocalBusinessQuery, city: String) async -> APILeadSourceOutcome {
        let providers = SearchProviderRegistry.shared.apiProviders
        guard !providers.isEmpty else {
            return APILeadSourceOutcome(attempted: false, providerNames: [], leads: [], status: "not_configured")
        }

        let searchQueries = targetedQueries(category: query.category, city: city, requireNoWebsite: query.requireNoWebsite)
        var leads: [LocalBusinessLead] = []
        var usedProviders: Set<String> = []

        for provider in providers {
            for q in searchQueries {
                guard leads.count < query.targetCount * 2 else { break }
                guard let results = try? await provider.search(query: q) else { continue }
                usedProviders.insert(provider.name)
                for result in results {
                    if let lead = lead(from: result, query: query, city: city, provider: provider.name) {
                        leads.append(lead)
                    }
                }
            }
        }

        let deduped = dedupe(leads)
        return APILeadSourceOutcome(
            attempted: true,
            providerNames: Array(usedProviders),
            leads: deduped,
            status: deduped.isEmpty ? "no_valid_rows" : "usable"
        )
    }

    // MARK: - Query strategy (smart targeting)

    /// Query set a targeting specialist would run: direct contact queries,
    /// directory-scoped queries, and social-profile queries for businesses
    /// that live on VK/Instagram instead of их own site.
    static func targetedQueries(category: String, city: String, requireNoWebsite: Bool) -> [String] {
        var queries = [
            "\(category) \(city) телефон контакты",
            "\(category) \(city) \"@\" email почта",
            "\(category) \(city) официальный сайт контакты",
            "site:vk.com \(category) \(city)",
            "site:2gis.ru \(category) \(city)",
            "site:zoon.ru \(category) \(city)",
        ]
        if requireNoWebsite {
            // Businesses without a website concentrate in socials/маркетплейсы услуг.
            queries = [
                "site:vk.com \(category) \(city) телефон",
                "site:instagram.com \(category) \(city)",
                "\(category) \(city) запись телефон whatsapp",
            ] + queries
        }
        return queries
    }

    // MARK: - Extraction

    private static func lead(
        from result: SearchResult,
        query: LocalBusinessQuery,
        city: String,
        provider: String
    ) -> LocalBusinessLead? {
        let combined = result.title + " • " + result.snippet
        let phone = firstPhone(in: combined)
        let email = firstEmail(in: combined)

        // Contact-less generic SERP rows are noise, not leads.
        guard !phone.isEmpty || !email.isEmpty || isSocialProfile(result.url) else { return nil }

        let name = cleanName(result.title, url: result.url)
        guard LocalBusinessLeadValidator.hasUsableName(name) else { return nil }

        let host = URL(string: result.url)?.host?
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) ?? ""

        var lead = LocalBusinessLead(
            name: name,
            category: query.category,
            city: city,
            address: "",
            phone: phone,
            email: email,
            website: isDirectory(host) ? "" : host,
            websiteStatus: LocalBusinessLeadValidator.classifyWebsite(result.url),
            sourceName: provider == "YandexSearch" ? "Яндекс API" : "Google API",
            sourceURL: result.url,
            notes: "Найдено через поисковый API",
            confidence: phone.isEmpty && email.isEmpty ? 0.5 : 0.75
        )
        lead = LocalBusinessLeadValidator.validate(lead)
        return lead
    }

    /// First plausible RU/international phone in free text.
    static func firstPhone(in text: String) -> String {
        let pattern = #"(?:\+7|8|\+\d{1,3})[\s\-\(]?\d{3}[\)\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let candidate = nsText.substring(with: match.range)
            if LocalBusinessLeadValidator.isValidPhone(candidate) { return candidate }
        }
        return ""
    }

    /// First plausible email in free text (skips image filenames etc.).
    static func firstEmail(in text: String) -> String {
        let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return "" }
        let email = ((text as NSString).substring(with: match.range)).lowercased()
        let junkSuffixes = [".png", ".jpg", ".jpeg", ".gif", ".webp"]
        if junkSuffixes.contains(where: { email.hasSuffix($0) }) { return "" }
        return email
    }

    private static func isSocialProfile(_ url: String) -> Bool {
        let socials = ["vk.com/", "instagram.com/", "t.me/"]
        return socials.contains { url.contains($0) }
    }

    private static func isDirectory(_ host: String) -> Bool {
        let directories = ["2gis.ru", "zoon.ru", "yandex.ru", "google.com", "flamp.ru",
                           "otzovik.com", "prodoctorov.ru", "yell.ru", "avito.ru"]
        return directories.contains { host.contains($0) }
    }

    private static func cleanName(_ raw: String, url: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" | ", " — ", " – ", " - ", " :: ", " · "] {
            if let range = value.range(of: separator), range.lowerBound > value.startIndex {
                value = String(value[..<range.lowerBound])
                break
            }
        }
        value = value.replacingOccurrences(
            of: #"(?i)\s*(официальный\s+сайт|контакты|отзывы|цены|— vk|вконтакте)\s*$"#,
            with: "", options: .regularExpression
        )
        if value.isEmpty {
            value = URL(string: url)?.host ?? url
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t.,;:|—-"))
    }

    private static func dedupe(_ leads: [LocalBusinessLead]) -> [LocalBusinessLead] {
        var seen: Set<String> = []
        var out: [LocalBusinessLead] = []
        for lead in leads {
            let key = LocalBusinessLeadValidator.deduplicateKey(lead)
            if seen.insert(key).inserted { out.append(lead) }
        }
        return out
    }
}
