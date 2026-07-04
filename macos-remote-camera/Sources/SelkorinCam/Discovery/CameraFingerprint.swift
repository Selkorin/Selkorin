import Foundation

/// Static knowledge about ports and banners commonly associated with IP
/// cameras and NVRs. Used to label discovery results. This is descriptive
/// metadata only — it helps you recognize what's on your network, not attack it.
enum CameraFingerprint {

    /// Ports worth probing when inventorying cameras on your own subnet.
    /// Kept short so a /24 sweep stays quick and light.
    static let commonPorts: [UInt16: String] = [
        80:    "HTTP (web UI)",
        443:   "HTTPS (web UI)",
        554:   "RTSP",
        322:   "RTSPS",
        1935:  "RTMP",
        8000:  "Hikvision SDK / HTTP",
        8080:  "HTTP alt",
        8554:  "RTSP alt",
        8899:  "ONVIF (some vendors)",
        9000:  "HTTP alt / NVR",
        34567: "Dahua/XM DVR (media)",
        37777: "Dahua SDK",
        37778: "Dahua SDK (UDP-adjacent)"
    ]

    /// Best-guess vendor from an open-port set or a text banner.
    static func vendorGuess(openPorts: [OpenPort]) -> String? {
        let ports = Set(openPorts.map { $0.port })
        if ports.contains(37777) || ports.contains(34567) { return "Dahua / XM-based DVR" }
        if ports.contains(8000) { return "Hikvision-style device" }

        for p in openPorts {
            guard let banner = p.banner?.lowercased() else { continue }
            if banner.contains("hikvision") { return "Hikvision" }
            if banner.contains("dahua") { return "Dahua" }
            if banner.contains("axis") { return "Axis" }
            if banner.contains("reolink") { return "Reolink" }
            if banner.contains("boa/") || banner.contains("gsoap") { return "Embedded camera (Boa/gSOAP)" }
            if banner.contains("server: dvrdvs") { return "Hikvision (DVRDVS)" }
        }
        return nil
    }

    /// Whether a given open-port set looks camera/NVR-ish enough to surface.
    static func looksLikeCamera(openPorts: [OpenPort]) -> Bool {
        let cameraSignals: Set<UInt16> = [554, 322, 8554, 8000, 8899, 34567, 37777]
        return openPorts.contains { cameraSignals.contains($0.port) }
    }
}
