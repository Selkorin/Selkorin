import Foundation

// ============================================================
// Connector.swift — core model types for the Connectors system.
// All real API calls are TODO stubs; this file defines structure.
// ============================================================

struct Connector: Identifiable {
    let id: String
    let title: String
    let description: String
    let category: ConnectorCategory
    let iconName: String          // SF Symbol name
    let authType: ConnectorAuthType
    let permissions: [ConnectorPermission]
    let availableTools: [String]
    var isEnabled: Bool
}

enum ConnectorCategory: String, CaseIterable {
    case google      = "google"
    case social      = "social"
    case files       = "files"
    case spreadsheets = "spreadsheets"
    case calendar    = "calendar"
    case crm         = "crm"
    case custom      = "custom"

    var title: String {
        switch self {
        case .google:       return "Google"
        case .social:       return "Социальные сети"
        case .files:        return "Файлы"
        case .spreadsheets: return "Таблицы"
        case .calendar:     return "Календарь"
        case .crm:          return "CRM"
        case .custom:       return "Кастомные"
        }
    }

    var iconName: String {
        switch self {
        case .google:       return "g.circle.fill"
        case .social:       return "bubble.left.and.bubble.right.fill"
        case .files:        return "folder.fill"
        case .spreadsheets: return "tablecells.fill"
        case .calendar:     return "calendar"
        case .crm:          return "person.3.fill"
        case .custom:       return "link"
        }
    }
}

enum ConnectorAuthType: String {
    case oauth2 = "oauth2"
    case apiKey = "api_key"
    case none   = "none"

    var title: String {
        switch self {
        case .oauth2:  return "OAuth 2.0"
        case .apiKey:  return "API Key"
        case .none:    return "Без авторизации"
        }
    }
}
