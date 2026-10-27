import Combine
import Foundation

@MainActor
final class AnomalyViewModel: ObservableObject {
    let mode: AnomalyMode

    @Published var target: String
    @Published private(set) var phase: AnomalyPhase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var report: AnomalyReport?
    @Published private(set) var localInfo: NetworkInterface.Info?
    @Published private(set) var gateway: IPv4Address?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()

    init(mode: AnomalyMode) {
        self.mode = mode
        let info = NetworkInterface.activeIPv4()
        self.localInfo = info
        self.gateway = nil
        self.target = info?.subnet.firstHost.description ?? ""
    }

    var suggestedTarget: String {
        gateway?.description
            ?? localInfo?.subnet.firstHost.description
            ?? ""
    }

    func refreshInterface() {
        localInfo = NetworkInterface.activeIPv4()
        gateway = nil
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
            errorMessage = "请输入网关 IP 或域名"
            return
        }

        refreshInterface()
        guard localInfo != nil else {
            errorMessage = "未识别到本机 IPv4 接口，请先连接 Wi-Fi 或局域网。"
            return
        }

        errorMessage = nil
        report = nil
        isRunning = true
        phase = .resolving

        let currentRun = UUID()
        runID = currentRun
        let mode = self.mode

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
                self.gateway = detected
                self.target = detected.description
            } else {
                address = resolvedAddress
            }

            guard address != .broadcast,
                  address != .zero,
                  !address.isMulticast
            else {
                self.errorMessage = "请使用单个网关或主机地址，不要使用广播/组播地址。"
                self.finish(currentRun)
                return
            }

            self.phase = .baseline
            let baseline = await LinkSampler.measure(
                target: address,
                count: 8,
                interval: 0.12,
                timeout: 0.8
            )
            guard !Task.isCancelled, self.runID == currentRun else { return }

            self.phase = .unicast
            let unicast = await EchoBurstProbe.unicast(
                target: address,
                count: 10,
                interval: 0.08,
                listenWindow: 1.5
            )
            guard !Task.isCancelled, self.runID == currentRun else { return }

            self.phase = .broadcast
            let broadcast = await EchoBurstProbe.broadcast(
                count: 8,
                interval: 0.10,
                listenWindow: 1.5
            )
            guard !Task.isCancelled, self.runID == currentRun else { return }

            self.phase = .post
            let post = await LinkSampler.measure(
                target: address,
                count: 8,
                interval: 0.12,
                timeout: 0.8
            )
            guard !Task.isCancelled, self.runID == currentRun else { return }

            self.phase = .analyzing
            let report = AnomalyAnalyzer.analyze(
                mode: mode,
                target: address.description,
                interfaceName: self.localInfo?.name,
                baseline: baseline,
                unicast: unicast,
                broadcast: broadcast,
                post: post
            )
            guard !Task.isCancelled, self.runID == currentRun else { return }

            self.report = report
            self.isRunning = false
            self.phase = .idle
            self.task = nil
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
        phase = .idle
    }

    private func finish(_ currentRun: UUID) {
        guard runID == currentRun else { return }
        isRunning = false
        phase = .idle
        task = nil
    }
}
