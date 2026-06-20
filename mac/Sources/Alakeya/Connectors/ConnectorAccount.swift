import Foundation

struct ConnectorAccount: Identifiable, Codable {
    let id: String
    var connectorID: String
    var displayName: String
    var email: String?
    var avatarURL: String?
    var isDefault: Bool
    var createdAt: Date

    init(connectorID: String, displayName: String, email: String? = nil) {
        self.id          = UUID().uuidString
        self.connectorID = connectorID
        self.displayName = displayName
        self.email       = email
        self.isDefault   = true
        self.createdAt   = Date()
    }
}
