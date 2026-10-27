import Foundation

enum SpeedTestMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case external = "外网"
    case intranet = "内网"

    var id: String { rawValue }
}

enum SpeedTestPhase: Sendable {
    case idle
    case latency
    case download
    case upload
    case analyzing
}

struct SpeedTestNode: Sendable {
    let name: String
    let baseURL: URL
    let referer: String?
}

struct SpeedTestTransfer: Sendable {
    let bytes: Int
    let duration: TimeInterval
    let mbps: Double
}

struct SpeedTestResult: Sendable {
    let mode: SpeedTestMode
    let nodeName: String
    let baseURL: String
    let latency: LinkQuality
    let download: SpeedTestTransfer
    let upload: SpeedTestTransfer
    let startedAt: Date
    let duration: TimeInterval
}

enum SpeedTestError: LocalizedError, Sendable {
    case invalidURL(String)
    case httpStatus(Int)
    case emptyTransfer
    case noLatency
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "测速后端地址无效。请填写完整的 http(s) URL。"
        case .httpStatus(let code):
            return "测速服务器返回 HTTP \(code)。"
        case .emptyTransfer:
            return "测速服务器没有返回有效数据。"
        case .noLatency:
            return "无法连接测速服务器，延迟采样全部失败。"
        case .message(let message):
            return message
        }
    }
}
