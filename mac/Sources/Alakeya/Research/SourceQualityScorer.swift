import Foundation

// ============================================================
// SourceQualityScorer.swift — scores and ranks search sources
// so the AI prioritizes high-quality data.
// ============================================================

struct ScoredSource {
    let url: String
    let title: String
    let score: Int
    let reasons: [String]

    var isHighQuality: Bool { score >= 40 }
    var isLowQuality:  Bool { score < 10 }
}

enum SourceQualityScorer {

    // MARK: - Scoring tiers (additive)

    private static let officialDomains: Set<String> = [
        "gov.ru", "kremlin.ru", "rosstat.gov.ru", "minfin.gov.ru",
        "who.int", "un.org", "wikipedia.org",
    ]
    private static let academicDomains: Set<String> = [
        "scholar.google.com", "cyberleninka.ru", "elibrary.ru",
        "arxiv.org", "pubmed.ncbi.nlm.nih.gov", "ncbi.nlm.nih.gov",
        "semanticscholar.org", "nature.com", "science.org",
        "sciencedirect.com", "link.springer.com", "springer.com",
        "jstor.org", "ieee.org", "ieeexplore.ieee.org", "dl.acm.org",
        "wiley.com", "onlinelibrary.wiley.com", "tandfonline.com",
        "mdpi.com", "plos.org", "frontiersin.org", "researchgate.net",
        "dissercat.com", "istina.msu.ru",
    ]
    private static let reviewPlatforms: Set<String> = [
        "tripadvisor.com", "tripadvisor.ru", "booking.com",
        "ostrovok.ru", "101hotels.com", "votpusk.ru",
        "2gis.ru", "zoon.ru", "flamp.ru",
    ]
    private static let mapDirectories: Set<String> = [
        "2gis.ru", "yell.com",
    ]
    private static let trustedNews: Set<String> = [
        "rbc.ru", "kommersant.ru", "interfax.ru", "ria.ru",
        "tass.ru", "vedomosti.ru", "vc.ru", "habr.com",
    ]
    private static let lowQualityPatterns: [String] = [
        "spam", "clickbait", "forum", "форум", "otvet.mail.ru",
        "pikabu.ru", "пикабу", "reddit.com",
    ]
    private static let botChallengePatterns: [String] = [
        "captcha", "капча", "не робот", "подтвердите, что", "verify you are human",
        "unusual traffic", "access denied", "доступ ограничен",
    ]
    private static let searchEngineDomains: Set<String> = [
        "yandex.ru", "google.com", "google.ru", "bing.com", "duckduckgo.com",
    ]

    static func score(url: String, title: String, snippet: String = "", isBlocked: Bool = false) -> ScoredSource {
        var score = 20 // base
        var reasons: [String] = []

        let domain = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
        let combined = (url + title + snippet).lowercased()

        if searchEngineDomains.contains(domain) || domain.hasSuffix(".yandex.ru") || domain.hasSuffix(".google.com") {
            score -= 25; reasons.append("поисковая выдача, не первоисточник")
        }
        // Official / authoritative
        if officialDomains.contains(domain) || domain.hasSuffix(".gov.ru") {
            score += 30; reasons.append("официальный источник")
        }
        // Peer-reviewed / scholarly (highest tier for research tasks)
        if academicDomains.contains(domain) || domain.hasSuffix(".edu") || domain.hasSuffix(".ac.uk") {
            score += 35; reasons.append("научный рецензируемый источник")
        }
        // Review platforms
        if reviewPlatforms.contains(domain) {
            score += 20; reasons.append("рейтинговая платформа")
        }
        // Map/directory
        if mapDirectories.contains(domain) {
            score += 20; reasons.append("справочник/карты")
        }
        // Trusted news
        if trustedNews.contains(domain) {
            score += 15; reasons.append("авторитетное издание")
        }
        // Has rating/review info
        if combined.range(of: #"\d[.,]\d\s*(звезд|★|\*|рейтинг)"#, options: .regularExpression) != nil {
            score += 10; reasons.append("содержит рейтинг")
        }
        // Has contact info
        if combined.range(of: #"\+7|\bтел\b|телефон|email"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 10; reasons.append("есть контакты")
        }
        // Current year
        let year = Calendar.current.component(.year, from: Date())
        if combined.contains(String(year)) || combined.contains(String(year - 1)) {
            score += 15; reasons.append("актуальная дата")
        }
        // Structured data signals
        if combined.contains("json-ld") || combined.contains("schema.org") {
            score += 10; reasons.append("структурированные данные")
        }
        // Low quality signals
        if lowQualityPatterns.contains(where: { combined.contains($0) }) {
            score -= 15; reasons.append("низкокачественный источник")
        }
        if botChallengePatterns.contains(where: { combined.contains($0) }) {
            score -= 60; reasons.append("антибот/капча")
        }
        // Blocked / thin
        if isBlocked {
            score -= 40; reasons.append("заблокировано")
        }
        // Very short snippet
        if !snippet.isEmpty && snippet.count < 50 {
            score -= 10; reasons.append("мало контента")
        }

        return ScoredSource(url: url, title: title, score: min(100, max(0, score)), reasons: reasons)
    }

    /// Ranks a list of (url, title, snippet) tuples.
    static func rank(_ sources: [(url: String, title: String, snippet: String)]) -> [ScoredSource] {
        sources
            .map { score(url: $0.url, title: $0.title, snippet: $0.snippet) }
            .sorted { $0.score > $1.score }
    }

    /// Returns a compact JSON description of ranked sources for the AI.
    static func rankJSON(_ sources: [(url: String, title: String, snippet: String)]) -> String {
        let ranked = rank(sources)
        let items = ranked.map { s -> [String: Any] in
            [
                "url": s.url,
                "title": s.title,
                "score": s.score,
                "reasons": s.reasons,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
}
