import Foundation

enum ReportTestKind: String, CaseIterable, Identifiable, Sendable {
    case ping
    case dhcp
    case traceroute
    case loop
    case storm
    case wifi
    case subnet
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: return "Ping 连通性"
        case .dhcp: return "DHCP 服务器"
        case .traceroute: return "路由追踪"
        case .loop: return "环路检测"
        case .storm: return "网络风暴"
        case .wifi: return "WiFi 分析"
        case .subnet: return "子网计算"
        case .speed: return "内外网测速"
        }
    }

    var icon: String {
        switch self {
        case .ping: return "dot.radiowaves.left.and.right"
        case .dhcp: return "server.rack"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .loop: return "arrow.triangle.2.circlepath"
        case .storm: return "bolt.horizontal.circle"
        case .wifi: return "wifi"
        case .subnet: return "square.grid.3x3"
        case .speed: return "speedometer"
        }
    }
}

enum ReportStatus: String, Sendable, Equatable {
    case pass
    case warning
    case fail
    case skipped

    var label: String {
        switch self {
        case .pass: return "正常"
        case .warning: return "需关注"
        case .fail: return "失败"
        case .skipped: return "跳过"
        }
    }
}

struct ReportMetric: Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

struct ReportTestResult: Identifiable, Sendable {
    let kind: ReportTestKind
    let status: ReportStatus
    let headline: String
    let metrics: [ReportMetric]
    let details: [String]
    let duration: TimeInterval

    var id: String { kind.rawValue }
}

struct ReportProgress: Sendable {
    let kind: ReportTestKind
    let completed: Int
    let total: Int
    let message: String

    var value: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

struct ReportSnapshot: Sendable {
    let generatedAt: Date
    let hostName: String
    let system: String
    let appVersion: String
    let interfaceName: String?
    let localAddress: String?
    let subnet: String?
    let gateway: String?
    let diagnosticInterface: String?
    let wifi: WiFiNetworkInfo?
    let results: [ReportTestResult]

    var passCount: Int { results.filter { $0.status == .pass }.count }
    var warningCount: Int { results.filter { $0.status == .warning }.count }
    var failCount: Int { results.filter { $0.status == .fail }.count }
    var skippedCount: Int { results.filter { $0.status == .skipped }.count }

    var overall: ReportStatus {
        if failCount > 0 { return .fail }
        if warningCount > 0 { return .warning }
        if results.isEmpty { return .skipped }
        if skippedCount == results.count { return .skipped }
        return .pass
    }

    var score: Int {
        let penalty = failCount * 20 + warningCount * 8 + skippedCount * 5
        return max(0, 100 - penalty)
    }

    var summaryLine: String {
        "\(results.count) 项检测 · \(passCount) 正常 · \(warningCount) 需关注 · \(failCount) 失败 · \(skippedCount) 跳过"
    }
}
