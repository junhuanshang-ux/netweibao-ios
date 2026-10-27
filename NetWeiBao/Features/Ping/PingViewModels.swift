import Combine
import Foundation

@MainActor
final class SinglePingViewModel: ObservableObject {
    @Published var host = ""
    @Published var continuous = true
    @Published var timeout: TimeInterval = 1.0
    @Published var interval: TimeInterval = 1.0
    @Published private(set) var isRunning = false
    @Published private(set) var samples: [PingReply] = []
    @Published private(set) var statistics = PingStatistics.empty
    @Published private(set) var resolvedAddress: String?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()

    func start() {
        guard !isRunning else { return }

        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            errorMessage = "请输入 IP 地址或域名"
            return
        }

        errorMessage = nil
        resolvedAddress = nil
        samples.removeAll()
        statistics = .empty
        isRunning = true

        let currentRun = UUID()
        runID = currentRun
        let timeout = self.timeout
        let interval = self.interval
        let continuous = self.continuous

        task = Task { [weak self] in
            guard let self else { return }

            let resolution = await HostResolver.resolveIPv4(target)
            guard !Task.isCancelled, self.runID == currentRun else { return }

            switch resolution {
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.finish(currentRun)

            case .success(let address):
                self.resolvedAddress = address.description
                var sequence = 0
                var received = 0
                var latencies: [Double] = []
                var lastLatency: Double?
                var jitterSum = 0.0
                var jitterCount = 0

                repeat {
                    if Task.isCancelled || self.runID != currentRun { break }

                    sequence += 1
                    let outcome = await PingEngine.shared.ping(address, timeout: timeout)
                    if Task.isCancelled || self.runID != currentRun { break }

                    let reply = PingReply(sequence: sequence, outcome: outcome)
                    self.samples.append(reply)
                    if self.samples.count > 120 {
                        self.samples.removeFirst(self.samples.count - 120)
                    }

                    if case .reply(let latency, _) = outcome {
                        received += 1
                        latencies.append(latency)
                        if let previous = lastLatency {
                            jitterSum += abs(latency - previous)
                            jitterCount += 1
                        }
                        lastLatency = latency
                    }

                    let sum = latencies.reduce(0, +)
                    self.statistics = PingStatistics(
                        sent: sequence,
                        received: received,
                        minLatency: latencies.min(),
                        averageLatency: latencies.isEmpty ? nil : sum / Double(latencies.count),
                        maxLatency: latencies.max(),
                        jitter: jitterCount > 0 ? jitterSum / Double(jitterCount) : nil
                    )

                    if !continuous { break }
                    try? await Task.sleep(
                        nanoseconds: UInt64(max(0.1, interval) * 1_000_000_000)
                    )
                } while true

                self.finish(currentRun)
            }
        }
    }

    func stop() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    func reset() {
        stop()
        samples.removeAll()
        statistics = .empty
        resolvedAddress = nil
        errorMessage = nil
    }

    private func finish(_ finishedRun: UUID) {
        guard runID == finishedRun else { return }
        isRunning = false
        task = nil
    }
}

enum HostFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case online = "在线"
    case offline = "离线"

    var id: String { rawValue }
}

private struct SubnetProbeResult: Sendable {
    let address: IPv4Address
    let outcome: PingOutcome
}

@MainActor
final class SubnetPingViewModel: ObservableObject {
    static let maximumHosts = 4096

    @Published var cidr: String
    @Published var timeout: TimeInterval = 1.0
    @Published var concurrency: Int = 32
    @Published var filter: HostFilter = .all
    @Published private(set) var isRunning = false
    @Published private(set) var results: [HostScanResult] = []
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var onlineCount = 0
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var indexByAddress: [UInt32: Int] = [:]

