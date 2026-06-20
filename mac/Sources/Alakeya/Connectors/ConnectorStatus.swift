import Foundation

enum ConnectorStatus: String, Codable {
    case disconnected = "disconnected"
    case connected    = "connected"
    case needsAuth    = "needs_auth"
    case error        = "error"
    case disabled     = "disabled"

    var title: String {
        switch self {
        case .disconnected: return "Не подключён"
        case .connected:    return "Подключён"
        case .needsAuth:    return "Требуется авторизация"
        case .error:        return "Ошибка"
        case .disabled:     return "Отключён"
        }
    }

    var isReady: Bool { self == .connected }
}

struct ConnectorConnectionState: Codable, Identifiable {
    var id: String { connectorID }
    var connectorID: String
    var status: ConnectorStatus
    var connectedEmail: String?
    var errorMessage: String?
    var lastConnected: Date?
}
