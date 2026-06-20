import Foundation

enum LocalBusinessSearchSource: String, CaseIterable {
    case yandexMaps    = "Яндекс Карты"
    case yandexSearch  = "Яндекс Поиск"
    case twoGis        = "2ГИС"
    case googleSearch  = "Google Поиск"
    // Avito is intentionally excluded — not a business directory

    var displayName: String { rawValue }

    /// Builds a search URL for the given category and city.
    func url(category: String, city: String) -> URL? {
        let encCat  = (category + " " + city).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encCat2 = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        _ = city  // city encoded into encCat

        switch self {
        case .yandexMaps:
            return URL(string: "https://yandex.ru/maps/?text=\(encCat)")
        case .yandexSearch:
            let q = (category + " " + city + " телефон адрес")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "https://yandex.ru/search/?text=\(q)&numdoc=50")
        case .twoGis:
            let citySlug = city.lowercased()
                .replacingOccurrences(of: "ё", with: "yo")
                .replacingOccurrences(of: " ", with: "_")
            return URL(string: "https://2gis.ru/\(citySlug)/search/\(encCat2)")
        case .googleSearch:
            let q = (category + " " + city + " контакты телефон")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "https://www.google.com/search?q=\(q)&num=20")
        }
    }
}
