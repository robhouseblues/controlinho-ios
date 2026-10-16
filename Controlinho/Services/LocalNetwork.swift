import Foundation
import Network

enum LocalNetwork {
    /// The device's IPv4 address on Wi-Fi (or the first private address it can find).
    static func currentIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = pointer.pointee
            guard let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buffer)
            guard isPrivateIPv4(ip) else { continue }
            if String(cString: iface.ifa_name) == "en0" { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }

    static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

/// Sends a Wake-on-LAN magic packet so a TV in standby can be switched on.
/// Requires "Power On with Mobile" (or similar) to be enabled on the TV.
enum WakeOnLAN {
    static func wake(mac: String, host: String) {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }

        let subnetBroadcast = host.split(separator: ".").prefix(3).joined(separator: ".") + ".255"
        for target in [host, subnetBroadcast] {
            for port: NWEndpoint.Port in [9, 7] {
                let connection = NWConnection(host: NWEndpoint.Host(target), port: port, using: .udp)
                connection.start(queue: .global())
                connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
