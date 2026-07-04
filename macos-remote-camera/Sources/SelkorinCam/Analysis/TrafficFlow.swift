import Foundation

/// A summarized network flow between two endpoints. This is metadata only —
/// addresses, ports, protocol, packet/byte counts. Payloads are never decoded
/// or stored, so the analyzer cannot and does not extract credentials or media.
struct TrafficFlow: Identifiable {
    let id: String          // "src:sport>dst:dport"
    let sourceIP: String
    let sourcePort: Int
    let destIP: String
    let destPort: Int
    let proto: String       // tcp / udp
    var packetCount: Int
    var byteCount: Int
    var firstSeen: Date
    var lastSeen: Date

    /// Best-guess application protocol from the well-known port involved.
    var appProtocol: String {
        let ports = [sourcePort, destPort]
        if ports.contains(554) || ports.contains(8554) { return "RTSP" }
        if ports.contains(322) { return "RTSPS" }
        if ports.contains(80) || ports.contains(8080) || ports.contains(8000) { return "HTTP" }
        if ports.contains(443) { return "HTTPS" }
        if ports.contains(37777) || ports.contains(34567) { return "Vendor SDK" }
        if proto == "udp" { return "RTP/RTCP?" }
        return proto.uppercased()
    }
}
