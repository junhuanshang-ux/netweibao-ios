import Foundation

enum AnomalyMode: String, CaseIterable, Identifiable, Sendable {
    case loop = "环路检测"
    case storm = "风暴检测"

    var id: String { rawValue }
}

enum AnomalyPhase: Sendable {
    case idle
    case resolving
    case baseline
    case unicast
    case broadcast
    case post
    case analyzing
}

enum AnomalyRisk: String, Sendable {
    case none = "未发现明显迹象"
    case suspected = "疑似异常"
    case unknown = "无法判断"
}

struct LinkQuality: Sendable {
    let sent: Int
    let received: Int
    let timeouts: Int
    let latencies: [Double]

    var loss: Double {
        guard sent > 0 else { return 0 }
        return Double(max(0, sent - received)) / Double(sent)
    }

    var average: Double? {
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var minLatency: Double? {
        latencies.min()
    }

    var maxLatency: Double? {
        latencies.max()
    }

    var jitter: Double? {
        guard latencies.count > 1 else { return nil }
        var total = 0.0
        for index in 1..<latencies.count {
            total += abs(latencies[index] - latencies[index - 1])
        }
        return total / Double(latencies.count - 1)
    }
}

struct EchoBurstResult: Sendable {
    let isBroadcast: Bool
    let sent: Int
    let totalReplies: Int
    let uniquePairs: Int
    let duplicateReplies: Int
    let duplicatePairs: Int
    let maxRepliesPerPair: Int
    let uniqueResponders: [IPv4Address]
    let target: String
    let warnings: [String]
    let duration: TimeInterval
}

struct AnomalyReport: Sendable {
    let mode: AnomalyMode
    let risk: AnomalyRisk
    let headline: String
    let summary: String
    let evidence: [String]
    let suggestions: [String]
    let baseline: LinkQuality
    let post: LinkQuality
    let unicast: EchoBurstResult
    let broadcast: EchoBurstResult
    let target: String
    let interfaceName: String?
    let createdAt: Date
}
