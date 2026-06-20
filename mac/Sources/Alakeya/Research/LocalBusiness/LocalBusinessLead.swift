import Foundation

// ============================================================
// LocalBusinessLead.swift — single validated business contact.
// ============================================================

enum WebsiteStatus: String, Codable {
    case hasWebsite   = "Да"
    case noWebsite    = "Нет"
    case socialOnly   = "Только соцсеть"
    case unknown      = "Не проверено"

    var passesFreeFilter: Bool {
        // For "без сайта" filter: accept noWebsite, socialOnly, unknown
        switch self {
        case .hasWebsite: return false
        default:          return true
        }
    }
}

struct LocalBusinessLead: Identifiable {
    let id: UUID
    var name: String
    var category: String
    var city: String
    var address: String
    var phone: String          // empty if not found or masked
    var website: String        // raw domain or empty
    var websiteStatus: WebsiteStatus
    var sourceName: String
    var sourceURL: String
    var notes: String          // "Телефон скрыт", "Данные из поиска" etc.
    var confidence: Double     // 0..1

    init(name: String = "", category: String = "", city: String = "",
         address: String = "", phone: String = "", website: String = "",
         websiteStatus: WebsiteStatus = .unknown,
         sourceName: String = "", sourceURL: String = "",
         notes: String = "", confidence: Double = 0.5) {
        self.id            = UUID()
        self.name          = name
        self.category      = category
        self.city          = city
        self.address       = address
        self.phone         = phone
        self.website       = website
        self.websiteStatus = websiteStatus
        self.sourceName    = sourceName
        self.sourceURL     = sourceURL
        self.notes         = notes
        self.confidence    = confidence
    }

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Convert leads array to ParsedMarkdownTable for chat storage and export.
    static func toTable(_ leads: [LocalBusinessLead], noWebsiteFilter: Bool) -> ParsedMarkdownTable {
        var headers = ["Название", "Адрес", "Телефон", "Сайт", "Источник"]
        if noWebsiteFilter { headers.insert("Есть сайт", at: 3) }

        let rows: [[String]] = leads.map { lead in
            var row = [
                lead.name.isEmpty ? "—" : lead.name,
                lead.address.isEmpty ? "—" : lead.address,
                lead.phone.isEmpty ? (lead.notes.contains("скрыт") ? "⚠ Скрыт" : "—") : lead.phone,
            ]
            if noWebsiteFilter { row.append(lead.websiteStatus.rawValue) }
            row.append(lead.website.isEmpty ? "—" : lead.website)
            row.append(lead.sourceName.isEmpty ? "—" : lead.sourceName)
            return row
        }

        return ParsedMarkdownTable(headers: headers, rows: rows)
    }
}
