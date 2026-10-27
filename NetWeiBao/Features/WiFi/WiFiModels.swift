import Foundation

struct WiFiNetworkInfo: Sendable {
    let ssid: String
    let bssid: String
    let isSecure: Bool
    let signalStrength: Double
    let autoJoined: Bool
}
