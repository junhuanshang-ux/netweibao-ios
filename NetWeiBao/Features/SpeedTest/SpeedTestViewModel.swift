import Combine
import Foundation

@MainActor
final class SpeedTestViewModel: ObservableObject {
    static let defaultExternalURL = "https://laxspeed.sharktech.net/backend"

    @Published var mode: SpeedTestMode = .external
    @Published var provider: SpeedTestProvider = .speedTestCN
    @Published var externalURL = SpeedTestViewModel.defaultExternalURL
    @Published var internalURL = ""
    @Published var downloadMegabytes = 100
    @Published var uploadMegabytes = 50
    @Published private(set) var phase: SpeedTestPhase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var resolvedNodeName: String?
    @Published private(set) var externalResult: SpeedTestResult?
    @Published private(set) var internalResult: SpeedTestResult?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var runID = UUID()

    var currentResult: SpeedTestResult? {
        mode == .external ? externalResult : internalResult
    }

    var activeURL: String {
        if mode == .external, provider == .speedTestCN {
            return ""
        }
        return mode == .external ? externalURL : internalURL
    }

    var nodeName: String {
        if mode == .external {
            if provider == .speedTestCN {
                return resolvedNodeName ?? "测速网 · 自动选择国内节点"
            }
            return externalURL.trimmingCharacters(in: .whitespacesAndNewlines)
                == Self.defaultExternalURL
                ? "洛杉矶 · Sharktech (LibreSpeed)"
                : "自定义外网节点"
        }
        return "内网自定义节点"
    }

    var canStart: Bool {
        if mode == .external, provider == .speedTestCN {
            return true
        }
        return !activeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sizeSummary: String {
        "下载 \(downloadMegabytes) MB · 上传 \(uploadMegabytes) MB · 延迟 5 次"
    }

    var phaseText: String {
        switch phase {
        case .idle:
            return "等待开始"
        case .resolving:
            return "选择测速网节点"
        case .latency:
            return "1/3 延迟采样"
        case .download:
            return "2/3 下载 \(downloadMegabytes) MB"
        case .upload:
            return "3/3 上传 \(uploadMegabytes) MB"
        case .analyzing:
            return "整理结果…"
        }
    }

    func modeChanged() {
        guard !isRunning else { return }
        errorMessage = nil
        resolvedNodeName = nil
        phase = .idle
    }

    func providerChanged() {
        guard !isRunning else { return }
        errorMessage = nil
        resolvedNodeName = nil
        phase = .idle
    }

    func start() {
        guard !isRunning else { return }

        let usesSpeedTestCN = mode == .external && provider == .speedTestCN
        let rawURL = activeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL?

        if usesSpeedTestCN {
            url = nil
        } else {
            guard !rawURL.isEmpty else {
                errorMessage = mode == .intranet
                    ? "内网测速需要填写 LibreSpeed 后端地址，例如 http://192.168.1.10:8080/backend"
                    : "请填写外网测速后端地址"
                return
            }

            guard let parsed = URL(string: rawURL),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  let host = parsed.host
            else {
                errorMessage = "后端地址无效，请填写完整的 http(s) URL。"
                return
            }

            if mode == .external, provider == .libreSpeed,
               host.lowercased().contains("speedtest.cn") {
                errorMessage = "speedtest.cn 不是 LibreSpeed 后端。请选择“测速网”节点，或填写 LibreSpeed 的 .../backend 地址。"
                return
            }
            url = parsed
        }

        errorMessage = nil
        resolvedNodeName = nil
        phase = usesSpeedTestCN ? .resolving : .latency
        isRunning = true
        if mode == .external {
            externalResult = nil
        } else {
            internalResult = nil
        }

        let currentRun = UUID()
        runID = currentRun
        let mode = self.mode
        let fallbackName = nodeName
        let downloadSize = min(max(downloadMegabytes, 1), 1_024)
        let uploadSize = min(max(uploadMegabytes, 1), 1_024)
        let startedAt = Date()

        task = Task { [weak self] in
            guard let self else { return }

            do {
                let node: SpeedTestNode
                if usesSpeedTestCN {
                    do {
                        node = try await SpeedTestCNService.shared.resolveNode()
                        self.resolvedNodeName = node.name
                    } catch {
                        node = SpeedTestNode(
                            name: "测速网解析失败 · 已回退 LibreSpeed",
                            baseURL: URL(string: Self.defaultExternalURL)!,
                            referer: nil
                        )
                        self.resolvedNodeName = "测速网解析失败 · 已回退 LibreSpeed"
                    }
                    guard !Task.isCancelled, self.runID == currentRun else { return }
                    self.phase = .latency
                } else {
                    guard let url else {
                        throw SpeedTestError.invalidURL(rawURL)
                    }
                    node = SpeedTestNode(
                        name: fallbackName,
                        baseURL: url,
                        referer: nil
                    )
                }

                let latency = try await SpeedTestService.shared.measureLatency(
                    node: node,
                    count: 5
                )
                guard !Task.isCancelled, self.runID == currentRun else { return }

                self.phase = .download
                let download = try await SpeedTestService.shared.download(
                    node: node,
                    megabytes: downloadSize
                )
                guard !Task.isCancelled, self.runID == currentRun else { return }

                self.phase = .upload
                let upload = try await SpeedTestService.shared.upload(
                    node: node,
                    megabytes: uploadSize
                )
                guard !Task.isCancelled, self.runID == currentRun else { return }

                self.phase = .analyzing
                let result = SpeedTestResult(
                    mode: mode,
                    nodeName: node.name,
                    baseURL: node.baseURL.absoluteString,
                    latency: latency,
                    download: download,
                    upload: upload,
                    startedAt: startedAt,
                    duration: Date().timeIntervalSince(startedAt)
                )

                if mode == .external {
                    self.externalResult = result
                } else {
                    self.internalResult = result
                }
            } catch is CancellationError {
                // User stopped the test; no error banner.
            } catch {
                if !Task.isCancelled, self.runID == currentRun {
                    self.errorMessage = error.localizedDescription
                }
            }

            guard self.runID == currentRun else { return }
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
}
