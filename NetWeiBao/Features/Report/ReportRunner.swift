import CoreLocation
import Foundation
import NetworkExtension
import UIKit

@MainActor
enum ReportRunner {
    static let reportSpeedDownloadMB = 10
    static let reportSpeedUploadMB = 5

    static func run(
        onProgress: @escaping @MainActor (ReportProgress) -> Void
    ) async throws -> ReportSnapshot {
        let startedAt = Date()
        let info = NetworkInterface.activeIPv4()
        let gateway = await GatewayDetector.detect(interface: info)
        let target = gateway
            ?? info?.subnet.firstHost
            ?? IPv4Address("223.5.5.5")!

        let total = ReportTestKind.allCases.count
        var completed = 0
        var results: [ReportTestResult] = []
        var baselineForWiFi: LinkQuality?

        func emit(_ kind: ReportTestKind, _ message: String) {
            onProgress(
                ReportProgress(
                    kind: kind,
                    completed: completed,
                    total: total,
                    message: message
                )
            )
        }

        func append(_ kind: ReportTestKind, _ result: ReportTestResult, by count: Int = 1) {
            results.append(result)
            completed += count
            emit(kind, result.headline)
        }

        // MARK: Ping
        emit(.ping, "Ping \(target)")
        var sent = 0
        var received = 0
        var latencies: [Double] = []
        var pingErrors: [String] = []

        for _ in 0..<4 {
            try Task.checkCancellation()
            let outcome = await PingEngine.shared.ping(target, timeout: 1.0)
            sent += 1
            switch outcome {
            case .reply(let latency, _):
                received += 1
                latencies.append(latency)
            case .unreachable(let message), .failure(let message):
                pingErrors.append(message)
            case .timeout:
                break
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        let pingLoss = sent > 0 ? Double(sent - received) / Double(sent) : 1
        let pingStatus: ReportStatus = received == 0
            ? .fail
            : (pingLoss > 0 ? .warning : .pass)
        let pingQuality = LinkQuality(
            sent: sent,
            received: received,
            timeouts: sent - received,
            latencies: latencies
        )
        append(
            .ping,
            ReportTestResult(
                kind: .ping,
                status: pingStatus,
                headline: received == 0 ? "目标无响应" : "\(received)/\(sent) 响应 · 丢包 \(percent(pingLoss))",
                metrics: [
                    ReportMetric(label: "目标", value: target.description),
                    ReportMetric(label: "发送/接收", value: "\(sent) / \(received)"),
                    ReportMetric(label: "丢包", value: percent(pingLoss)),
                    ReportMetric(label: "平均延迟", value: milliseconds(pingQuality.average)),
                    ReportMetric(label: "抖动", value: milliseconds(pingQuality.jitter))
                ],
                details: pingErrors.isEmpty ? [] : Array(Set(pingErrors)).prefix(2).map { $0 },
                duration: Date().timeIntervalSince(startedAt)
            )
        )

        // MARK: DHCP
        try Task.checkCancellation()
        emit(.dhcp, "发送 DHCPDISCOVER")
        let dhcpStartedAt = Date()
        let dhcp = await DHCPProbeService.shared.discover(timeout: 4.0)
        let dhcpStatus: ReportStatus = dhcp.errorMessage != nil
            ? .fail
            : (dhcp.offers.isEmpty ? .warning : .pass)
        var dhcpMetrics: [ReportMetric] = [
            ReportMetric(label: "发现服务器", value: "\(dhcp.offers.count) 台"),
            ReportMetric(label: "本机接口", value: dhcp.interfaceName ?? "—"),
            ReportMetric(label: "客户端端口", value: dhcp.boundPort.map(String.init) ?? "—")
        ]
        if let first = dhcp.offers.first {
            dhcpMetrics.append(
                ReportMetric(label: "服务器", value: first.serverIdentifier?.description ?? first.sourceAddress?.description ?? "—")
            )
            dhcpMetrics.append(
                ReportMetric(label: "分配地址", value: first.offeredAddress?.description ?? "—")
            )
            dhcpMetrics.append(
                ReportMetric(label: "网关", value: first.routers.map(\.description).joined(separator: ", "))
            )
            dhcpMetrics.append(
                ReportMetric(label: "DNS", value: first.dnsServers.map(\.description).joined(separator: ", "))
            )
        }
        append(
            .dhcp,
            ReportTestResult(
                kind: .dhcp,
                status: dhcpStatus,
                headline: dhcp.errorMessage
                    ?? (dhcp.offers.isEmpty ? "未收到 DHCPOFFER" : "发现 \(dhcp.offers.count) 台 DHCP 服务器"),
                metrics: dhcpMetrics,
                details: dhcp.warnings,
                duration: Date().timeIntervalSince(dhcpStartedAt)
            )
        )

        // MARK: Traceroute
        try Task.checkCancellation()
        emit(.traceroute, "逐跳追踪 \(target)")
        let traceStartedAt = Date()
        var hops: [TracerouteHop] = []
        for ttl in 1...12 {
            try Task.checkCancellation()
            let hop = await TracerouteProbe.probe(
                target: target,
                ttl: ttl,
                attempts: 1,
                timeout: 0.7
            )
            hops.append(hop)
            if hop.status == .target || hop.status == .unreachable {
                break
            }
        }
        let reached = hops.contains { $0.status == .target }
        let sawHop = hops.contains { $0.status == .hop || $0.status == .target }
        let traceStatus: ReportStatus = reached
            ? .pass
            : (sawHop ? .warning : .warning)
        let path = hops.map { hop -> String in
            if let address = hop.address {
                return "\(hop.ttl) \(address)"
            }
            return "\(hop.ttl) *"
        }.joined(separator: "  →  ")
        append(
            .traceroute,
            ReportTestResult(
                kind: .traceroute,
                status: traceStatus,
                headline: reached
                    ? "已到达目标，共 \(hops.count) 跳"
                    : "未到达目标，记录 \(hops.count) 跳",
                metrics: [
                    ReportMetric(label: "目标", value: target.description),
                    ReportMetric(label: "跳数", value: "\(hops.count)"),
                    ReportMetric(label: "路径", value: path.isEmpty ? "无 ICMP 跳点" : path)
                ],
                details: sawHop ? [] : ["iOS 可能不暴露 ICMP Time Exceeded，结果为尽力而为。"],
                duration: Date().timeIntervalSince(traceStartedAt)
            )
        )

        // MARK: Loop / Storm
        try Task.checkCancellation()
        emit(.loop, "环路 / 风暴采样")
        let anomalyStartedAt = Date()
        let baseline = await LinkSampler.measure(
            target: target,
            count: 5,
            interval: 0.12,
            timeout: 0.7
        )
        baselineForWiFi = baseline
        try Task.checkCancellation()

        let unicast = await EchoBurstProbe.unicast(
            target: target,
            count: 6,
            interval: 0.08,
            listenWindow: 1.2
        )
        try Task.checkCancellation()

        let broadcast = await EchoBurstProbe.broadcast(
            count: 5,
            interval: 0.1,
            listenWindow: 1.2
        )
        try Task.checkCancellation()

        let post = await LinkSampler.measure(
            target: target,
            count: 5,
            interval: 0.12,
            timeout: 0.7
        )
        try Task.checkCancellation()

        let loopReport = AnomalyAnalyzer.analyze(
            mode: .loop,
            target: target.description,
            interfaceName: info?.name,
            baseline: baseline,
            unicast: unicast,
            broadcast: broadcast,
            post: post
        )
        let stormReport = AnomalyAnalyzer.analyze(
            mode: .storm,
            target: target.description,
            interfaceName: info?.name,
            baseline: baseline,
            unicast: unicast,
            broadcast: broadcast,
            post: post
        )
        let anomalyDuration = Date().timeIntervalSince(anomalyStartedAt)
        append(
            .loop,
            ReportTestResult(
                kind: .loop,
                status: anomalyStatus(loopReport.risk),
                headline: loopReport.headline,
                metrics: anomalyMetrics(loopReport),
                details: Array(loopReport.evidence.prefix(3)),
                duration: anomalyDuration / 2
            )
        )
        append(
            .storm,
            ReportTestResult(
                kind: .storm,
                status: anomalyStatus(stormReport.risk),
                headline: stormReport.headline,
                metrics: anomalyMetrics(stormReport),
                details: Array(stormReport.evidence.prefix(3)),
                duration: anomalyDuration / 2
            )
        )

        // MARK: WiFi
        try Task.checkCancellation()
        emit(.wifi, "读取当前 WiFi")
        let wifiStartedAt = Date()
        let wifi = await currentWiFi()
        let wifStatus: ReportStatus
        if info?.name.hasPrefix("en") != true {
            wifStatus = .skipped
        } else if wifi == nil {
            wifStatus = .warning
        } else {
            wifStatus = .pass
        }
        var wifiMetrics: [ReportMetric] = [
            ReportMetric(label: "接口", value: info?.name ?? "—"),
            ReportMetric(label: "本机地址", value: info?.address.description ?? "—")
        ]
        if let wifi {
            wifiMetrics.append(ReportMetric(label: "SSID", value: wifi.ssid))
            wifiMetrics.append(ReportMetric(label: "BSSID", value: wifi.bssid))
            wifiMetrics.append(ReportMetric(label: "信号", value: percent(wifi.signalStrength)))
        }
        if let baselineForWiFi {
            wifiMetrics.append(
                ReportMetric(label: "网关延迟", value: milliseconds(baselineForWiFi.average))
            )
            wifiMetrics.append(
                ReportMetric(label: "网关丢包", value: percent(baselineForWiFi.loss))
            )
        }
        append(
            .wifi,
            ReportTestResult(
                kind: .wifi,
                status: wifStatus,
                headline: info?.name.hasPrefix("en") != true
                    ? "当前不是 WiFi 接口"
                    : (wifi == nil ? "无法读取 SSID/BSSID" : "已读取 \(wifi!.ssid)"),
                metrics: wifiMetrics,
                details: wifi == nil
                    ? ["需要精确位置权限和 WiFi Info entitlement；SSID 不可用时仍保留网关质量。"]
                    : [],
                duration: Date().timeIntervalSince(wifiStartedAt)
            )
        )

        // MARK: Subnet
        try Task.checkCancellation()
        emit(.subnet, "计算本机子网")
        let subnetStartedAt = Date()
        let subnetResult: ReportTestResult
        if let info {
            let subnet = info.subnet
            subnetResult = ReportTestResult(
                kind: .subnet,
                status: .pass,
                headline: subnet.cidr,
                metrics: [
                    ReportMetric(label: "网络地址", value: subnet.network.description),
                    ReportMetric(label: "广播地址", value: subnet.broadcast.description),
                    ReportMetric(label: "掩码", value: subnet.netmask.description),
                    ReportMetric(label: "可用主机", value: "\(subnet.usableHostCount)"),
                    ReportMetric(label: "主机范围", value: "\(subnet.firstHost.description) – \(subnet.lastHost.description)")
                ],
                details: [],
                duration: Date().timeIntervalSince(subnetStartedAt)
            )
        } else {
            subnetResult = ReportTestResult(
                kind: .subnet,
                status: .skipped,
                headline: "没有 IPv4 接口",
                metrics: [],
                details: ["连接 Wi-Fi 或局域网后再测。"],
                duration: Date().timeIntervalSince(subnetStartedAt)
            )
        }
        append(.subnet, subnetResult)

        // MARK: Speed
        try Task.checkCancellation()
        emit(.speed, "快速测速 \(reportSpeedDownloadMB) MB / \(reportSpeedUploadMB) MB")
        let speedStartedAt = Date()
        let speedResult = await quickSpeedResult()
        append(.speed, speedResult)

        _ = startedAt
        return ReportSnapshot(
            generatedAt: Date(),
            hostName: ProcessInfo.processInfo.hostName,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
            interfaceName: info?.name,
            localAddress: info?.address.description,
            subnet: info.map { $0.subnet.cidr },
            gateway: gateway?.description,
            diagnosticInterface: NetworkInterfaceSelection.shared.selectedName,
            wifi: wifi,
            results: results
        )
    }

    private static func quickSpeedResult() async -> ReportTestResult {
        let startedAt = Date()
        let node = SpeedTestNode(
            name: "洛杉矶 · Sharktech (LibreSpeed)",
            baseURL: URL(string: SpeedTestViewModel.defaultExternalURL)!,
            referer: nil
        )

        do {
            let latency = try await SpeedTestService.shared.measureLatency(
                node: node,
                count: 3
            )
            let download = try await SpeedTestService.shared.download(
                node: node,
                megabytes: reportSpeedDownloadMB
            )
            let upload = try await SpeedTestService.shared.upload(
                node: node,
                megabytes: reportSpeedUploadMB
            )
            return ReportTestResult(
                kind: .speed,
                status: .pass,
                headline: String(
                    format: "↓ %.1f Mbps · ↑ %.1f Mbps",
                    download.mbps,
                    upload.mbps
                ),
                metrics: [
                    ReportMetric(label: "下载", value: String(format: "%.1f Mbps", download.mbps)),
                    ReportMetric(label: "上传", value: String(format: "%.1f Mbps", upload.mbps)),
                    ReportMetric(label: "延迟", value: milliseconds(latency.average)),
                    ReportMetric(label: "抖动", value: milliseconds(latency.jitter)),
                    ReportMetric(label: "数据量", value: "\(reportSpeedDownloadMB) MB / \(reportSpeedUploadMB) MB"),
                    ReportMetric(label: "节点", value: node.name)
                ],
                details: ["报告使用快速测速，避免一键检测消耗过多流量。"],
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return ReportTestResult(
                kind: .speed,
                status: .fail,
                headline: error.localizedDescription,
                metrics: [
                    ReportMetric(label: "节点", value: node.name),
                    ReportMetric(label: "数据量", value: "\(reportSpeedDownloadMB) MB / \(reportSpeedUploadMB) MB")
                ],
                details: ["可在内外网测速中换节点或调小数据量后单独复测。"],
                duration: Date().timeIntervalSince(startedAt)
            )
        }
    }

    private static func anomalyStatus(_ risk: AnomalyRisk) -> ReportStatus {
        switch risk {
        case .none: return .pass
        case .suspected, .unknown: return .warning
        }
    }

    private static func anomalyMetrics(_ report: AnomalyReport) -> [ReportMetric] {
        [
            ReportMetric(label: "结论", value: report.risk.rawValue),
            ReportMetric(label: "基线丢包", value: percent(report.baseline.loss)),
            ReportMetric(label: "平均延迟", value: milliseconds(report.baseline.average)),
            ReportMetric(label: "抖动", value: milliseconds(report.baseline.jitter)),
            ReportMetric(label: "单播重复", value: "\(report.unicast.duplicateReplies)"),
            ReportMetric(label: "广播回复/重复", value: "\(report.broadcast.totalReplies) / \(report.broadcast.duplicateReplies)")
        ]
    }

    private static func currentWiFi() async -> WiFiNetworkInfo? {
        guard CLLocationManager.authorizationStatus() != .denied,
              CLLocationManager.authorizationStatus() != .restricted
        else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: WiFiNetworkInfo(
                        ssid: network.ssid,
                        bssid: network.bssid,
                        isSecure: network.isSecure,
                        signalStrength: min(max(network.signalStrength, 0), 1),
                        autoJoined: network.didAutoJoin
                    )
                )
            }
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }
}
