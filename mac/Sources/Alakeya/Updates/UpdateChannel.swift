import Foundation

enum UpdateChannel: String, Codable, CaseIterable {
    case stable = "stable"
    case beta   = "beta"

    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .beta:   return "Beta"
        }
    }

    var feedURL: String {
        // TODO: Replace with your real update server URL
        switch self {
        case .stable: return "https://updates.selkorin.com/alakeya/appcast.json"
        case .beta:   return "https://updates.selkorin.com/alakeya/appcast-beta.json"
        }
    }
}
