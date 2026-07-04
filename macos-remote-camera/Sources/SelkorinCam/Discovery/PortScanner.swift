import Foundation
import Network

/// A polite, bounded TCP connect-scan of the local subnet for camera-ish ports.
///
/// "Connect scan" means it completes a normal TCP handshake (like any client
/// would) and immediately closes — no raw packets, no half-open/SYN tricks.
/// Concurrency and per-host port list are deliberately small so a sweep of a
/// /24 is quick and does not hammer the network. Scope is the local /24 only.
final class PortScanner {

    struct HostResult {
        let ip: String
        let openPorts: [OpenPort]
    }

    private let ports: [UInt16]
    private let connectTimeout: TimeInterval
    private let maxConcurrent: Int

    init(ports: [UInt16] = Array(CameraFingerprint.commonPorts.keys),
         connectTimeout: TimeInterval = 1.0,
         maxConcurrent: Int = 64) {
        self.ports = ports.sorted()
        self.connectTimeout = connectTimeout
        self.maxConcurrent = maxConcurrent
    }

    /// Scan every host in `hosts`, calling `onHost` as each host that has at
    /// least one open camera-ish port is found.
    func scan(hosts: [String], onHost: @escaping (HostResult) -> Void) async {
        await withTaskGroup(of: HostResult?.self) { group in
            var iterator = hosts.makeIterator()

            func launchNext() {
                guard let host = iterator.next() else { return }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let open = await self.scanHost(host)
                    return open.isEmpty ? nil : HostResult(ip: host, openPorts: open)
                }
            }

            for _ in 0..<min(maxConcurrent, hosts.count) { launchNext() }

            while let finished = await group.next() {
                if let finished { onHost(finished) }
                launchNext()
            }
        }
    }

    private func scanHost(_ host: String) async -> [OpenPort] {
        var open: [OpenPort] = []
        for port in ports {
            if let result = await probe(host: host, port: port) {
                open.append(result)
            }
        }
        return open
    }

    /// Try to open a TCP connection to host:port. If it connects, grab a short
    /// banner if the service offers one (metadata only), then close.
    private func probe(host: String, port: UInt16) async -> OpenPort? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        // Several callbacks (connect timeout, banner-read timeout, receive
        // completion, connection failure) may race to finish this probe from
        // different queues. Serialize the "resume exactly once" decision on a
        // dedicated queue so the continuation can never be resumed twice.
        let syncQueue = DispatchQueue(label: "com.selkorin.portscan.probe")
        return await withCheckedContinuation { (continuation: CheckedContinuation<OpenPort?, Never>) in
            var resumed = false
            let finish: (OpenPort?) -> Void = { value in
                syncQueue.async {
                    if resumed { return }
                    resumed = true
                    conn.cancel()
                    continuation.resume(returning: value)
                }
            }

            let timeoutTask = DispatchWorkItem { finish(nil) }
            DispatchQueue.global().asyncAfter(deadline: .now() + connectTimeout, execute: timeoutTask)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // A completed handshake is the signal we care about: the port
                    // is open. Try a brief banner read, but many services (e.g.
                    // RTSP) stay silent until the client speaks, so don't block on
                    // them — fall back to "open, no banner" after a short window.
                    timeoutTask.cancel()
                    let label = CameraFingerprint.commonPorts[port] ?? "open"
                    let bannerFallback = DispatchWorkItem {
                        finish(OpenPort(port: port, service: label, banner: nil))
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: bannerFallback)
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                        bannerFallback.cancel()
                        var banner: String?
                        if let data, !data.isEmpty {
                            banner = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        finish(OpenPort(port: port, service: label, banner: banner))
                    }
                case .failed, .cancelled:
                    timeoutTask.cancel()
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }
    }
}
