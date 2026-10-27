import Foundation

struct WiFiNetworkInfo: Sendable {
    let ssid: String
    let bssid: String
    let isSecure: Bool
    let signalStrength: Double
    let autoJoined: Bool

    /// iOS frequently returns 0 even when the link is healthy. Treat 0 as
    /// "unknown" instead of displaying a misleading 0% / weak signal.
    var hasSignalStrength: Bool {
        signalStrength.isFinite && signalStrength > 0.01
    }

    var signalPercent: Int? {
        guard hasSignalStrength else { return nil }
        return Int((min(max(signalStrength, 0), 1) * 100).rounded())
    }

    var signalLabel: String {
        guard let signalPercent else { return "系统未提供" }
        if signalPercent >= 66 { return "强" }
        if signalPercent >= 33 { return "中" }
        return "弱"
    }

    var signalText: String {
        guard let signalPercent else { return "系统未提供" }
        return "\(signalPercent)% · \(signalLabel)"
    }
}
