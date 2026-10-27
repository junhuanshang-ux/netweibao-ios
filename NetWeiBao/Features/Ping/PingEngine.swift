import Darwin
import Dispatch
import Foundation

/// Unprivileged ICMP echo engine built on `SOCK_DGRAM` + `IPPROTO_ICMP`.
/// A bounded operation queue keeps /24 scans from exhausting file descriptors or threads.
final class PingEngine: @unchecked Sendable {
    static let shared = PingEngine()

    private let identifier: UInt16
    private let sequenceLock = NSLock()
    private var sequence: UInt16 = 0

    private let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.netweibao.ping.io"
        queue.maxConcurrentOperationCount = 32
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init() {
        self.identifier = UInt16.random(in: 1...UInt16.max)
    }

    func ping(
        _ address: IPv4Address,
        timeout: TimeInterval = 1.0,
        payloadSize: Int = 32
    ) async -> PingOutcome {
        let sequence = nextSequence()
        let identifier = self.identifier
        let boundedTimeout = min(max(timeout, 0.1), 10)
        let boundedPayload = min(max(payloadSize, 0), 1400)

        return await withCheckedContinuation { (continuation: CheckedContinuation<PingOutcome, Never>) in
            ioQueue.addOperation {
                let outcome = Self.performPing(
                    address: address,
                    identifier: identifier,
                    sequence: sequence,
                    timeout: boundedTimeout,
                    payloadSize: boundedPayload
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    private func nextSequence() -> UInt16 {
        sequenceLock.lock()
        defer { sequenceLock.unlock() }

        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        return sequence
    }

    // MARK: - Blocking probe

    private static func performPing(
        address: IPv4Address,
        identifier: UInt16,
        sequence: UInt16,
        timeout: TimeInterval,
        payloadSize: Int
    ) -> PingOutcome {
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fileDescriptor >= 0 else {
            return .failure("无法创建 ICMP 套接字：\(posixMessage(errno))")
        }
        defer { _ = close(fileDescriptor) }

        var receiveBuffer: Int32 = 512 * 1024
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBuffer,
            socklen_t(MemoryLayout<Int32>.size)
        )

        let packet = ICMPPacket.echoRequest(
            identifier: identifier,
            sequence: sequence,
            payloadSize: payloadSize
        )
        var destination = address.sockaddr
        let startedAt = DispatchTime.now().uptimeNanoseconds

        let sentBytes = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { destinationPointer in
                destinationPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        fileDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard sentBytes >= 0 else {
            let code = errno
            if code == EACCES || code == EPERM {
                return .failure("本地网络权限被拒绝，请在系统设置中允许访问本地网络")
            }
            if code == EHOSTUNREACH || code == ENETUNREACH {
                return .unreachable("目标网络不可达")
            }
            return .failure("发送失败：\(posixMessage(code))")
        }

        let deadline = startedAt + UInt64(timeout * 1_000_000_000)
        var buffer = [UInt8](repeating: 0, count: 2048)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return .timeout }

            let remaining = deadline - now
            let waitMilliseconds = Int32(min(250, max(1, remaining / 1_000_000)))

            var pollDescriptor = pollfd(
                fd: fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let pollResult = poll(&pollDescriptor, 1, waitMilliseconds)

            if pollResult == 0 { continue }
            if pollResult < 0 {
                if errno == EINTR { continue }
                return .failure("等待响应失败：\(posixMessage(errno))")
            }

            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let receivedBytes = withUnsafeMutablePointer(to: &source) { sourcePointer in
                sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    buffer.withUnsafeMutableBytes { rawBuffer in
                        recvfrom(
                            fileDescriptor,
                            rawBuffer.baseAddress,
                            rawBuffer.count,
                            0,
                            socketAddress,
                            &sourceLength
                        )
                    }
                }
            }

            if receivedBytes < 0 {
                let code = errno
                if code == EINTR || code == EAGAIN || code == EWOULDBLOCK { continue }
                if code == ECONNREFUSED { return .unreachable("目标拒绝连接（可能不在线）") }
                if code == EHOSTUNREACH || code == ENETUNREACH {
                    return .unreachable("目标网络不可达")
                }
                if code == EACCES || code == EPERM {
                    return .failure("本地网络权限被拒绝，请在系统设置中允许访问本地网络")
                }
                return .failure("接收失败：\(posixMessage(code))")
            }

            guard receivedBytes >= 8 else { continue }

            let sourceAddress = IPv4Address(
                value: UInt32(bigEndian: source.sin_addr.s_addr)
            )
            guard sourceAddress == address else { continue }

            if ICMPPacket.isEchoReply(
                buffer,
                length: receivedBytes,
                identifier: identifier,
                sequence: sequence
            ) {
                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
                let latency = Double(elapsed) / 1_000_000.0
                return .reply(latencyMs: latency, ttl: nil)
            }
        }
    }

    private static func posixMessage(_ code: Int32) -> String {
        guard let message = strerror(code) else { return "errno \(code)" }
        return String(cString: message)
    }
}

private enum ICMPPacket {
    static func echoRequest(
        identifier: UInt16,
        sequence: UInt16,
        payloadSize: Int
    ) -> [UInt8] {
        let size = max(0, payloadSize)
        var bytes = [UInt8](repeating: 0, count: 8 + size)
        bytes[0] = 8
        bytes[1] = 0
        bytes[4] = UInt8(identifier >> 8)
        bytes[5] = UInt8(identifier & 0xFF)
        bytes[6] = UInt8(sequence >> 8)
        bytes[7] = UInt8(sequence & 0xFF)

        for index in 8..<bytes.count {
            bytes[index] = UInt8(truncatingIfNeeded: index)
        }

        let checksum = checksum(bytes)
        bytes[2] = UInt8(checksum >> 8)
        bytes[3] = UInt8(checksum & 0xFF)
        return bytes
    }

    static func isEchoReply(
        _ bytes: [UInt8],
        length: Int,
        identifier: UInt16,
        sequence: UInt16
    ) -> Bool {
        guard length >= 8, bytes.count >= length else { return false }

        var offset = 0
        if length >= 20, bytes[0] >> 4 == 4 {
            let headerLength = Int(bytes[0] & 0x0F) * 4
            if headerLength >= 20, length >= headerLength + 8 {
                offset = headerLength
            }
        }

        guard length >= offset + 8 else { return false }
        guard bytes[offset] == 0, bytes[offset + 1] == 0 else { return false }

        let replyIdentifier = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
        let replySequence = UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7])
        return replyIdentifier == identifier && replySequence == sequence
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0

        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }

        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return UInt16(~sum & 0xFFFF)
    }
}
