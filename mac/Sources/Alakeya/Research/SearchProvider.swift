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
        BrowserSearchProvider(),
    ]

    var available: [SearchProvider] { providers.filter { $0.isAvailable } }

    func primaryProvider() -> SearchProvider {
        // Prefer Google Custom Search if configured, else browser fallback
        if let google = providers.first(where: { $0.name == "GoogleCustomSearch" && $0.isAvailable }) {
            return google
        }
        return providers.first(where: { $0.name == "BrowserSearch" }) ?? BrowserSearchProvider()
    }
}

// MARK: - Browser search provider

struct BrowserSearchProvider: SearchProvider {
    let name = "BrowserSearch"
    var isAvailable: Bool { true }

    func search(query: String) async throws -> [SearchResult] {
        // Opens query in browser. The AI then calls extract_search_results to parse results.
        // This provider signals intent; actual extraction done via AlakeyaBrowser tools.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://yandex.ru/search/?text=\(encoded)"
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
