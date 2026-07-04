import Foundation

/// ONVIF WS-Discovery: sends a standard multicast SOAP "Probe" to
/// 239.255.255.250:3702 and collects "ProbeMatch" replies. Conformant IP
/// cameras answer with their service URLs (XAddrs) and scopes (which often
/// include the model/name). This is exactly how ONVIF Device Manager and
/// vendor tools locate cameras on a LAN.
///
/// Implemented with a POSIX UDP socket rather than a connected `NWConnection`,
/// because ProbeMatch replies come back as *unicast* from each camera's own
/// address — a connected socket bound to the multicast group would filter those
/// out. An unconnected datagram socket with `recvfrom` receives them correctly.
final class OnvifDiscovery {

    struct Match {
        let ip: String
        let xAddrs: [String]
        let scopes: [String]
    }

    var onMatch: ((Match) -> Void)?

    private var running = false
    private let queue = DispatchQueue(label: "com.selkorin.onvif")
    private let listenSeconds: TimeInterval = 6

    func start() {
        guard !running else { return }
        running = true
        queue.async { [weak self] in self?.run() }
    }

    func stop() {
        running = false
    }

    private func run() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { log(.error, "ONVIF socket() failed"); return }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind an ephemeral local port on all interfaces so replies reach us.
        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = 0            // INADDR_ANY
        local.sin_port = 0
        let bindOK = withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else { log(.error, "ONVIF bind() failed"); return }

        // Don't let recvfrom block indefinitely; poll in ~1s slices.
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(3702).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

        let probe = Self.probeMessage()
        let probeBytes = Array(probe.utf8)
        let sent = probeBytes.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &dest) { dptr in
                dptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, raw.count, 0,
                           $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            log(.warn, "ONVIF sendto failed (errno \(errno))")
        } else {
            log(.info, "ONVIF WS-Discovery probe sent to 239.255.255.250:3702")
        }

        let deadline = Date().addingTimeInterval(listenSeconds)
        var buf = [UInt8](repeating: 0, count: 65536)
        while running && Date() < deadline {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { fptr in
                fptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saddr in
                    recvfrom(fd, &buf, buf.count, 0, saddr, &fromLen)
                }
            }
            if n > 0, let text = String(bytes: buf.prefix(n), encoding: .utf8) {
                parse(text)
            }
            // n <= 0 means timeout/error; the loop re-checks running & deadline.
        }
    }

    private func parse(_ xml: String) {
        let xAddrs = Self.values(in: xml, tagLocalName: "XAddrs")
            .flatMap { $0.split(separator: " ").map(String.init) }
        let scopes = Self.values(in: xml, tagLocalName: "Scopes")
            .flatMap { $0.split(separator: " ").map(String.init) }

        var ip = ""
        if let first = xAddrs.first, let url = URL(string: first), let host = url.host {
            ip = host
        }
        guard !ip.isEmpty else { return }
        onMatch?(Match(ip: ip, xAddrs: xAddrs, scopes: scopes))
    }

    private static func probeMessage() -> String {
        let messageID = "urn:uuid:\(UUID().uuidString.lowercased())"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
                    xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
                    xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
                    xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
          <e:Header>
            <w:MessageID>\(messageID)</w:MessageID>
            <w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
            <w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
          </e:Header>
          <e:Body>
            <d:Probe>
              <d:Types>dn:NetworkVideoTransmitter</d:Types>
            </d:Probe>
          </e:Body>
        </e:Envelope>
        """
    }

    /// Small XML value extractor that ignores namespace prefixes, e.g. finds the
    /// contents of both <XAddrs> and <d:XAddrs>.
    private static func values(in xml: String, tagLocalName: String) -> [String] {
        var results: [String] = []
        let pattern = "<(?:[A-Za-z0-9]+:)?\(tagLocalName)[^>]*>(.*?)</(?:[A-Za-z0-9]+:)?\(tagLocalName)>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return results
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            if let match, match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: xml) {
                results.append(String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return results
    }
}
