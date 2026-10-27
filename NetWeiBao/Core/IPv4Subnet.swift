import Foundation

struct IPv4Subnet: Hashable, CustomStringConvertible, Sendable {
    let network: IPv4Address
    let prefixLength: Int

    init(address: IPv4Address, prefixLength: Int) {
        let clamped = min(32, max(0, prefixLength))
        self.prefixLength = clamped
        self.network = IPv4Address(value: address.value & Self.mask(for: clamped))
    }

    init?(cidr: String) {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)

        guard parts.count == 2,
              let address = IPv4Address(String(parts[0])),
              let prefix = Int(parts[1]),
              (0...32).contains(prefix)
        else {
            return nil
        }

        self.init(address: address, prefixLength: prefix)
    }

    static func mask(for prefixLength: Int) -> UInt32 {
        let clamped = min(32, max(0, prefixLength))
        guard clamped > 0 else { return 0 }
        guard clamped < 32 else { return .max }
        return UInt32.max << UInt32(32 - clamped)
    }

    var netmask: IPv4Address {
        IPv4Address(value: Self.mask(for: prefixLength))
    }

    var broadcast: IPv4Address {
        IPv4Address(value: network.value | ~Self.mask(for: prefixLength))
    }

    var firstHost: IPv4Address {
        prefixLength >= 31 ? network : network.adding(1)
    }

    var lastHost: IPv4Address {
        prefixLength >= 31 ? broadcast : IPv4Address(value: broadcast.value &- 1)
    }

    var totalAddressCount: UInt64 {
        UInt64(1) << UInt64(32 - prefixLength)
    }

    var usableHostCount: UInt64 {
        switch prefixLength {
        case 32:
            return 1
        case 31:
            return 2
        default:
            return totalAddressCount - 2
        }
    }

    var cidr: String {
        "\(network)/\(prefixLength)"
    }

    var description: String {
        cidr
    }

    func contains(_ address: IPv4Address) -> Bool {
        address.value & Self.mask(for: prefixLength) == network.value
    }

    /// Returns usable host addresses in ascending order.
    /// `limit` protects the UI from accidentally scanning a /8.
    func hostAddresses(limit: Int = 4096) -> [IPv4Address] {
        guard limit > 0, usableHostCount > 0 else { return [] }

        let start = UInt64(firstHost.value)
        let end = UInt64(lastHost.value)
        var current = start
        var result: [IPv4Address] = []
        result.reserveCapacity(min(limit, Int(usableHostCount)))

        while current <= end, result.count < limit {
            result.append(IPv4Address(value: UInt32(current)))
            current += 1
        }

        return result
    }
}
