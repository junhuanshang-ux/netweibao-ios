import Darwin
import Foundation

enum InterfaceType: String, Sendable, Equatable {
    case wifi
    case ethernet
    case cellular
    case vpn
    case bridge
    case peer
    case loopback
    case other

    var label: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .ethernet:
            return "以太网"
        case .cellular:
            return "蜂窝网络"
        case .vpn:
            return "VPN"
        case .bridge:
            return "热点 / 桥接"
        case .peer:
            return "点对点"
        case .loopback:
            return "回环"
        case .other:
            return "其他"
        }
    }

    var sortOrder: Int {
        switch self {
        case .wifi: return 0
        case .ethernet: return 1
        case .cellular: return 2
        case .vpn: return 3
        case .bridge: return 4
        case .peer: return 5
        case .other: return 6
        case .loopback: return 7
        }
    }
}

enum NetworkAddressFamily: String, Sendable, Equatable {
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
}

struct InterfaceAddress: Identifiable, Sendable {
    let id: String
    let family: NetworkAddressFamily
    let address: String
    let prefixLength: Int?
    let netmask: String?
}

struct NetworkInterfaceSnapshot: Identifiable, Sendable {
    let name: String
    let type: InterfaceType
    let isUp: Bool
    let isRunning: Bool
    let isLoopback: Bool
    let isPointToPoint: Bool
    let addresses: [InterfaceAddress]

    var id: String { name }

    var displayName: String {
        "\(type.label) · \(name)"
    }

    var ipv4Addresses: [InterfaceAddress] {
        addresses.filter { $0.family == .ipv4 }
    }

    var ipv6Addresses: [InterfaceAddress] {
        addresses.filter { $0.family == .ipv6 }
    }

    var primaryIPv4: String? {
        ipv4Addresses.first?.address
    }
}

enum NetworkInterfaceCatalog {
    static func snapshot() -> [NetworkInterfaceSnapshot] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }

        var builders: [String: Builder] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let name = String(cString: interface.pointee.ifa_name)
            let flags = interface.pointee.ifa_flags
            guard let addressPointer = interface.pointee.ifa_addr else { continue }

            var builder = builders[name] ?? Builder(name: name, flags: flags)
            builder.flags = flags

            let family = addressPointer.pointee.sa_family
            if family == UInt8(AF_INET) {
                if let parsed = ipv4Address(
                    addressPointer,
                    name: name,
                    interface: interface
                ) {
                    builder.addresses.append(parsed)
                }
            } else if family == UInt8(AF_INET6) {
                if let parsed = ipv6Address(addressPointer, name: name) {
                    builder.addresses.append(parsed)
                }
            }

            builders[name] = builder
        }

        return builders.values
            .map { builder in
                let type = interfaceType(for: builder.name)
                return NetworkInterfaceSnapshot(
                    name: builder.name,
                    type: type,
                    isUp: builder.flags & UInt32(IFF_UP) != 0,
                    isRunning: builder.flags & UInt32(IFF_RUNNING) != 0,
                    isLoopback: builder.flags & UInt32(IFF_LOOPBACK) != 0,
                    isPointToPoint: builder.flags & UInt32(IFF_POINTOPOINT) != 0,
                    addresses: builder.addresses.sorted {
                        if $0.family == $1.family {
                            return $0.address < $1.address
                        }
                        return $0.family == .ipv4
                    }
                )
            }
            .sorted {
                if $0.type.sortOrder == $1.type.sortOrder {
                    return $0.name < $1.name
                }
                return $0.type.sortOrder < $1.type.sortOrder
            }
    }

    static func interfaceType(for name: String) -> InterfaceType {
        if name == "lo0" { return .loopback }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") { return .vpn }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .peer }
        if name == "en0" { return .wifi }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }

    private struct Builder {
        let name: String
        var flags: UInt32
        var addresses: [InterfaceAddress] = []
    }

    private static func ipv4Address(
        _ pointer: UnsafeMutablePointer<sockaddr>,
        name: String,
        interface: UnsafeMutablePointer<ifaddrs>
    ) -> InterfaceAddress? {
        let address = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            IPv4Address(value: UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
        }

        var prefix: Int?
        var netmask: String?
        if let maskPointer = interface.pointee.ifa_netmask,
           maskPointer.pointee.sa_family == UInt8(AF_INET) {
            let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                IPv4Address(value: UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
            }
            prefix = NetworkInterface.prefixLength(for: mask)
            netmask = mask.description
        }

        return InterfaceAddress(
            id: "\(name)-ipv4-\(address.description)",
            family: .ipv4,
            address: address.description,
            prefixLength: prefix,
            netmask: netmask
        )
    }

    private static func ipv6Address(
        _ pointer: UnsafeMutablePointer<sockaddr>,
        name: String
    ) -> InterfaceAddress? {
        var raw = pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
            $0.pointee.sin6_addr
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))

        let converted: Bool = withUnsafePointer(to: &raw) { pointer in
            buffer.withUnsafeMutableBufferPointer { output in
                guard let base = output.baseAddress else { return false }
                return inet_ntop(
                    AF_INET6,
                    UnsafeRawPointer(pointer),
                    base,
                    socklen_t(output.count)
                ) != nil
            }
        }
        guard converted else { return nil }

        var address = buffer.withUnsafeBufferPointer { pointer -> String in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
        if address.hasPrefix("fe80") {
            address += "%\(name)"
        }

        return InterfaceAddress(
            id: "\(name)-ipv6-\(address)",
            family: .ipv6,
            address: address,
            prefixLength: nil,
            netmask: nil
        )
    }
}
