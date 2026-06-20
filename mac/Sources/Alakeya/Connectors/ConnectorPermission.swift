import Foundation

enum PermissionRisk: String, Codable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var title: String {
        switch self {
        case .low:    return "Низкий"
        case .medium: return "Средний"
        case .high:   return "Высокий"
        }
    }
}

struct ConnectorPermission: Identifiable {
    let id: String
    let title: String
    let description: String
    let oauthScope: String     // e.g. "https://www.googleapis.com/auth/gmail.readonly"
    let risk: PermissionRisk
    let isRequired: Bool
}
