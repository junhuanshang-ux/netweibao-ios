import Foundation

enum PingOutcome: Sendable {
    case reply(latencyMs: Double, ttl: Int?)
    case timeout
    case unreachable(String)
    case failure(String)

    var isSuccess: Bool {
        if case .reply = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .unreachable(let message), .failure(let message):
            return message
        case .reply, .timeout:
            return nil
        }
    }
}

struct PingReply: Identifiable, Sendable {
    let id: UUID
    let sequence: Int
    let outcome: PingOutcome
    let timestamp: Date

    init(sequence: Int, outcome: PingOutcome, timestamp: Date = Date()) {
        self.id = UUID()
        self.sequence = sequence
        self.outcome = outcome
        self.timestamp = timestamp
    }

    var latencyMs: Double? {
        if case .reply(let latency, _) = outcome { return latency }
        return nil
    }

    var statusText: String {
        switch outcome {
        case .reply:
            return "成功"
        case .timeout:
            return "超时"
        case .unreachable:
            return "不可达"
        case .failure:
            return "失败"
        }
    }
}

struct PingStatistics: Sendable {
    var sent: Int = 0
    var received: Int = 0
    var minLatency: Double? = nil
    var averageLatency: Double? = nil
    var maxLatency: Double? = nil
    var jitter: Double? = nil

    var packetLoss: Double {
        guard sent > 0 else { return 0 }
        return Double(max(0, sent - received)) / Double(sent)
    }

    static let empty = PingStatistics()
}

enum HostScanStatus: Sendable, Equatable {
    case pending
    case online
    case timeout
    case unreachable
    case failed

    var label: String {
        switch self {
        case .pending:
            return "等待"
        case .online:
            return "在线"
        case .timeout:
            return "超时"
        case .unreachable:
            return "不可达"
        case .failed:
            return "失败"
        }
    }
}

struct HostScanResult: Identifiable {
    let address: IPv4Address
    var status: HostScanStatus = .pending
    var latencyMs: Double? = nil
    var message: String? = nil

    var id: UInt32 { address.value }
}

enum LatencyFormatter {
    static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 10 {
            return String(format: "%.1f ms", value)
        }
        return String(format: "%.0f ms", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
