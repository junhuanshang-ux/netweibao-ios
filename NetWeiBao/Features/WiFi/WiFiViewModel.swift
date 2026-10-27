import Combine
import CoreLocation
import Foundation
import NetworkExtension
import UIKit

@MainActor
final class WiFiViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var network: WiFiNetworkInfo?
    @Published private(set) var quality: LinkQuality?
    @Published private(set) var gateway: IPv4Address?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let locationManager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    var authorizationText: String {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "已授权"
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
        authorizationStatus = locationManager.authorizationStatus

        guard isAuthorized else {
            errorMessage = authorizationStatus == .denied
                ? "定位权限被拒绝。iOS 需要定位权限才能读取当前 WiFi 名称。"
                : "需要定位权限才能读取当前 WiFi 名称。"
            if authorizationStatus == .notDetermined {
                requestAuthorization()
            }
            return
        }

        fetchCurrentNetwork()
    }

    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            fetchCurrentNetwork()
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
                    self.errorMessage = "无法读取当前 WiFi。请确认已连接 WiFi、定位权限已允许，并且 WiFi Info entitlement 已生效。模拟器通常无法返回 SSID。"
                    return
                }

                self.network = WiFiNetworkInfo(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: network.isSecure,
                    signalStrength: min(max(network.signalStrength, 0), 1),
                    autoJoined: network.autoJoined
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