    init() {
        self.cidr = Self.suggestedCIDR()
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var displayedResults: [HostScanResult] {
        switch filter {
        case .all:
            return results
        case .online:
            return results.filter { $0.status == .online }
        case .offline:
            return results.filter {
                $0.status != .online && $0.status != .pending
            }
        }
    }

    var summaryText: String {
        guard total > 0 else { return "尚未开始扫描" }
        return "\(completed)/\(total) 已扫描 · \(onlineCount) 台在线"
    }

    func useLocalSubnet() {
        cidr = Self.suggestedCIDR()
    }

    func start() {
        guard !isRunning else { return }
        guard let subnet = IPv4Subnet(cidr: cidr) else {
            errorMessage = "CIDR 格式不正确，示例：192.168.1.0/24"
            return
        }

        guard subnet.usableHostCount <= UInt64(Self.maximumHosts) else {
            errorMessage = "网段过大。单次最多扫描 \(Self.maximumHosts) 个地址，请使用 /20 或更小范围。"
            return
        }

        let hosts = subnet.hostAddresses(limit: Self.maximumHosts)
        guard !hosts.isEmpty else {
            errorMessage = "该网段没有可扫描的主机地址"
            return
        }

        errorMessage = nil
        results = hosts.map { HostScanResult(address: $0) }
        var indexMap: [UInt32: Int] = [:]
        for (index, host) in hosts.enumerated() {
            indexMap[host.value] = index
        }
        indexByAddress = indexMap
        completed = 0
        total = hosts.count
        onlineCount = 0
        filter = .all
        isRunning = true

        let currentRun = UUID()
        runID = currentRun
        let timeout = self.timeout
        let concurrency = min(max(self.concurrency, 4), 32)

        task = Task { [weak self] in
            guard let self else { return }
            await self.scan(
                hosts: hosts,
                timeout: timeout,
                concurrency: concurrency,
                currentRun: currentRun
            )
        }
    }

    func stop() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    func reset() {
        stop()
        results.removeAll()
        indexByAddress.removeAll()
        completed = 0
        total = 0
        onlineCount = 0
        errorMessage = nil
    }

    private func scan(
        hosts: [IPv4Address],
        timeout: TimeInterval,
        concurrency: Int,
        currentRun: UUID
    ) async {
        var batch: [SubnetProbeResult] = []
        var lastFlush = Date.distantPast

        func flushIfNeeded(force: Bool) {
            guard force || batch.count >= 16 || Date().timeIntervalSince(lastFlush) >= 0.1 else {
                return
            }

            let delta = apply(batch)
            completed += delta.completed
            onlineCount += delta.online
            batch.removeAll(keepingCapacity: true)
            lastFlush = Date()
        }

        await withTaskGroup(of: SubnetProbeResult.self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0
            let window = min(concurrency, hosts.count)

            for _ in 0..<window {
                guard let host = iterator.next() else { break }
                inFlight += 1
                group.addTask {
                    let outcome = await PingEngine.shared.ping(host, timeout: timeout)
                    return SubnetProbeResult(address: host, outcome: outcome)
                }
            }

            while inFlight > 0, let result = await group.next() {
                inFlight -= 1

                guard runID == currentRun, !Task.isCancelled else {
                    group.cancelAll()
                    break
                }

                batch.append(result)
                flushIfNeeded(force: false)

                if let next = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        let outcome = await PingEngine.shared.ping(next, timeout: timeout)
                        return SubnetProbeResult(address: next, outcome: outcome)
                    }
                }
            }

            group.cancelAll()
        }

        guard runID == currentRun else { return }
        flushIfNeeded(force: true)
        isRunning = false
        task = nil
    }

    private func apply(_ batch: [SubnetProbeResult]) -> (completed: Int, online: Int) {
        guard !batch.isEmpty else { return (0, 0) }

        var updatedResults = results
        var completedCount = 0
        var onlineIncrement = 0

        for probe in batch {
            guard let index = indexByAddress[probe.address.value] else { continue }
            completedCount += 1

            switch probe.outcome {
            case .reply(let latency, _):
                updatedResults[index].status = .online
                updatedResults[index].latencyMs = latency
                updatedResults[index].message = nil
                onlineIncrement += 1
            case .timeout:
                updatedResults[index].status = .timeout
                updatedResults[index].latencyMs = nil
                updatedResults[index].message = nil
            case .unreachable(let message):
                updatedResults[index].status = .unreachable
                updatedResults[index].latencyMs = nil
                updatedResults[index].message = message
            case .failure(let message):
                updatedResults[index].status = .failed
                updatedResults[index].latencyMs = nil
                updatedResults[index].message = message
            }
        }

        results = updatedResults
        return (completedCount, onlineIncrement)
    }

    static func suggestedCIDR() -> String {
        guard let interface = NetworkInterface.activeIPv4(),
              interface.name.hasPrefix("en") || interface.name.hasPrefix("bridge")
        else {
            return "192.168.1.0/24"
        }

        var prefix = interface.prefixLength
        if !(20...30).contains(prefix) {
            prefix = 24
        }
        return IPv4Subnet(address: interface.address, prefixLength: prefix).cidr
    }
}

struct BatchTargetRow: Identifiable {
    let id: Int
    let target: String
    var address: String? = nil
    var status: HostScanStatus = .pending
    var sent = 0
    var received = 0
    var averageLatency: Double? = nil
    var message: String? = nil
}

struct BatchProbeOutcome: Sendable {
    let id: Int
    let address: String?
    let status: HostScanStatus
    let sent: Int
    let received: Int
    let averageLatency: Double?
    let message: String?
}

