import Darwin
import Dispatch
import Foundation

/// Read-only DHCP discovery. Sends a single DHCPDISCOVER and collects OFFERs.
/// No lease is requested or held, so the scan does not take an address from the pool.
final class DHCPProbeService: @unchecked Sendable {
    static let shared = DHCPProbeService()

    private let queue = DispatchQueue(label: "com.netweibao.dhcp", qos: .userInitiated)
    private let clientMAC: [UInt8] = DHCPProbeService.makeClientMAC()

    private init() {}

    func discover(timeout: TimeInterval = 4.0) async -> DHCPDiscoveryResult {
        let boundedTimeout = min(max(timeout, 1.0), 10.0)

        return await withCheckedContinuation { (continuation: CheckedContinuation<DHCPDiscoveryResult, Never>) in
            queue.async {
                continuation.resume(returning: self.performDiscover(timeout: boundedTimeout))
            }
        }
    }

    private func performDiscover(timeout: TimeInterval) -> DHCPDiscoveryResult {
        let startedAt = Date()
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start + UInt64(timeout * 1_000_000_000)
        let retryAt = start + 1_200_000_000

        let interface = NetworkInterface.activeIPv4()
        var warnings: [String] = []
        if interface == nil {
            warnings.append("未识别到本机 IPv4 接口，仍尝试向 255.255.255.255 发送 DISCOVER。")
        }

        let destinations = Self.broadcastDestinations(interface: interface)
        let fileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fileDescriptor >= 0 else {
            return Self.failureResult(
                message: "无法创建 UDP 套接字：\(Self.posixMessage(errno))",
                startedAt: startedAt,
                interface: interface,
                destinations: destinations,
                warnings: warnings
            )
        }
        defer { _ = close(fileDescriptor) }

        Self.configureSocket(fileDescriptor)

        var boundPort: UInt16?
        if Self.bindSocket(fileDescriptor, port: 68) {
            boundPort = 68
        } else {
            let primaryError = errno
            warnings.append(
                "无法绑定 UDP 68（\(Self.posixMessage(primaryError))），已改用临时端口。多数 DHCP 服务器只向 68 端口回复，可能收不到 OFFER。"
            )

            if Self.bindSocket(fileDescriptor, port: 0), let ephemeralPort = Self.boundPort(fileDescriptor) {
                boundPort = ephemeralPort
            } else {
                let fallbackError = errno
                return Self.failureResult(
                    message: "无法绑定 DHCP 客户端端口：\(Self.posixMessage(fallbackError))",
                    startedAt: startedAt,
                    interface: interface,
                    destinations: destinations,
                    warnings: warnings
                )
            }
        }

        let xid = UInt32.random(in: 1...UInt32.max)
        let packet = DHCPDiscoverBuilder.makePacket(xid: xid, mac: clientMAC)

        func sendDiscover() {
            for destination in destinations {
                if let code = Self.send(
                    packet: packet,
                    to: destination,
                    socket: fileDescriptor
                ) {
                    warnings.append("发送到 \(destination):67 失败：\(Self.posixMessage(code))")
                }
            }
        }

        sendDiscover()
        var retrySent = false
        var offersByServer: [String: DHCPOffer] = [:]
        var buffer = [UInt8](repeating: 0, count: 2_048)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }

