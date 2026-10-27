import Combine
import Foundation
import Network
import UIKit

@MainActor
final class NetworkHomeViewModel: ObservableObject {
    @Published private(set) var interfaces: [NetworkInterfaceSnapshot] = []
    @Published private(set) var selectedName: String? = nil
    @Published private(set) var gateway: IPv4Address? = nil
    @Published private(set) var dnsServers: [String] = []
    @Published private(set) var pathStatus: NWPath.Status = .requiresConnection
    @Published private(set) var usesWiFi = false
    @Published private(set) var usesCellular = false
    @Published private(set) var usesWired = false
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false

    let hostName = ProcessInfo.processInfo.hostName
    let systemName = UIDevice.current.systemName
    let systemVersion = UIDevice.current.systemVersion
    let deviceModel = UIDevice.current.model

    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.netweibao.path-monitor")
    private var timer: Timer?
    private var gatewayTask: Task<Void, Never>?
    private var usesSystemDefault = false

    init() {
        refresh()
        if let saved = NetworkInterfaceSelection.shared.selectedName,
           interfaces.contains(where: {
               $0.name == saved
                   && !$0.ipv4Addresses.isEmpty
                   && $0.type != .loopback
           }) {
            selectedName = saved
        } else {
            selectedName = preferredInterface()?.name
        }
        applySelection()
    }

    var selectedInterface: NetworkInterfaceSnapshot? {
        guard let selectedName else { return nil }
        return interfaces.first(where: { $0.name == selectedName })
    }

    var pathText: String {
        guard pathStatus == .satisfied else { return "无网络" }
        if usesWiFi { return "Wi-Fi" }
        if usesCellular { return "蜂窝网络" }
        if usesWired { return "有线网络" }
        return "已连接"
    }

    var pathDetail: String {
        var items: [String] = []
        if isExpensive { items.append("计费网络") }
        if isConstrained { items.append("低数据模式") }
        return items.isEmpty ? "系统路由正常" : items.joined(separator: " · ")
    }

    func start() {
        monitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path)
            }
        }
        monitor.start(queue: monitorQueue)
        self.monitor = monitor

        refresh()
        detectGateway()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        timer?.invalidate()
        timer = nil
        gatewayTask?.cancel()
        gatewayTask = nil
    }

    func refresh() {
        interfaces = NetworkInterfaceCatalog.snapshot()
        dnsServers = DNSConfiguration.servers()

        if let selectedName,
           !interfaces.contains(where: { $0.name == selectedName }) {
            self.selectedName = preferredInterface()?.name
            applySelection()
        } else if selectedName == nil, !usesSystemDefault {
            selectedName = preferredInterface()?.name
            applySelection()
        }
    }

    func select(_ interface: NetworkInterfaceSnapshot) {
        guard !interface.ipv4Addresses.isEmpty,
              interface.type != .loopback
        else {
            return
        }
        usesSystemDefault = false
        selectedName = interface.name
        applySelection()
        detectGateway()
    }

    func useSystemDefault() {
        usesSystemDefault = true
        selectedName = nil
        NetworkInterfaceSelection.shared.selectedName = nil
        gateway = nil
    }

    func detectGateway() {
        gatewayTask?.cancel()
        gateway = nil

        guard let selectedInterface,
              let info = NetworkInterface.allIPv4().first(where: {
                  $0.name == selectedInterface.name
              })
        else {
            return
        }

        gatewayTask = Task { [weak self] in
            let detected = await GatewayDetector.detect(interface: info)
            guard !Task.isCancelled, let self else { return }
            self.gateway = detected ?? info.subnet.firstHost
        }
    }

    private func applySelection() {
        NetworkInterfaceSelection.shared.selectedName = selectedName
    }

    private func preferredInterface() -> NetworkInterfaceSnapshot? {
        interfaces.first { $0.name == "en0" && !$0.ipv4Addresses.isEmpty }
            ?? interfaces.first { !$0.ipv4Addresses.isEmpty && $0.type != .loopback }
            ?? interfaces.first { !$0.ipv4Addresses.isEmpty }
    }

    private func apply(_ path: NWPath) {
        pathStatus = path.status
        usesWiFi = path.usesInterfaceType(.wifi)
        usesCellular = path.usesInterfaceType(.cellular)
        usesWired = path.usesInterfaceType(.wiredEthernet)
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        refresh()
    }
}
