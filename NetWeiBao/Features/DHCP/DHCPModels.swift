import Foundation

struct DHCPOffer: Identifiable, Sendable {
    let id: UUID
    let serverIdentifier: IPv4Address?
    let sourceAddress: IPv4Address?
    let offeredAddress: IPv4Address?
    let subnetMask: IPv4Address?
    let routers: [IPv4Address]
    let dnsServers: [IPv4Address]
    let leaseTime: TimeInterval?
    let renewalTime: TimeInterval?
    let rebindingTime: TimeInterval?
    let domainName: String?
    let broadcastAddress: IPv4Address?
    let nextServer: IPv4Address?
    let serverName: String?
    let bootFileName: String?
    let vendorClass: String?
    let vendorSpecific: String?

    init(
        id: UUID = UUID(),
        serverIdentifier: IPv4Address?,
        sourceAddress: IPv4Address?,
        offeredAddress: IPv4Address?,
        subnetMask: IPv4Address?,
        routers: [IPv4Address],
        dnsServers: [IPv4Address],
        leaseTime: TimeInterval?,
        renewalTime: TimeInterval?,
        rebindingTime: TimeInterval?,
        domainName: String?,
        broadcastAddress: IPv4Address?,
        nextServer: IPv4Address?,
        serverName: String?,
        bootFileName: String?,
        vendorClass: String?,
        vendorSpecific: String?
    ) {
        self.id = id
        self.serverIdentifier = serverIdentifier
        self.sourceAddress = sourceAddress
        self.offeredAddress = offeredAddress
        self.subnetMask = subnetMask
        self.routers = routers
        self.dnsServers = dnsServers
        self.leaseTime = leaseTime
        self.renewalTime = renewalTime
        self.rebindingTime = rebindingTime
        self.domainName = domainName
        self.broadcastAddress = broadcastAddress
        self.nextServer = nextServer
        self.serverName = serverName
        self.bootFileName = bootFileName
        self.vendorClass = vendorClass
        self.vendorSpecific = vendorSpecific
    }
}

struct DHCPDiscoveryResult: Sendable {
    let offers: [DHCPOffer]
    let warnings: [String]
    let errorMessage: String?
    let interfaceName: String?
    let localAddress: String?
    let subnet: String?
    let broadcastTargets: [String]
    let boundPort: UInt16?
    let requestedAt: Date
    let duration: TimeInterval

    var boundClientPort: Bool {
        boundPort == 68
    }
}

enum DHCPFormatter {
    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "—" }

        if interval < 60 {
            return "\(Int(interval)) 秒"
        }
        if interval < 3_600 {
            return "\(Int(interval / 60)) 分钟"
        }
        if interval < 86_400 {
            let hours = Int(interval / 3_600)
            let minutes = Int(interval.truncatingRemainder(dividingBy: 3_600) / 60)
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }

        let days = Int(interval / 86_400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3_600)
        return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
    }

    static func addresses(_ addresses: [IPv4Address]) -> String {
        addresses.isEmpty ? "—" : addresses.map(\.description).joined(separator: ", ")
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1_000)) ms"
        }
        return String(format: "%.1f s", interval)
    }
}
