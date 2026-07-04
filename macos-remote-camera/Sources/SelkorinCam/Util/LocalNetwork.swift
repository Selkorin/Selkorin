import Foundation

/// Helpers for figuring out the Mac's own IPv4 addresses and enumerating the
/// hosts on the local /24 it is attached to. Discovery is deliberately scoped
/// to the subnet the machine is already on — the tool is for auditing your own
/// network, not for reaching arbitrary ranges.
enum LocalNetwork {

    /// Non-loopback IPv4 addresses of active interfaces (en0, en1, ...).
    static func interfaceIPv4Addresses() -> [String] {
        var results: [String] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return results }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                                 &host, socklen_t(host.count),
                                 nil, 0, NI_NUMERICHOST)
            if ok == 0 {
                let addr = String(cString: host)
                if !addr.hasPrefix("169.254") { results.append(addr) }
            }
        }
        return results
    }

    /// The /24 CIDR the primary interface sits on, e.g. "192.168.1.0/24".
    static func primarySubnetCIDR() -> String? {
        guard let ip = interfaceIPv4Addresses().first else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    /// Expand a "a.b.c.0/24" CIDR into host addresses .1 ... .254.
    /// Only /24 is supported on purpose — it keeps scan scope small and local.
    static func hostsIn(cidr: String) -> [String] {
        let comps = cidr.split(separator: "/")
        guard comps.count == 2, comps[1] == "24" else { return [] }
        let octets = comps[0].split(separator: ".")
        guard octets.count == 4 else { return [] }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])."
        return (1...254).map { "\(prefix)\($0)" }
    }
}