            if !retrySent, now >= retryAt {
                retrySent = true
                sendDiscover()
            }

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
                warnings.append("等待 DHCP 响应失败：\(Self.posixMessage(errno))")
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
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                warnings.append("接收 DHCP 响应失败：\(Self.posixMessage(errno))")
                continue
            }

            guard receivedBytes > 0 else { continue }
            let packetBytes = Array(buffer[0..<Int(receivedBytes)])
            let sourceAddress = IPv4Address(
                value: UInt32(bigEndian: source.sin_addr.s_addr)
            )

            guard let offer = DHCPPacketParser.parseOffer(
                packetBytes,
                xid: xid,
                sourceAddress: sourceAddress
            ) else {
                continue
            }

            let key = offer.serverIdentifier?.description ?? sourceAddress.description
            if offersByServer[key] == nil {
                offersByServer[key] = offer
            }
        }

        let offers = offersByServer.values.sorted { lhs, rhs in
            let lhsID = lhs.serverIdentifier?.value ?? 0
            let rhsID = rhs.serverIdentifier?.value ?? 0
            if lhsID == rhsID {
                return (lhs.sourceAddress?.value ?? 0) < (rhs.sourceAddress?.value ?? 0)
            }
            return lhsID < rhsID
        }

        return DHCPDiscoveryResult(
            offers: offers,
            warnings: Self.uniqueWarnings(warnings),
            errorMessage: nil,
            interfaceName: interface?.name,
            localAddress: interface?.address.description,
            subnet: interface?.subnet.description,
            broadcastTargets: destinations.map(\.description),
            boundPort: boundPort,
            requestedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    // MARK: - Socket helpers

    private static func configureSocket(_ fileDescriptor: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var receiveBuffer: Int32 = 1_024 * 1_024
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBuffer,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }

    private static func bindSocket(_ fileDescriptor: Int32, port: UInt16) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: 0)

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(
                    fileDescriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }

    private static func boundPort(_ fileDescriptor: Int32) -> UInt16? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fileDescriptor, socketAddress, &length)
            }
        }

        guard result == 0 else { return nil }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func send(
        packet: [UInt8],
        to destination: IPv4Address,
        socket fileDescriptor: Int32
    ) -> Int32? {
        var address = destination.sockaddr
        address.sin_port = UInt16(67).bigEndian

        let sentBytes = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
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

        return sentBytes < 0 ? errno : nil
    }

    private static func broadcastDestinations(interface: NetworkInterface.Info?) -> [IPv4Address] {
        var destinations: [IPv4Address] = []
        if let interface {
            let subnetBroadcast = interface.subnet.broadcast
            destinations.append(subnetBroadcast)
        }
        if !destinations.contains(.broadcast) {
            destinations.append(.broadcast)
        }
        return destinations
    }

    private static func failureResult(
        message: String,
        startedAt: Date,
        interface: NetworkInterface.Info?,
        destinations: [IPv4Address],
        warnings: [String]
    ) -> DHCPDiscoveryResult {
        DHCPDiscoveryResult(
            offers: [],
            warnings: uniqueWarnings(warnings),
            errorMessage: message,
            interfaceName: interface?.name,
            localAddress: interface?.address.description,
            subnet: interface?.subnet.description,
            broadcastTargets: destinations.map(\.description),
            boundPort: nil,
            requestedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private static func uniqueWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }

    private static func makeClientMAC() -> [UInt8] {
        var bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = (bytes[0] & 0xFC) | 0x02
        return bytes
    }

    private static func posixMessage(_ code: Int32) -> String {
        guard let message = strerror(code) else { return "errno \(code)" }
        return String(cString: message)
    }
}

private enum DHCPDiscoverBuilder {
    static func makePacket(xid: UInt32, mac: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 236)
        packet[0] = 1
        packet[1] = 1
        packet[2] = 6
        packet[3] = 0

        writeUInt32(xid, to: &packet, at: 4)
        packet[10] = 0x80
        packet[11] = 0x00

        for index in 0..<min(6, mac.count) {
            packet[28 + index] = mac[index]
        }

        packet.append(contentsOf: [99, 130, 83, 99])
        packet.append(contentsOf: option(53, [1]))
        packet.append(contentsOf: option(61, [1] + mac))
        packet.append(contentsOf: option(12, Array("NetWeiBao".utf8)))
        packet.append(contentsOf: option(60, Array("NetWeiBao/0.1".utf8)))
        packet.append(contentsOf: option(55, [1, 3, 6, 15, 28, 43, 51, 54, 58, 59, 119]))
        packet.append(contentsOf: option(57, [0x05, 0xDC]))
        packet.append(255)

        if packet.count < 300 {
            packet.append(contentsOf: [UInt8](repeating: 0, count: 300 - packet.count))
        }
        return packet
    }

    private static func option(_ code: UInt8, _ value: [UInt8]) -> [UInt8] {
        let bounded = Array(value.prefix(255))
        return [code, UInt8(bounded.count)] + bounded
    }

    private static func writeUInt32(_ value: UInt32, to packet: inout [UInt8], at offset: Int) {
        packet[offset] = UInt8((value >> 24) & 0xFF)
        packet[offset + 1] = UInt8((value >> 16) & 0xFF)
        packet[offset + 2] = UInt8((value >> 8) & 0xFF)
        packet[offset + 3] = UInt8(value & 0xFF)
    }
}

