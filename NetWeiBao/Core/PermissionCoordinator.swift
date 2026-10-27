import CoreLocation
import Foundation
import Network
import UIKit

enum LocalNetworkPermissionStatus: Sendable, Equatable {
    case unknown
    case requesting
    case authorized
    case denied
}

@MainActor
final class PermissionCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var locationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var localNetworkStatus: LocalNetworkPermissionStatus = .unknown

    private let locationManager: CLLocationManager
    private var browser: NWBrowser?
    private let requestedKey = "NetWeiBao.permissions.requested.v1"

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.locationStatus = manager.authorizationStatus
        self.accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
    }

    var isLocationAuthorized: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }

    var locationText: String {
        switch locationStatus {
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

    var localNetworkText: String {
        switch localNetworkStatus {
        case .unknown:
            return "待确认"
        case .requesting:
            return "请求中"
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        }
    }

    /// Called once from the first screen. iOS can only show its own permission
    /// prompts; this starts the location request and a short Bonjour browse to
    /// trigger the Local Network prompt.
    func requestAtLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: requestedKey) else { return }
        defaults.set(true, forKey: requestedKey)
        requestAll()
    }

    func requestAll() {
        requestLocation()
        requestLocalNetwork()
    }

    func requestLocation() {
        locationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization

        if locationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if isLocationAuthorized, accuracyAuthorization == .reducedAccuracy {
            locationManager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: "WiFiAnalysis"
            )
        }
    }

    func requestLocalNetwork() {
        guard browser == nil else { return }

        localNetworkStatus = .requesting
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: "_http._tcp", domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.localNetworkStatus = .authorized
                case .failed:
                    self.localNetworkStatus = .denied
                case .cancelled:
                    if self.localNetworkStatus == .requesting {
                        self.localNetworkStatus = .unknown
                    }
                default:
                    break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.locationStatus = self.locationManager.authorizationStatus
            self.accuracyAuthorization = self.locationManager.accuracyAuthorization

            if self.isLocationAuthorized,
               self.accuracyAuthorization == .reducedAccuracy {
                self.locationManager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: "WiFiAnalysis"
                )
            }
        }
    }
}
