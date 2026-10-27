import Darwin
import Dispatch
import Foundation

enum LinkSampler {
    static func measure(
        target: IPv4Address,
        count: Int = 8,
        interval: TimeInterval = 0.12,
        timeout: TimeInterval = 0.8
    ) async -> LinkQuality {
        let total = max(1, count)
        var sent = 0
        var received = 0
        var timeouts = 0
        var latencies: [Double] = []

        for index in 0..<total {
            if Task.isCancelled { break }

            let outcome = await PingEngine.shared.ping(target, timeout: timeout)
            sent += 1

            switch outcome {
            case .reply(let latency, _):
                received += 1
                latencies.append(latency)
            case .timeout:
                timeouts += 1
            case .unreachable, .failure:
                break
            }

            if index < total - 1 {
                try? await Task.sleep(
                    nanoseconds: UInt64(max(0.05, interval) * 1_000_000_000)
                )
            }
        }

        return LinkQuality(
            sent: sent,
            received: received,
            timeouts: timeouts,
            latencies: latencies
        )
    }
}

enum EchoBurstProbe {
    private static let queue = DispatchQueue(
        label: "com.netweibao.anomaly.echo-burst",
        qos: .userInitiated
    )

    static func unicast(
        target: IPv4Address,
        count: Int = 10,
        interval: TimeInterval = 0.08,
        listenWindow: TimeInterval = 1.5
    ) async -> EchoBurstResult {
        await burst(
            target: target,
            isBroadcast: false,
            count: count,
            interval: interval,
            listenWindow: listenWindow
        )
    }

    static func broadcast(
        count: Int = 8,
        interval: TimeInterval = 0.1,
        listenWindow: TimeInterval = 1.5
    ) async -> EchoBurstResult {
        await burst(
            target: .broadcast,
            isBroadcast: true,
            count: count,
            interval: interval,
            listenWindow: listenWindow
        )
    }

    private static func burst(
        target: IPv4Address,
        isBroadcast: Bool,
        count: Int,
        interval: TimeInterval,
        listenWindow: TimeInterval
    ) async -> EchoBurstResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<EchoBurstResult, Never>) in
            queue.async {
                continuation.resume(
                    returning: performBurst(
                        target: target,
                        isBroadcast: isBroadcast,
                        count: count,
                        interval: interval,
                        listenWindow: listenWindow
                    )
                )
            }
        }
    }

    private static func performBurst(
        target: IPv4Address,
        isBroadcast: Bool,
        count: Int,
        interval: TimeInterval,
        listenWindow: TimeInterval
    ) -> EchoBurstResult {
        let startedAt = Date()
        let total = max(1, count)
        let identifier = UInt16.random(in: 1...UInt16.max)
        let destination = target
        var warnings: [String] = []

        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fileDescriptor >= 0 else {
            return emptyResult(
                sent: 0,
                isBroadcast: isBroadcast,
                target: destination.description,
                duration: Date().timeIntervalSince(startedAt),
                warnings: ["无法创建 ICMP 套接字：\(posixMessage(errno))"]
            )
        }
        defer { _ = close(fileDescriptor) }

        var enabled: Int32 = 1
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var receiveBuffer: Int32 = 1_024 * 1_024
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBuffer,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var sentSequences = Set<UInt16>()
        var replyCounts: [ReplyKey: Int] = [:]
        var totalReplies = 0

        for sequence in 1...total {
            let packet = ICMPPacket.echoRequest(
                identifier: identifier,
                sequence: UInt16(sequence),
                payloadSize: 32
            )
            if let code = send(packet: packet, socket: fileDescriptor, destination: destination) {
                warnings.append("发送广播探测失败：\(posixMessage(code))")
            } else {
                sentSequences.insert(UInt16(sequence))
            }

            if sequence < total {
                Thread.sleep(forTimeInterval: max(0.02, interval))
            }
        }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(max(0.5, listenWindow) * 1_000_000_000)
        var buffer = [UInt8](repeating: 0, count: 2_048)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }

            let remaining = deadline - now
            let waitMilliseconds = Int32(min(200, max(1, remaining / 1_000_000)))

            var pollDescriptor = pollfd(
                fd: fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let pollResult = poll(&pollDescriptor, 1, waitMilliseconds)

            if pollResult == 0 { continue }
            if pollResult < 0 {
                if errno == EINTR { continue }
                warnings.append("等待广播回复失败：\(posixMessage(errno))")
                break
            }

            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let receivedBytes = withUnsafeMutablePointer(to: &source) { sourcePointer in
                sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    buffer.withUnsafeMutableBytes { rawBuffer in
                        recvfrom(
                            fileDescriptor,
                            rawBuffer.baseAddress,
                            rawBuffer.count,
                            0,
                            socketAddress,
                            &sourceLength
                        )
                    }
                }
            }

            if receivedBytes < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                warnings.append("接收广播回复失败：\(posixMessage(errno))")
                continue
            }

            guard receivedBytes > 0 else { continue }
            let bytes = Array(buffer[0..<Int(receivedBytes)])
            guard let reply = ICMPPacket.echoReplyInfo(bytes, length: Int(receivedBytes)),
                  reply.identifier == identifier,
                  sentSequences.contains(reply.sequence)
            else {
                continue
            }

            let sourceAddress = IPv4Address(
                value: UInt32(bigEndian: source.sin_addr.s_addr)
            )
            let key = ReplyKey(sequence: reply.sequence, source: sourceAddress)
            replyCounts[key, default: 0] += 1
            totalReplies += 1
        }

        let uniquePairs = replyCounts.count
        let duplicateReplies = max(0, totalReplies - uniquePairs)
        let duplicatePairs = replyCounts.values.filter { $0 > 1 }.count
        let maxRepliesPerPair = replyCounts.values.max() ?? 0
        let uniqueResponders = Set(replyCounts.keys.map(\.source)).sorted()

        return EchoBurstResult(
            isBroadcast: isBroadcast,
            sent: sentSequences.count,
            totalReplies: totalReplies,
            uniquePairs: uniquePairs,
            duplicateReplies: duplicateReplies,
            duplicatePairs: duplicatePairs,
            maxRepliesPerPair: maxRepliesPerPair,
            uniqueResponders: uniqueResponders,
            target: destination.description,
            warnings: uniqueWarnings(warnings),
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private struct ReplyKey: Hashable {
        let sequence: UInt16
        let source: IPv4Address
    }

    private static func send(
        packet: [UInt8],
        socket fileDescriptor: Int32,
        destination: IPv4Address
    ) -> Int32? {
        var address = destination.sockaddr
        address.sin_port = 0

        let sentBytes = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        fileDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        return sentBytes < 0 ? errno : nil
    }

    private static func emptyResult(
        sent: Int,
        isBroadcast: Bool,
        target: String,
        duration: TimeInterval,
        warnings: [String]
    ) -> EchoBurstResult {
        EchoBurstResult(
            isBroadcast: isBroadcast,
            sent: sent,
            totalReplies: 0,
            uniquePairs: 0,
            duplicateReplies: 0,
            duplicatePairs: 0,
            maxRepliesPerPair: 0,
            uniqueResponders: [],
            target: target,
            warnings: warnings,
            duration: duration
        )
    }

    private static func uniqueWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }

    private static func posixMessage(_ code: Int32) -> String {
        guard let message = strerror(code) else { return "errno \(code)" }
        return String(cString: message)
    }
}

