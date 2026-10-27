import Foundation

enum TracerouteHopStatus: Sendable, Equatable {
    case hop
    case target
    case timeout
    case unreachable
}

struct TracerouteHop: Identifiable, Sendable {
    let ttl: Int
    let address: IPv4Address?
    let latency: Double?
    let status: TracerouteHopStatus

    var id: Int { ttl }
}
