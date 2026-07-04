import Foundation
import SwiftUI

/// Passive traffic analyzer. Wraps the system `tcpdump` in *quiet* mode to
/// observe camera-related flows on an interface you own and rolls them up into
/// per-flow summaries (endpoints, ports, protocol, packet/byte counts).
///
/// Design constraints that keep this defensive, not offensive:
///   • `-q` quiet output and a small snap length: we read headers, not payload.
///   • No payload is parsed, decoded, stored, or displayed.
///   • A BPF filter restricts capture to camera-ish ports by default.
///   • Requires elevated privileges (BPF access) — the same as Wireshark. If it
///     can't get them, it reports that instead of doing anything sneaky.
@MainActor
final class PacketAnalyzer: ObservableObject {

    @Published private(set) var flows: [TrafficFlow] = []
    @Published var isCapturing = false
    @Published var interfaceName = "en0"
    @Published var statusText = "Idle"
    @Published var authorized = false

    /// Default BPF filter: camera control/stream ports only.
    @Published var bpfFilter = "tcp port 554 or tcp port 8554 or tcp port 322 or tcp port 80 or tcp port 8000 or tcp port 37777"

    private var process: Process?
    private var flowMap: [String: TrafficFlow] = [:]

    func start() {
        guard authorized else {
            statusText = "Acknowledge the authorized-use notice before capturing."
            return
        }
        guard !isCapturing else { return }
        flowMap.removeAll()
        flows.removeAll()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        // -l line-buffered, -n no DNS, -q quiet (headers only), -tt epoch ts,
        // -s 96 tiny snap length (headers, not media payload), -K skip checksum.
        proc.arguments = [
            "-l", "-n", "-q", "-tt", "-s", "96",
            "-i", interfaceName,
            bpfFilter
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let raw = String(line)
                Task { @MainActor in self?.consume(line: raw) }
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.isCapturing = false
                if p.terminationStatus != 0 {
                    self?.statusText = "tcpdump exited (\(p.terminationStatus)). Needs sudo/BPF access?"
                    log(.warn, "PacketAnalyzer tcpdump exited \(p.terminationStatus)")
                } else {
                    self?.statusText = "Stopped"
                }
            }
        }

        do {
            try proc.run()
            process = proc
            isCapturing = true
            statusText = "Capturing on \(interfaceName)…"
            log(.info, "PacketAnalyzer capturing on \(interfaceName) filter=[\(bpfFilter)]")
        } catch {
            statusText = "Failed to launch tcpdump: \(error.localizedDescription)"
            log(.error, "PacketAnalyzer launch failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        isCapturing = false
        statusText = "Stopped. \(flows.count) flow(s) observed."
    }

    /// Parse one quiet-mode tcpdump line, e.g.:
    ///   1712345678.90 IP 192.168.1.5.554 > 192.168.1.10.51234: tcp 1428
    private func consume(line: String) {
        let tokens = line.split(separator: " ").map(String.init)
        guard let ipIdx = tokens.firstIndex(of: "IP") ?? tokens.firstIndex(of: "IP6"),
              tokens.count > ipIdx + 3 else { return }

        let srcToken = tokens[ipIdx + 1]                    // 192.168.1.5.554
        guard tokens[ipIdx + 2] == ">" else { return }
        var dstToken = tokens[ipIdx + 3]                    // 192.168.1.10.51234:
        if dstToken.hasSuffix(":") { dstToken.removeLast() }

        guard let (srcIP, srcPort) = Self.splitHostPort(srcToken),
              let (dstIP, dstPort) = Self.splitHostPort(dstToken) else { return }

        // Proto + length are near the end: "... tcp 1428"
        var proto = "tcp"
        var length = 0
        if let last = tokens.last, let n = Int(last) {
            length = n
            if tokens.count >= 2 { proto = tokens[tokens.count - 2] }
        }

        let key = "\(srcIP):\(srcPort)>\(dstIP):\(dstPort)"
        if var existing = flowMap[key] {
            existing.packetCount += 1
            existing.byteCount += length
            existing.lastSeen = Date()
            flowMap[key] = existing
        } else {
            flowMap[key] = TrafficFlow(id: key,
                                       sourceIP: srcIP, sourcePort: srcPort,
                                       destIP: dstIP, destPort: dstPort,
                                       proto: proto,
                                       packetCount: 1, byteCount: length,
                                       firstSeen: Date(), lastSeen: Date())
        }
        flows = flowMap.values.sorted { $0.byteCount > $1.byteCount }
    }

    /// Split tcpdump's "a.b.c.d.port" host.port notation.
    private static func splitHostPort(_ token: String) -> (String, Int)? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let port = Int(parts.last!) else { return nil }
        let host = parts.dropLast().joined(separator: ".")
        return (host, port)
    }
}
