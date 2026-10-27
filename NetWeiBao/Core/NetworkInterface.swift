import Darwin
import Foundation
import SystemConfiguration

enum NetworkInterface {
    struct Info: Identifiable, Sendable {
        let name: String
        let address: IPv4Address
        let netmask: IPv4Address
        let prefixLength: Int

        var id: String { "\(name)-\(address.value)" }

        var subnet: IPv4Subnet {
            IPv4Subnet(address: address, prefixLength: prefixLength)
        }
    }

    /// Returns the most useful active IPv4 interface, preferring Wi-Fi (`en0`).
    static func activeIPv4() -> Info? {
        allIPv4().first
    }

    static func allIPv4() -> [Info] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }

        var candidates: [(score: Int, info: Info)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = interface.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0,
                  let addressPointer = interface.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let name = String(cString: interface.pointee.ifa_name)
            guard let address = ipv4(from: addressPointer) else { continue }

            var netmask = IPv4Address(value: 0xFFFF_FF00)
            if let maskPointer = interface.pointee.ifa_netmask,
               maskPointer.pointee.sa_family == UInt8(AF_INET),
               let parsedMask = ipv4(from: maskPointer) {
                netmask = parsedMask
            }

            let prefix = prefixLength(for: netmask)
            let info = Info(
                name: name,
                address: address,
                netmask: netmask,
                prefixLength: prefix
            )

            var score = 5
            if name == "en0" {
                score = 0
            } else if name.hasPrefix("en") {
                score = 1
            } else if name.hasPrefix("bridge") {
                score = 2
            } else if name.hasPrefix("pdp_ip") {
                score = 7
            } else if name.hasPrefix("utun") {
                score = 8
            }
            if address.isLinkLocal { score += 20 }

            candidates.append((score, info))
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.info.address < rhs.info.address
                }
                return lhs.score < rhs.score
            }
            .map(\.info)
    }

    /// Best-effort default gateway lookup from the system network state.
    /// Falls back to `nil` when the sandbox or the current network does not expose it.
    static func defaultGateway() -> IPv4Address? {
        let store = SCDynamicStoreCreate(
            nil,
            "NetWeiBao" as CFString,
            nil,
            nil
        )
        guard let store,
              let value = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/IPv4" as CFString
              ),
              let dictionary = value as? [String: Any],
              let router = dictionary["Router"] as? String,
              let address = IPv4Address(router)
        else {
            return nil
        }
        return address
    }

    static func prefixLength(for mask: IPv4Address) -> Int {
        guard mask.value != 0 else { return 0 }
        let inverted = ~mask.value
        guard inverted & (inverted &+ 1) == 0 else { return 24 }
        return mask.value.nonzeroBitCount
    }

    private static func ipv4(from pointer: UnsafeMutablePointer<sockaddr>) -> IPv4Address? {
        guard pointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
        return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { rebound in
            IPv4Address(value: UInt32(bigEndian: rebound.pointee.sin_addr.s_addr))
        }
    }
}