@MainActor
final class BatchPingViewModel: ObservableObject {
    @Published var input = "223.5.5.5\nwww.baidu.com"
    @Published var attempts = 2
    @Published var timeout: TimeInterval = 1.0
    @Published private(set) var isRunning = false
    @Published private(set) var rows: [BatchTargetRow] = []
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    func start() {
        guard !isRunning else { return }

        let parsed = Self.parseTargets(input)
        guard !parsed.targets.isEmpty else {
            errorMessage = "请输入至少一个 IP、域名或 CIDR"
            return
        }

        errorMessage = nil
        noticeMessage = parsed.truncated
            ? "目标过多，已截取前 \(parsed.targets.count) 个"
            : nil
        rows = parsed.targets.enumerated().map {
            BatchTargetRow(id: $0.offset, target: $0.element)
        }
        completed = 0
        total = parsed.targets.count
        isRunning = true

        let currentRun = UUID()
        runID = currentRun
        let attempts = min(max(self.attempts, 1), 5)
        let timeout = self.timeout

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                targets: parsed.targets,
                attempts: attempts,
                timeout: timeout,
                currentRun: currentRun
            )
        }
    }

    func stop() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false

        for index in rows.indices where rows[index].status == .pending {
            rows[index].status = .failed
            rows[index].message = "已停止"
        }
    }

    func reset() {
        stop()
        rows.removeAll()
        completed = 0
        total = 0
        errorMessage = nil
        noticeMessage = nil
    }

    private func run(
        targets: [String],
        attempts: Int,
        timeout: TimeInterval,
        currentRun: UUID
    ) async {
        await withTaskGroup(of: BatchProbeOutcome.self) { group in
            var iterator = targets.enumerated().makeIterator()
            var inFlight = 0
            let window = min(8, targets.count)

            for _ in 0..<window {
                guard let next = iterator.next() else { break }
                inFlight += 1
                group.addTask {
                    await BatchProbeRunner.probe(
                        id: next.offset,
                        target: next.element,
                        attempts: attempts,
                        timeout: timeout
                    )
                }
            }

            while inFlight > 0, let result = await group.next() {
                inFlight -= 1

                guard runID == currentRun, !Task.isCancelled else {
                    group.cancelAll()
                    break
                }

                apply(result)
                completed += 1

                if let next = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        await BatchProbeRunner.probe(
                            id: next.offset,
                            target: next.element,
                            attempts: attempts,
                            timeout: timeout
                        )
                    }
                }
            }

            group.cancelAll()
        }

        guard runID == currentRun else { return }
        isRunning = false
        task = nil
    }

    private func apply(_ result: BatchProbeOutcome) {
        guard let index = rows.firstIndex(where: { $0.id == result.id }) else { return }
        rows[index].address = result.address
        rows[index].status = result.status
        rows[index].sent = result.sent
        rows[index].received = result.received
        rows[index].averageLatency = result.averageLatency
        rows[index].message = result.message
    }

    nonisolated static func parseTargets(_ raw: String) -> (targets: [String], truncated: Bool) {
        let separators = CharacterSet(charactersIn: ",，;；\n\r\t ")
        let tokens = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let limit = 128
        var seen = Set<String>()
        var targets: [String] = []
        var truncated = false

        outer: for token in tokens {
            let expanded: [String]

            if token.contains("/"), let subnet = IPv4Subnet(cidr: token),
               subnet.prefixLength >= 24,
               subnet.usableHostCount <= 254 {
                expanded = subnet.hostAddresses(limit: 254).map(\.description)
            } else {
                expanded = [token]
            }

            for item in expanded {
                let key = item.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                if targets.count >= limit {
                    truncated = true
                    break outer
                }
                targets.append(item)
            }
        }

        return (targets, truncated)
    }
}

enum BatchProbeRunner {
    static func probe(
        id: Int,
        target: String,
        attempts: Int,
        timeout: TimeInterval
    ) async -> BatchProbeOutcome {
        let resolution = await HostResolver.resolveIPv4(target)

        guard case .success(let address) = resolution else {
            let message: String
            if case .failure(let error) = resolution {
                message = error.localizedDescription
            } else {
                message = "域名解析失败"
            }
            return BatchProbeOutcome(
                id: id,
                address: nil,
                status: .failed,
                sent: 0,
                received: 0,
                averageLatency: nil,
                message: message
            )
        }

        var sent = 0
        var received = 0
        var latencies: [Double] = []
        var lastOutcome: PingOutcome = .timeout

        for attempt in 0..<max(1, attempts) {
            if Task.isCancelled { break }
            let outcome = await PingEngine.shared.ping(address, timeout: timeout)
            sent += 1
            lastOutcome = outcome

            if case .reply(let latency, _) = outcome {
                received += 1
                latencies.append(latency)
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        let status: HostScanStatus
        var message: String?

        if received > 0 {
            status = .online
        } else {
            switch lastOutcome {
            case .unreachable(let detail):
                status = .unreachable
                message = detail
            case .failure(let detail):
                status = .failed
                message = detail
            case .reply, .timeout:
                status = .timeout
            }
        }

        let average = latencies.isEmpty
            ? nil
            : latencies.reduce(0, +) / Double(latencies.count)

        return BatchProbeOutcome(
            id: id,
            address: address.description,
            status: status,
            sent: sent,
            received: received,
            averageLatency: average,
            message: message
        )
    }
}