private enum DHCPPacketParser {
    static func parseOffer(
        _ packet: [UInt8],
        xid: UInt32,
        sourceAddress: IPv4Address
    ) -> DHCPOffer? {
        guard packet.count >= 240,
              packet[0] == 2,
              readUInt32(packet, at: 4) == xid,
              Array(packet[236..<240]) == [99, 130, 83, 99]
        else {
            return nil
        }

        let offeredAddress = address(packet, at: 16)
        let nextServer = address(packet, at: 20)
        let serverName = string(packet, offset: 44, length: 64)
        var bootFileName = string(packet, offset: 108, length: 128)

        var messageType: UInt8?
        var serverIdentifier: IPv4Address?
        var subnetMask: IPv4Address?
        var routers: [IPv4Address] = []
        var dnsServers: [IPv4Address] = []
        var leaseTime: TimeInterval?
        var renewalTime: TimeInterval?
        var rebindingTime: TimeInterval?
        var domainName: String?
        var broadcastAddress: IPv4Address?
        var vendorClass: String?
        var vendorSpecific: String?

        var index = 240
        while index < packet.count {
            let code = packet[index]
            index += 1

            if code == 0 { continue }
            if code == 255 { break }
            guard index < packet.count else { break }

            let length = Int(packet[index])
            index += 1
            guard index + length <= packet.count else { break }

            let value = Array(packet[index..<index + length])
            index += length

            switch code {
            case 1:
                subnetMask = address(value, at: 0)
            case 3:
                routers = addressList(value)
            case 6:
                dnsServers = addressList(value)
            case 15:
                domainName = string(value)
            case 28:
                broadcastAddress = address(value, at: 0)
            case 43:
                vendorSpecific = hex(value, limit: 64)
            case 51:
                if value.count >= 4 { leaseTime = TimeInterval(readUInt32(value, at: 0)) }
            case 53:
                messageType = value.first
            case 54:
                serverIdentifier = address(value, at: 0)
            case 58:
                if value.count >= 4 { renewalTime = TimeInterval(readUInt32(value, at: 0)) }
            case 59:
                if value.count >= 4 { rebindingTime = TimeInterval(readUInt32(value, at: 0)) }
            case 60:
                vendorClass = string(value)
            case 67:
                bootFileName = string(value)
            default:
                break
            }
        }

        guard messageType == 2 else { return nil }

        return DHCPOffer(
            serverIdentifier: serverIdentifier,
            sourceAddress: sourceAddress,
            offeredAddress: offeredAddress,
            subnetMask: subnetMask,
            routers: routers,
            dnsServers: dnsServers,
            leaseTime: leaseTime,
            renewalTime: renewalTime,
            rebindingTime: rebindingTime,
            domainName: domainName,
            broadcastAddress: broadcastAddress,
            nextServer: nextServer,
            serverName: serverName,
            bootFileName: bootFileName,
            vendorClass: vendorClass,
            vendorSpecific: vendorSpecific
        )
    }

    private static func address(_ data: [UInt8], at offset: Int) -> IPv4Address? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        let address = IPv4Address(
            a: data[offset],
            b: data[offset + 1],
            c: data[offset + 2],
            d: data[offset + 3]
        )
        return address.value == 0 ? nil : address
    }

    private static func addressList(_ data: [UInt8]) -> [IPv4Address] {
        guard data.count >= 4 else { return [] }
        let end = data.count - (data.count % 4)
        return stride(from: 0, to: end, by: 4).compactMap { address(data, at: $0) }
    }

    private static func readUInt32(_ data: [UInt8], at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 3 < data.count else { return 0 }
        return UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func string(_ data: [UInt8], offset: Int = 0, length: Int? = nil) -> String? {
        let end = min(data.count, offset + (length ?? data.count))
        guard offset >= 0, offset < end else { return nil }

        var bytes = Array(data[offset..<end])
        if let zero = bytes.firstIndex(of: 0) {
            bytes = Array(bytes[..<zero])
        }
        let value = String(bytes: bytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func hex(_ data: [UInt8], limit: Int) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix(limit)
        var text = prefix.map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.count > limit {
            text += " …"
        }
        return text
    }
}
