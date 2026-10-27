import Combine
import Foundation

@MainActor
final class DHCPViewModel: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var result: DHCPDiscoveryResult?
    @Published private(set) var localInfo: NetworkInterface.Info? = NetworkInterface.activeIPv4()
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var broadcastPreview: String {
        localInfo?.subnet.broadcast.description ?? "255.255.255.255"
    }

    func refreshInterface() {
        localInfo = NetworkInterface.activeIPv4()
    }

    func start() {
        guard !isScanning else { return }

        refreshInterface()
        errorMessage = nil
        result = nil
        isScanning = true

        task = Task { [weak self] in
            let discovery = await DHCPProbeService.shared.discover(timeout: 4.0)
            guard !Task.isCancelled, let self else { return }

            self.result = discovery
            self.isScanning = false
            if let error = discovery.errorMessage {
                self.errorMessage = error
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }
}
