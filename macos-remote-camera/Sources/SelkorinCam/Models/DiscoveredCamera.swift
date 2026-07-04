import Foundation

/// A camera-like device found on the local network by one of the discovery
/// backends (ONVIF WS-Discovery, Bonjour/mDNS, or a TCP port probe).
struct DiscoveredCamera: Identifiable, Hashable {
    enum Source: String {
        case onvif = "ONVIF"
        case bonjour = "Bonjour/mDNS"
        case portScan = "Port probe"
    }

    let id = UUID()
    var ipAddress: String
    var hostname: String?
    /// Ports that responded, with a best-guess service label.
    var openPorts: [OpenPort]
    /// How this device was first seen.
    var source: Source
    /// Vendor / model guess, if we could infer one from a banner or ONVIF scope.
    var vendorGuess: String?
    /// RTSP / ONVIF service URLs advertised by the device, if any.
    var serviceURLs: [String]
    var lastSeen: Date

    var displayName: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let vendorGuess, !vendorGuess.isEmpty { return "\(vendorGuess) @ \(ipAddress)" }
        return ipAddress
    }

    static func == (lhs: DiscoveredCamera, rhs: DiscoveredCamera) -> Bool {
        lhs.ipAddress == rhs.ipAddress
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
    }
}

struct OpenPort: Hashable {
    let port: UInt16
    /// Human label, e.g. "RTSP", "HTTP", "Dahua", "Hikvision SDK".
    let service: String
    /// First bytes of a text banner, if the service returned one. Metadata only.
    var banner: String?
}
