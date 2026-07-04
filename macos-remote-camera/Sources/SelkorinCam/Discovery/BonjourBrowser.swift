import Foundation

/// Browses the local network for camera-related Bonjour/mDNS service types and
/// resolves each to an IPv4 address. Many cameras and NVRs advertise `_rtsp`,
/// `_onvif`, or a web UI over `_http`.
final class BonjourBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    /// Called on the main thread when a service resolves to an address.
    var onResolved: ((_ ip: String, _ name: String, _ serviceType: String, _ port: Int) -> Void)?

    private let serviceTypes = [
        "_rtsp._tcp.",
        "_onvif._tcp.",
        "_http._tcp.",
        "_axis-video._tcp.",
        "_dahua._tcp."
    ]

    private var browsers: [NetServiceBrowser] = []
    // Hold strong references while services resolve.
    private var resolving: Set<NetService> = []

    func start() {
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
        log(.info, "Bonjour discovery started (\(serviceTypes.count) service types)")
    }

    func stop() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        resolving.removeAll()
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.insert(service)
        service.resolve(withTimeout: 5.0)
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { resolving.remove(sender) }
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            if let ip = Self.ipv4String(from: data) {
                onResolved?(ip, sender.name, sender.type, sender.port)
                break
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.remove(sender)
    }

    /// Extract a dotted-quad IPv4 string from a sockaddr blob, ignoring IPv6.
    private static func ipv4String(from data: Data) -> String? {
        return data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self)
            guard sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
            var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
    }
}
