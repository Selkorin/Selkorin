import Foundation
import SwiftUI

/// Runs the discovery backends (ONVIF, Bonjour, port probe) against the local
/// subnet and merges their findings into a single de-duplicated list keyed by
/// IP address. This is the view model for the Discovery tab.
@MainActor
final class DiscoveryCoordinator: ObservableObject {

    @Published private(set) var cameras: [DiscoveredCamera] = []
    @Published var isScanning = false
    @Published var subnetCIDR: String = LocalNetwork.primarySubnetCIDR() ?? "192.168.1.0/24"
    @Published var progressText = ""
    /// Set to true only after the user acknowledges the authorized-use notice.
    @Published var authorized = false

    private var onvif: OnvifDiscovery?
    private var bonjour: BonjourBrowser?
    private var byIP: [String: DiscoveredCamera] = [:]

    func startScan() {
        guard authorized else {
            progressText = "Acknowledge the authorized-use notice before scanning."
            return
        }
        guard !isScanning else { return }
        isScanning = true
        byIP.removeAll()
        cameras.removeAll()
        progressText = "Scanning \(subnetCIDR)…"
        log(.info, "Discovery started on \(subnetCIDR)")

        startOnvif()
        startBonjour()
        startPortScan()
    }

    func stopScan() {
        onvif?.stop(); onvif = nil
        bonjour?.stop(); bonjour = nil
        isScanning = false
        progressText = "Stopped. \(cameras.count) device(s) found."
    }

    // MARK: - Backends

    private func startOnvif() {
        let onvif = OnvifDiscovery()
        onvif.onMatch = { [weak self] match in
            Task { @MainActor in
                self?.merge(ip: match.ip,
                            source: .onvif,
                            serviceURLs: match.xAddrs,
                            vendor: Self.vendorFromScopes(match.scopes))
            }
        }
        onvif.start()
        self.onvif = onvif
    }

    private func startBonjour() {
        let bonjour = BonjourBrowser()
        bonjour.onResolved = { [weak self] ip, name, type, port in
            Task { @MainActor in
                let url = type.contains("rtsp") ? "rtsp://\(ip):\(port)/" : "http://\(ip):\(port)/"
                self?.merge(ip: ip, source: .bonjour, hostname: name, serviceURLs: [url])
            }
        }
        bonjour.start()
        self.bonjour = bonjour
    }

    private func startPortScan() {
        let hosts = LocalNetwork.hostsIn(cidr: subnetCIDR)
        guard !hosts.isEmpty else {
            progressText = "Only /24 subnets are supported for scanning."
            isScanning = false
            return
        }
        Task.detached { [weak self] in
            let scanner = PortScanner()
            await scanner.scan(hosts: hosts) { result in
                // Record every responding host; camera-likeness only affects
                // ranking (see merge's sort), so HTTP-only hosts still show up.
                let vendor = CameraFingerprint.vendorGuess(openPorts: result.openPorts)
                Task { @MainActor in
                    self?.merge(ip: result.ip, source: .portScan,
                                openPorts: result.openPorts, vendor: vendor)
                }
            }
            await MainActor.run {
                self?.isScanning = false
                self?.progressText = "Scan complete. \(self?.cameras.count ?? 0) device(s) found."
                log(.info, "Discovery complete: \(self?.cameras.count ?? 0) devices")
            }
        }
    }

    // MARK: - Merge

    private func merge(ip: String,
                       source: DiscoveredCamera.Source,
                       hostname: String? = nil,
                       openPorts: [OpenPort] = [],
                       serviceURLs: [String] = [],
                       vendor: String? = nil) {
        var entry = byIP[ip] ?? DiscoveredCamera(ipAddress: ip,
                                                 hostname: nil,
                                                 openPorts: [],
                                                 source: source,
                                                 vendorGuess: nil,
                                                 serviceURLs: [],
                                                 lastSeen: Date())
        if let hostname, entry.hostname == nil { entry.hostname = hostname }
        if let vendor, entry.vendorGuess == nil { entry.vendorGuess = vendor }

        // Merge ports (unique by port number).
        var portMap = Dictionary(uniqueKeysWithValues: entry.openPorts.map { ($0.port, $0) })
        for p in openPorts { portMap[p.port] = p }
        entry.openPorts = portMap.values.sorted { $0.port < $1.port }

        // Merge service URLs.
        var urls = Set(entry.serviceURLs)
        serviceURLs.forEach { urls.insert($0) }
        entry.serviceURLs = urls.sorted()

        entry.lastSeen = Date()
        byIP[ip] = entry

        cameras = byIP.values.sorted { lhs, rhs in
            let l = CameraFingerprint.looksLikeCamera(openPorts: lhs.openPorts) ? 0 : 1
            let r = CameraFingerprint.looksLikeCamera(openPorts: rhs.openPorts) ? 0 : 1
            if l != r { return l < r }
            return lhs.ipAddress.compare(rhs.ipAddress, options: .numeric) == .orderedAscending
        }
    }

    private static func vendorFromScopes(_ scopes: [String]) -> String? {
        for scope in scopes {
            if let range = scope.range(of: "onvif://www.onvif.org/name/") {
                return String(scope[range.upperBound...]).removingPercentEncoding
            }
            if let range = scope.range(of: "onvif://www.onvif.org/hardware/") {
                return String(scope[range.upperBound...]).removingPercentEncoding
            }
        }
        return nil
    }
}
