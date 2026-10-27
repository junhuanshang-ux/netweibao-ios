import Foundation

final class SpeedTestService: @unchecked Sendable {
    static let shared = SpeedTestService()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    func measureLatency(
        node: SpeedTestNode,
        count: Int = 5
    ) async throws -> LinkQuality {
        let total = max(1, count)
        var latencies: [Double] = []
        var received = 0
        var errors = 0

        for _ in 0..<total {
            try Task.checkCancellation()

            do {
                let latency = try await latencySample(node: node)
                latencies.append(latency)
                received += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors += 1
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard received > 0 else {
            throw SpeedTestError.noLatency
        }

        return LinkQuality(
            sent: total,
            received: received,
            timeouts: errors,
            latencies: latencies
        )
    }

    func download(
        node: SpeedTestNode,
        megabytes: Int = 100
    ) async throws -> SpeedTestTransfer {
        let size = max(1, megabytes)
        let url = try makeURL(
            node: node,
            path: "garbage.php",
            query: [
                URLQueryItem(name: "ckSize", value: "\(size)")
            ]
        )
        var request = makeRequest(url: url, node: node, method: "GET")
        request.timeoutInterval = 300

        try Task.checkCancellation()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let (fileURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try validate(response)
        let bytes = fileSize(at: fileURL)
        guard bytes > 0 else { throw SpeedTestError.emptyTransfer }

        return makeTransfer(bytes: bytes, startedAt: startedAt)
    }

    func upload(
        node: SpeedTestNode,
        megabytes: Int = 50
    ) async throws -> SpeedTestTransfer {
        let size = max(1, megabytes)
        let url = try makeURL(
            node: node,
            path: "empty.php",
            query: []
        )
        var request = makeRequest(url: url, node: node, method: "POST")
        request.timeoutInterval = 300
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let body = Data(repeating: 0x5A, count: size * 1_024 * 1_024)

        try Task.checkCancellation()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let (_, response) = try await session.upload(for: request, from: body)
        try validate(response)

        return makeTransfer(bytes: body.count, startedAt: startedAt)
    }

    private func latencySample(node: SpeedTestNode) async throws -> Double {
        let url = try makeURL(node: node, path: "empty.php", query: [])
        let request = makeRequest(url: url, node: node, method: "GET")

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let (_, response) = try await session.data(for: request)
        try validate(response)
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return Double(elapsed) / 1_000_000.0
    }

    private func makeURL(
        node: SpeedTestNode,
        path: String,
        query: [URLQueryItem]
    ) throws -> URL {
        let endpoint = node.baseURL.appendingPathComponent(path)
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw SpeedTestError.invalidURL(endpoint.absoluteString)
        }

        var items = query
        items.append(URLQueryItem(name: "r", value: UUID().uuidString))
        components.queryItems = items

        guard let url = components.url else {
            throw SpeedTestError.invalidURL(endpoint.absoluteString)
        }
        return url
    }

    private func makeRequest(
        url: URL,
        node: SpeedTestNode,
        method: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer(for: node), forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private func referer(for node: SpeedTestNode) -> String {
        if let referer = node.referer {
            return referer
        }
        guard var components = URLComponents(
            url: node.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return node.baseURL.absoluteString
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? node.baseURL.absoluteString
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SpeedTestError.message("测速服务器响应无效。")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SpeedTestError.httpStatus(http.statusCode)
        }
    }

    private func fileSize(at url: URL) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }

    private func makeTransfer(bytes: Int, startedAt: UInt64) -> SpeedTestTransfer {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        let seconds = max(Double(elapsed) / 1_000_000_000.0, 0.001)
        let mbps = Double(bytes) * 8.0 / seconds / 1_000_000.0
        return SpeedTestTransfer(bytes: bytes, duration: seconds, mbps: mbps)
    }
}