enum GatewayDetector {
    /// Best-effort LAN gateway guess: probe the first and last usable host in the subnet.
    /// This avoids relying on unavailable iOS routing-table APIs.
    static func detect(interface: NetworkInterface.Info?) async -> IPv4Address? {
        guard let interface,
              interface.name.hasPrefix("en") || interface.name.hasPrefix("bridge"),
              (16...30).contains(interface.prefixLength)
        else {
            return nil
        }

        let first = interface.subnet.firstHost
        let last = IPv4Address(value: interface.subnet.broadcast.value &- 1)
        var candidates: [IPv4Address] = []
        for candidate in [first, last] where candidate != interface.address && !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        guard !candidates.isEmpty else { return nil }

        var reachable: [IPv4Address: Bool] = [:]
        await withTaskGroup(of: (IPv4Address, Bool).self) { group in
            for candidate in candidates {
                group.addTask {
                    let outcome = await PingEngine.shared.ping(candidate, timeout: 0.35)
                    return (candidate, outcome.isSuccess)
                }
            }

            for await result in group {
                reachable[result.0] = result.1
            }
        }

        return candidates.first { reachable[$0] == true }
    }
}

enum AnomalyAnalyzer {
    static func analyze(
        mode: AnomalyMode,
        target: String,
        interfaceName: String?,
        baseline: LinkQuality,
        unicast: EchoBurstResult,
        broadcast: EchoBurstResult,
        post: LinkQuality
    ) -> AnomalyReport {
        var evidence: [String] = []
        var suggestions: [String] = []
        evidence.append(
            "基线：\(baseline.received)/\(baseline.sent) 响应，丢包 \(percent(baseline.loss))，平均 \(latency(baseline.average))，抖动 \(latency(baseline.jitter))"
        )
        evidence.append(
            "单播回声：发送 \(unicast.sent)，收到 \(unicast.totalReplies) 个回复，同源重复 \(unicast.duplicateReplies) 个"
        )
        evidence.append(
            "广播回声：发送 \(broadcast.sent)，收到 \(broadcast.totalReplies) 个回复，来自 \(broadcast.uniqueResponders.count) 台设备，同源重复 \(broadcast.duplicateReplies) 个"
        )
        evidence.append(
            "复测：\(post.received)/\(post.sent) 响应，丢包 \(percent(post.loss))，平均 \(latency(post.average))，抖动 \(latency(post.jitter))"
        )

        let baselineUnavailable = baseline.received == 0
        let linkUnstable = baseline.loss >= 0.2 || (baseline.jitter ?? 0) >= 80
        let noBroadcastReplies = broadcast.totalReplies == 0
        let duplicateReplies = unicast.duplicateReplies + broadcast.duplicateReplies
        let lossWorse = post.loss >= baseline.loss + 0.2
        let latencyWorse: Bool = {
            guard let base = baseline.average, let after = post.average else { return false }
            return after >= base * 2 + 20
        }()
        let jitterWorse = (post.jitter ?? 0) >= max(50, (baseline.jitter ?? 0) * 2.5)
        let linkRegressed = lossWorse || latencyWorse || jitterWorse

        let risk: AnomalyRisk
        let headline: String
        let summary: String

        if baselineUnavailable {
            risk = .unknown
            headline = "目标无响应"
            summary = "检测目标没有回复 ICMP，无法建立基线，也不能据此判断环路或风暴。请确认网关地址，或换一个允许 Ping 的目标。"
            suggestions.append("确认默认网关是否就是实际网关；默认值可能只是本网段第一个地址。")
            suggestions.append("换一个允许 ICMP Ping 的目标，或检查本地网络权限。")
        } else {
            switch mode {
            case .loop:
                if duplicateReplies > 0 {
                    risk = .suspected
                    headline = "疑似重复回声"
                    summary = "回声探测中出现同源同序号重复 Reply。它可能来自广播复制/环路，也可能来自 Wi-Fi 重传或抓包镜像；这是弱信号，不能确认二层环路。"
                } else if linkUnstable {
                    risk = .unknown
                    headline = "链路本身不稳定"
                    summary = "基线丢包或抖动过高，无法可靠区分“环路导致的重复”与普通无线/链路波动。"
                } else if unicast.totalReplies == 0 {
                    risk = .unknown
                    headline = "单播回声无响应"
                    summary = "目标在基线阶段有响应，但单播回声探测没有收到回复，可能是瞬时拥塞或目标限速。"
                } else {
                    risk = .none
                    headline = "未发现明显重复迹象"
                    summary = noBroadcastReplies
                        ? "基线稳定，单播与广播探测均未出现同源重复回复。广播 ICMP 无响应，广播复制未覆盖；不能排除交换机侧环路。"
                        : "基线稳定，单播与广播探测均未出现同源重复回复。该结果不能排除交换机侧的二层环路。"
                }

            case .storm:
                if linkRegressed {
                    risk = .suspected
                    headline = "广播负载后链路退化"
                    summary = "低强度广播探测后，网关丢包/延迟/抖动明显上升。这可能是广播风暴、拥塞、无线干扰或设备限速，不能单独确认风暴。"
                } else if duplicateReplies > 0 {
                    risk = .suspected
                    headline = "疑似重复回声"
                    summary = "单播或广播探测中出现同源同序号重复回复，可能意味着广播被复制。也可能是 Wi-Fi 重传，需要抓包确认。"
                } else if linkUnstable {
                    risk = .unknown
                    headline = "链路基线不稳定"
                    summary = "基线丢包或抖动过高，无法可靠判断广播负载是否造成了额外退化。"
                } else {
                    risk = .none
                    headline = "未发现明显风暴征兆"
                    summary = noBroadcastReplies
                        ? "低强度广播探测未导致网关质量明显下降；广播 ICMP 无响应，广播级证据缺失。iOS 无法抓包，本结果不能替代端口镜像。"
                        : "低强度广播探测未导致网关质量明显下降。iOS 无法抓包，本结果不能替代端口镜像或抓包分析。"
                }
            }
        }

        if noBroadcastReplies {
            evidence.append("广播 ICMP 无响应；广播复制检测未覆盖，结论主要依据单播回声与链路质量。")
            suggestions.append("该网络可能过滤广播 ICMP；不要仅凭“无广播回复”判断环路/风暴。")
        }
        if duplicateReplies > 0 {
            suggestions.append("检查交换机 STP / MAC 表、端口指示灯，以及 Wi-Fi 重传或重复 IP。")
        }
        if linkRegressed {
            suggestions.append("检查链路利用率、AP 干扰、广播域大小；可换多个目标在不同时段复测。")
        }
        if suggestions.isEmpty {
            suggestions.append("可换多个目标复测；需要确定性结论时使用端口镜像或探针抓包。")
        }

        if let warning = unicast.warnings.first {
            evidence.append("单播探测：\(warning)")
        }
        if let warning = broadcast.warnings.first {
            evidence.append("广播探测：\(warning)")
        }
        if max(unicast.maxRepliesPerPair, broadcast.maxRepliesPerPair) > 1 {
            evidence.append("同源同序号最多收到 \(max(unicast.maxRepliesPerPair, broadcast.maxRepliesPerPair)) 个回复")
        }

        return AnomalyReport(
            mode: mode,
            risk: risk,
            headline: headline,
            summary: summary,
            evidence: evidence,
            suggestions: suggestions,
            baseline: baseline,
            post: post,
            unicast: unicast,
            broadcast: broadcast,
            target: target,
            interfaceName: interfaceName,
            createdAt: Date()
        )
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func latency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }
}
