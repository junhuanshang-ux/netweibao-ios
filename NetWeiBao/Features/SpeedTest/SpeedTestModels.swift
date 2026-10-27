import Foundation

enum SpeedTestMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case external = "外网"
    case intranet = "内网"

    var id: String { rawValue }
}

enum SpeedTestPhase: Sendable {
    case idle
    case resolving
    case latency
    case download
    case upload
    case analyzing
}

enum SpeedTestProvider: String, CaseIterable, Identifiable, Hashable, Sendable {
    case speedTestCN = "测速网"
    case libreSpeed = "LibreSpeed"

    var id: String { rawValue }
}

struct SpeedTestNode: Sendable {
    let name: String
    let baseURL: URL
    let downloadPath: String
    let uploadPath: String
    let pingPath: String
    let downloadSizeParameter: String
    let maxDownloadMegabytesPerRequest: Int?
    let maxUploadMegabytesPerRequest: Int?
    let referer: String?

    init(
        name: String,
        baseURL: URL,
        referer: String? = nil
    ) {
        self.name = name
        self.baseURL = baseURL
        self.downloadPath = "garbage.php"
        self.uploadPath = "empty.php"
        self.pingPath = "empty.php"
        self.downloadSizeParameter = "ckSize"
        self.maxDownloadMegabytesPerRequest = nil
        self.maxUploadMegabytesPerRequest = nil
        self.referer = referer
    }

    init(
        name: String,
        baseURL: URL,
        downloadPath: String,
        uploadPath: String,
        pingPath: String,
        downloadSizeParameter: String,
        maxDownloadMegabytesPerRequest: Int? = nil,
        maxUploadMegabytesPerRequest: Int? = nil,
        referer: String?
    ) {
        self.name = name
        self.baseURL = baseURL
        self.downloadPath = downloadPath
        self.uploadPath = uploadPath
        self.pingPath = pingPath
        self.downloadSizeParameter = downloadSizeParameter
        self.maxDownloadMegabytesPerRequest = maxDownloadMegabytesPerRequest
        self.maxUploadMegabytesPerRequest = maxUploadMegabytesPerRequest
        self.referer = referer
    }
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
