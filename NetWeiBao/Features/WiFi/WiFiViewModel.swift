import Combine
import CoreLocation
import Foundation
import NetworkExtension
import UIKit

@MainActor
final class WiFiViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var network: WiFiNetworkInfo?
    @Published private(set) var quality: LinkQuality?
    @Published private(set) var gateway: IPv4Address?
    @Published private(set) var interfaceInfo: NetworkInterface.Info?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let locationManager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.accuracyAuthorization = manager.accuracyAuthorization
        self.interfaceInfo = NetworkInterface.activeIPv4()
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    var isWiFiInterface: Bool {
        interfaceInfo?.name.hasPrefix("en") == true
    }

    var authorizationText: String {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return accuracyAuthorization == .fullAccuracy ? "已授权 · 精确" : "已授权 · 模糊"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限制"
        case .notDetermined:
            return "未请求"
        @unknown default:
            return "未知"
        }
    }

    func refresh() {
        interfaceInfo = NetworkInterface.activeIPv4()
        authorizationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization

        guard isWiFiInterface else {
            errorMessage = "当前没有 WiFi IPv4 接口。WiFi 分析需要连接 Wi-Fi；蜂窝网络下只能看到本机地址。"
            network = nil
            quality = nil
            return
        }

        guard isAuthorized else {
            errorMessage = authorizationStatus == .denied
                ? "定位权限被拒绝。iOS 需要定位权限才能读取当前 WiFi 名称；仍可测量网关质量。"
                : "需要定位权限才能读取当前 WiFi 名称；仍可测量网关质量。"
            if authorizationStatus == .notDetermined {
                requestAuthorization()
            }
            Task { await self.loadQuality() }
            return
        }

        if accuracyAuthorization == .reducedAccuracy {
            requestFullAccuracy()
        }

        fetchCurrentNetwork()
    }

    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestFullAccuracy() {
        guard isAuthorized, accuracyAuthorization == .reducedAccuracy else { return }
        locationManager.requestTemporaryFullAccuracyAuthorization(
            withPurposeKey: "WiFiAnalysis"
        )
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.locationManager.authorizationStatus
            self.accuracyAuthorization = self.locationManager.accuracyAuthorization
            if self.isAuthorized {
                self.fetchCurrentNetwork()
            }
        }
    }

    private func fetchCurrentNetwork() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                guard let network else {
                    self.network = nil
                    self.errorMessage = "无法读取 SSID/BSSID。请确认已连接 WiFi、定位权限为“精确”，并且重签 profile 支持 WiFi Info entitlement。网关质量仍可参考。"
                    await self.loadQuality()
                    return
                }

                self.network = WiFiNetworkInfo(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: network.isSecure,
                    signalStrength: min(max(network.signalStrength, 0), 1),
                    autoJoined: network.didAutoJoin
                )

                await self.loadQuality()
            }
        }
    }

    private func loadQuality() async {
        guard let info = NetworkInterface.activeIPv4() else {
            errorMessage = "当前没有可用的 IPv4 接口。"
            return
        }
        interfaceInfo = info

        guard info.name.hasPrefix("en") else {
            errorMessage = "当前不是 WiFi 连接（\(info.name)），无法分析无线链路。"
            quality = nil
            return
        }

        let gateway = await GatewayDetector.detect(interface: info)
            ?? info.subnet.firstHost
        self.gateway = gateway

        let quality = await LinkSampler.measure(
            target: gateway,
            count: 6,
            interval: 0.15,
            timeout: 0.6
        )
        self.quality = quality
    }
}
