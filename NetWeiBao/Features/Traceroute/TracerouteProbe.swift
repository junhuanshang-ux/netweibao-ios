import Darwin
import Dispatch
import Foundation

enum TracerouteProbe {
    private static let queue = DispatchQueue(
        label: "com.netweibao.traceroute",
        qos: .userInitiated
    )

    static func probe(
        target: IPv4Address,
        ttl: Int,
        attempts: Int = 1,
        timeout: TimeInterval = 0.8
    ) async -> TracerouteHop {
        let boundedTTL = min(max(ttl, 1), 64)
        let boundedAttempts = min(max(attempts, 1), 3)
        let boundedTimeout = min(max(timeout, 0.2), 3.0)

        return await withCheckedContinuation { (continuation: CheckedContinuation<TracerouteHop, Never>) in
            queue.async {
                continuation.resume(
                    returning: perform(
                        target: target,
                        ttl: boundedTTL,
                        attempts: boundedAttempts,
                        timeout: boundedTimeout
                    )
                )
            }
        }
    }

    private static func perform(
        target: IPv4Address,
        ttl: Int,
        attempts: Int,
        timeout: TimeInterval
    ) -> TracerouteHop {
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fileDescriptor >= 0 else {
            return TracerouteHop(
                ttl: ttl,
                address: nil,
                latency: nil,
                status: .timeout
            )
        }
        defer { _ = close(fileDescriptor) }

        InterfaceBinder.bind(fileDescriptor, to: NetworkInterfaceSelection.shared.selectedName)

        var ttlValue = Int32(ttl)
        _ = setsockopt(
            fileDescriptor,
            IPPROTO_IP,
            IP_TTL,
            &ttlValue,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var receiveBuffer: Int32 = 256 * 1024
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBuffer,
            socklen_t(MemoryLayout<Int32>.size)
        )

        let identifier = UInt16.random(in: 1...UInt16.max)
        var buffer = [UInt8](repeating: 0, count: 2_048)

        for attempt in 0..<attempts {
            let sequence = UInt16(attempt + 1)
            let packet = ICMPPacket.echoRequest(
                identifier: identifier,
                sequence: sequence,
                payloadSize: 32
            )
            var destination = target.sockaddr
            let startedAt = DispatchTime.now().uptimeNanoseconds

            let sentBytes = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
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
            guard sentBytes >= 0 else { continue }

            let deadline = startedAt + UInt64(timeout * 1_000_000_000)

            while true {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline else { break }

                let remaining = deadline - now
                let waitMilliseconds = Int32(min(120, max(1, remaining / 1_000_000)))

                var pollDescriptor = pollfd(
                    fd: fileDescriptor,
                    events: Int16(POLLIN),
                    revents: 0
                )
                let pollResult = poll(&pollDescriptor, 1, waitMilliseconds)

                if pollResult == 0 { continue }
                if pollResult < 0 {
                    if errno == EINTR { continue }
                    break
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
                    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                        continue
                    }
                    break
                }
                guard receivedBytes > 0 else { continue }

                let data = Array(buffer[0..<Int(receivedBytes)])
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000.0
                let sourceAddress = IPv4Address(
                    value: UInt32(bigEndian: source.sin_addr.s_addr)
                )

                if let reply = ICMPPacket.echoReplyInfo(data, length: Int(receivedBytes)),
                   reply.identifier == identifier,
                   reply.sequence == sequence {
                    return TracerouteHop(
                        ttl: ttl,
                        address: target,
                        latency: elapsed,
                        status: .target
                    )
                }

                if let quoted = ICMPPacket.timeExceededInfo(data, length: Int(receivedBytes)),
                   quoted.identifier == identifier,
                   quoted.sequence == sequence {
                    return TracerouteHop(
                        ttl: ttl,
                        address: sourceAddress.value == 0 ? nil : sourceAddress,
                        latency: elapsed,
                        status: .hop
                    )
                }

                if let quoted = ICMPPacket.destinationUnreachableInfo(data, length: Int(receivedBytes)),
                   quoted.identifier == identifier,
                   quoted.sequence == sequence {
                    return TracerouteHop(
                        ttl: ttl,
                        address: sourceAddress.value == 0 ? target : sourceAddress,
                        latency: elapsed,
                        status: .unreachable
                    )
                }
            }
        }

        return TracerouteHop(
            ttl: ttl,
            address: nil,
            latency: nil,
            status: .timeout
        )
    }
}
