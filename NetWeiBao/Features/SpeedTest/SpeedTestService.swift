import Foundation
import Network

final class SpeedTestService: @unchecked Sendable {
    static let shared = SpeedTestService()

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private let queue = DispatchQueue(label: "com.netweibao.speedtest.transport")

    private init() {}

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
                latencies.append(try await latencySample(node: node))
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
            query: [URLQueryItem(name: "ckSize", value: "\(size)")]
        )
        let host = try connectionHost(for: url)
        let connection = makeConnection(host: host, url: url)
        let timeoutTask = startTimeout(seconds: 300, connection: connection)
        defer {
            timeoutTask.cancel()
            connection.cancel()
        }

        try await waitForReady(connection)
        let request = makeRequest(url: url, node: node, method: "GET", contentLength: nil)
        try await send(request, on: connection, isComplete: true)

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let response = try await readHeaders(on: connection)
        try validate(status: response.status)

        var bodyBytes = response.bodyPrefix.count
        var isComplete = response.isComplete
        while !isComplete {
            try Task.checkCancellation()
            let chunk = try await receive(on: connection)
            bodyBytes += chunk.data.count
            isComplete = chunk.isComplete
        }

        guard bodyBytes > 0 else { throw SpeedTestError.emptyTransfer }
        return makeTransfer(bytes: bodyBytes, startedAt: startedAt)
    }

    func upload(
        node: SpeedTestNode,
        megabytes: Int = 50
    ) async throws -> SpeedTestTransfer {
        let size = max(1, megabytes)
        let url = try makeURL(node: node, path: "empty.php", query: [])
        let host = try connectionHost(for: url)
        let body = Data(repeating: 0x5A, count: size * 1_024 * 1_024)

        let connection = makeConnection(host: host, url: url)
        let timeoutTask = startTimeout(seconds: 300, connection: connection)
        defer {
            timeoutTask.cancel()
            connection.cancel()
        }

        try await waitForReady(connection)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let header = makeRequest(
            url: url,
            node: node,
            method: "POST",
            contentLength: body.count
        )
        try await send(header, on: connection, isComplete: false)

        let chunkSize = 1_024 * 1_024
        var offset = 0
        while offset < body.count {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, body.count)
            let chunk = body.subdata(in: offset..<end)
            try await send(chunk, on: connection, isComplete: end == body.count)
            offset = end
        }

        let response = try await readHeaders(on: connection)
        try validate(status: response.status)
        return makeTransfer(bytes: body.count, startedAt: startedAt)
    }

    private func latencySample(node: SpeedTestNode) async throws -> Double {
        let url = try makeURL(node: node, path: "empty.php", query: [])
        let host = try connectionHost(for: url)
        let connection = makeConnection(host: host, url: url)
        let timeoutTask = startTimeout(seconds: 10, connection: connection)
        defer {
            timeoutTask.cancel()
            connection.cancel()
        }

        try await waitForReady(connection)
        let request = makeRequest(url: url, node: node, method: "GET", contentLength: nil)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        try await send(request, on: connection, isComplete: true)
        let response = try await readHeaders(on: connection)
        try validate(status: response.status)
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return Double(elapsed) / 1_000_000.0
    }

    // MARK: - HTTP over NWConnection

    private struct HTTPHeaders {
        let status: Int
        let bodyPrefix: Data
        let isComplete: Bool
    }

    private func readHeaders(on connection: NWConnection) async throws -> HTTPHeaders {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)

        while true {
            try Task.checkCancellation()
            let chunk = try await receive(on: connection)
            buffer.append(chunk.data)

            if let range = buffer.range(of: separator) {
                let head = String(
                    data: buffer[..<range.lowerBound],
                    encoding: .utf8
                ) ?? ""
                let status = try parseStatus(head)
                let body = Data(buffer[range.upperBound...])
                return HTTPHeaders(
                    status: status,
                    bodyPrefix: body,
                    isComplete: chunk.isComplete
                )
            }

            if chunk.isComplete {
                throw SpeedTestError.message("测速服务器提前关闭连接。")
            }
            if buffer.count > 64 * 1_024 {
                throw SpeedTestError.message("测速服务器响应头异常。")
            }
        }
    }

    private func parseStatus(_ headers: String) throws -> Int {
        guard let firstLine = headers.components(separatedBy: "\r\n").first else {
            throw SpeedTestError.message("测速服务器响应无效。")
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw SpeedTestError.message("测速服务器响应无效。")
        }
        return status
    }

    private func validate(status: Int) throws {
        guard (200...299).contains(status) else {
            throw SpeedTestError.httpStatus(status)
        }
    }

    private func makeConnection(host: String, url: URL) -> NWConnection {
        let parameters: NWParameters = url.scheme?.lowercased() == "http" ? .tcp : .tls
        parameters.includePeerToPeer = false

        if let interfaceName = NetworkInterfaceSelection.shared.selectedName,
           let interfaceType = requiredInterfaceType(named: interfaceName) {
            parameters.requiredInterfaceType = interfaceType
        }

        let port = url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 443
        return NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: parameters
        )
    }

    private func requiredInterfaceType(named name: String) -> NWInterface.InterfaceType? {
        switch NetworkInterfaceCatalog.interfaceType(for: name) {
        case .wifi:
            return .wifi
        case .ethernet:
            return .wiredEthernet
        case .cellular:
            return .cellular
        case .loopback:
            return .loopback
        default:
            return .other
        }
    }

    private func connectionHost(for url: URL) throws -> String {
        guard let host = url.host, !host.isEmpty else {
            throw SpeedTestError.invalidURL(url.absoluteString)
        }
        return host
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.run { continuation.resume() }
                case .failed(let error):
                    gate.run { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.run {
                        continuation.resume(
                            throwing: SpeedTestError.message("测速连接已取消。")
                        )
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func startTimeout(seconds: TimeInterval, connection: NWConnection) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
            connection.cancel()
        }
    }

    private func send(
        _ data: Data,
        on connection: NWConnection,
        isComplete: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: isComplete,
                completion: .contentProcessed { error in
                    if let error {
                        gate.run { continuation.resume(throwing: error) }
                    } else {
                        gate.run { continuation.resume() }
                    }
                }
            )
        }
    }

    private func receive(on connection: NWConnection) async throws -> (data: Data, isComplete: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 256 * 1_024
            ) { data, _, isComplete, error in
                if let error {
                    gate.run { continuation.resume(throwing: error) }
                } else {
                    gate.run {
                        continuation.resume(returning: (data ?? Data(), isComplete))
                    }
                }
            }
        }
    }

    // MARK: - Request construction

    private func makeRequest(
        url: URL,
        node: SpeedTestNode,
        method: String,
        contentLength: Int?
    ) -> Data {
        let hostHeader: String
        let defaultPort = url.scheme?.lowercased() == "http" ? 80 : 443
        if let port = url.port, port != defaultPort {
            hostHeader = "\(url.host ?? ""):\(port)"
        } else {
            hostHeader = url.host ?? ""
        }

        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }

        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "User-Agent: \(userAgent)",
            "Referer: \(referer(for: node))",
            "Accept: */*",
            "Connection: close"
        ]
        if let contentLength {
            lines.append("Content-Type: application/octet-stream")
            lines.append("Content-Length: \(contentLength)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
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

    private func makeTransfer(bytes: Int, startedAt: UInt64) -> SpeedTestTransfer {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        let seconds = max(Double(elapsed) / 1_000_000_000.0, 0.001)
        let mbps = Double(bytes) * 8.0 / seconds / 1_000_000.0
        return SpeedTestTransfer(bytes: bytes, duration: seconds, mbps: mbps)
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        action()
    }
}
