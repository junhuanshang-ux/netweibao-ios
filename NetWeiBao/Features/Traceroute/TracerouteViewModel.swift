import Combine
import Foundation

@MainActor
final class TracerouteViewModel: ObservableObject {
    @Published var target: String
    @Published var maxHops: Int = 16
    @Published var timeout: TimeInterval = 0.8
    @Published private(set) var hops: [TracerouteHop] = []
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var reached = false
    @Published private(set) var warning: String?
    @Published private(set) var localInfo: NetworkInterface.Info?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()

    init() {
        let info = NetworkInterface.activeIPv4()
        self.localInfo = info
        self.target = info?.subnet.firstHost.description ?? ""
    }

    var suggestedTarget: String {
        localInfo?.subnet.firstHost.description ?? ""
    }

    func refreshInterface() {
        localInfo = NetworkInterface.activeIPv4()
        if target.isEmpty {
            target = suggestedTarget
        }
    }

    func useSuggestedTarget() {
        if !suggestedTarget.isEmpty {
            target = suggestedTarget
        }
    }

    func start() {
        guard !isRunning else { return }

        let input = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = "请输入目标 IP 或域名"
            return
        }

        refreshInterface()
        guard localInfo != nil else {
            errorMessage = "未识别到本机 IPv4 接口，请先连接 Wi-Fi 或局域网。"
            return
        }

        errorMessage = nil
        warning = nil
        hops.removeAll()
        isRunning = true
        reached = false
        progress = 0

        let currentRun = UUID()
        runID = currentRun
        let hopsLimit = min(max(maxHops, 1), 30)
        let hopTimeout = min(max(timeout, 0.3), 2.5)

        task = Task { [weak self] in
            guard let self else { return }

            let resolution = await HostResolver.resolveIPv4(input)
            guard !Task.isCancelled, self.runID == currentRun else { return }

            let resolvedAddress: IPv4Address
            switch resolution {
            case .success(let resolved):
                resolvedAddress = resolved
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.finish(currentRun)
                return
            }

            let address: IPv4Address
            if input == self.suggestedTarget,
               let detected = await GatewayDetector.detect(interface: self.localInfo) {
                address = detected
                self.target = detected.description
            } else {
                address = resolvedAddress
            }

            guard address != .broadcast,
                  address != .zero,
                  !address.isMulticast
            else {
                self.errorMessage = "请使用单个目标地址，不要使用广播/组播地址。"
                self.finish(currentRun)
                return
            }

            var sawHop = false
            var sawUnreachable = false

            for ttl in 1...hopsLimit {
                if Task.isCancelled || self.runID != currentRun { return }

                let hop = await TracerouteProbe.probe(
                    target: address,
                    ttl: ttl,
                    attempts: 1,
                    timeout: hopTimeout
                )
                guard !Task.isCancelled, self.runID == currentRun else { return }

                self.hops.append(hop)
                self.progress = Double(ttl) / Double(hopsLimit)

                if hop.status == .hop { sawHop = true }
                if hop.status == .target {
                    self.reached = true
                    break
                }
                if hop.status == .unreachable {
                    sawUnreachable = true
                    break
                }
            }

            if !self.reached {
                if sawUnreachable {
                    self.warning = "目标或中间设备返回不可达，追踪提前结束。"
                } else if sawHop {
                    self.warning = "在第 \(self.hops.count) 跳后未到达目标；目标可能禁 Ping，或后续路由不返回 ICMP。"
                } else {
                    self.warning = "未收到任何 ICMP Time Exceeded / Echo Reply。iOS 可能不向非特权 socket 暴露中间跳，或网络过滤了 ICMP。"
                }
            }

            self.progress = 1
            self.isRunning = false
            self.task = nil
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func finish(_ currentRun: UUID) {
        guard runID == currentRun else { return }
        isRunning = false
        progress = 0
        task = nil
    }
}
