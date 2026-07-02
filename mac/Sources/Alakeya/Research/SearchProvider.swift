import Foundation

// ============================================================
// SearchProvider.swift — abstraction for search backends.
// BrowserSearchProvider uses existing BrowserPane (always available).
// GoogleCustomSearchProvider uses API key (optional).
// ============================================================

struct SearchResult {
    let title: String
    let url: String
    let snippet: String
    let position: Int
}

protocol SearchProvider {
    var name: String { get }
    var isAvailable: Bool { get }
    func search(query: String) async throws -> [SearchResult]
}

// MARK: - Registry

final class SearchProviderRegistry {
    static let shared = SearchProviderRegistry()
    private init() {}

    var providers: [SearchProvider] = [
        GoogleCustomSearchProvider(),
        YandexSearchProvider(),
        BrowserSearchProvider(),
    ]

    var available: [SearchProvider] { providers.filter { $0.isAvailable } }

    /// API providers that return structured results without opening a
    /// browser (no bot challenges) — the backbone of the lead parser.
    var apiProviders: [SearchProvider] {
        providers.filter { $0.isAvailable && $0.name != "BrowserSearch" }
    }

    func primaryProvider() -> SearchProvider {
        // Prefer structured APIs when configured, else browser fallback.
        if let api = apiProviders.first { return api }
        return providers.first(where: { $0.name == "BrowserSearch" }) ?? BrowserSearchProvider()
    }
}

// MARK: - Browser search provider

struct BrowserSearchProvider: SearchProvider {
    let name = "BrowserSearch"
    var isAvailable: Bool { true }

    func search(query: String) async throws -> [SearchResult] {
        // Opens query in browser as a manual fallback. Automated research
        // should normally use search_internet/browser_agent_search instead.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://duckduckgo.com/html/?q=\(encoded)"
        await MainActor.run { AlakeyaBrowser.shared.open(searchURL) }
        // Return empty; AI will call extract_search_results after browser_wait
        return []
    }
}

// MARK: - Google Custom Search provider

struct GoogleCustomSearchProvider: SearchProvider {
    let name = "GoogleCustomSearch"

    var isAvailable: Bool {
        !apiKey.isEmpty && !cx.isEmpty
    }

    private var apiKey: String {
        ConnectorAuthStore.shared.loadToken(for: "google_search") ?? ""
    }
    private var cx: String {
        UserDefaults.standard.string(forKey: "alakeya.google_search.cx") ?? ""
    }

    func search(query: String) async throws -> [SearchResult] {
        guard isAvailable else {
            throw SearchError.notConfigured("Google Custom Search не настроен. Добавьте API key и CX в Настройки → Коннекторы → Google Search.")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "https://www.googleapis.com/customsearch/v1?key=\(apiKey)&cx=\(cx)&q=\(encoded)&num=10&hl=ru"
        guard let url = URL(string: urlStr) else { throw SearchError.invalidQuery }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SearchError.apiError("Google Search API ответил с ошибкой")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let items = json["items"] as? [[String: Any]] ?? []
        return items.enumerated().map { i, item in
            SearchResult(
                title:   item["title"]   as? String ?? "",
                url:     item["link"]    as? String ?? "",
                snippet: item["snippet"] as? String ?? "",
                position: i + 1
            )
        }
    }
}

// MARK: - Yandex Search API provider

/// Yandex Search API (XML, via Yandex Cloud): needs an API key and a
/// Cloud folder id. Structured results, no captcha — unlike scraping
/// yandex.ru/search HTML. https://yandex.cloud/docs/search-api/
struct YandexSearchProvider: SearchProvider {
    let name = "YandexSearch"

    var isAvailable: Bool {
        !apiKey.isEmpty && !folderID.isEmpty
    }

    private var apiKey: String {
        ConnectorAuthStore.shared.loadToken(for: "yandex_search") ?? ""
    }
    private var folderID: String {
        UserDefaults.standard.string(forKey: "alakeya.yandex_search.folder") ?? ""
    }

    func search(query: String) async throws -> [SearchResult] {
        guard isAvailable else {
            throw SearchError.notConfigured("Яндекс Поиск не настроен. Добавьте API key в Настройки → Подключения → Яндекс Поиск и folder id.")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let groupby = "attr%3D%22%22.mode%3Dflat.groups-on-page%3D10.docs-in-group%3D1"
        let urlStr = "https://yandex.ru/search/xml?folderid=\(folderID)&apikey=\(apiKey)&query=\(encoded)&l10n=ru&filter=strict&groupby=\(groupby)"
        guard let url = URL(string: urlStr) else { throw SearchError.invalidQuery }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SearchError.apiError("Yandex Search API ответил с ошибкой")
        }
        let xml = String(data: data, encoding: .utf8) ?? ""
        if xml.contains("<error") {
            throw SearchError.apiError("Yandex Search API: проверьте API key и folder id")
        }
        return Self.parseXML(xml)
    }

    /// Defensive tag-level parsing — the XML schema is flat and stable,
    /// a full XMLParser delegate isn't worth the ceremony here.
    static func parseXML(_ xml: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let docPattern = #"<doc[^>]*>([\s\S]*?)</doc>"#
        guard let docRegex = try? NSRegularExpression(pattern: docPattern) else { return [] }
        let nsXML = xml as NSString
        let matches = docRegex.matches(in: xml, range: NSRange(location: 0, length: nsXML.length))

        for (i, match) in matches.enumerated() {
            let doc = nsXML.substring(with: match.range(at: 1))
            let url = firstTag("url", in: doc)
            guard !url.isEmpty else { continue }
            let title = stripTags(firstTag("title", in: doc))
            let passages = allTags("passage", in: doc).map(stripTags).joined(separator: " ")
            let headline = stripTags(firstTag("headline", in: doc))
            results.append(SearchResult(
                title: title.isEmpty ? url : title,
                url: url,
                snippet: passages.isEmpty ? headline : passages,
                position: i + 1
            ))
        }
        return results
    }

    private static func firstTag(_ tag: String, in text: String) -> String {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return "" }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func allTags(_ tag: String, in text: String) -> [String] {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range(at: 1)) }
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SearchError: Error, LocalizedError {
    case notConfigured(String)
    case apiError(String)
    case invalidQuery

    var errorDescription: String? {
        switch self {
        case .notConfigured(let m): return m
        case .apiError(let m):      return m
        case .invalidQuery:         return "Неверный поисковый запрос"
        }
    }
}
