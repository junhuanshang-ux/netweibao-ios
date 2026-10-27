import Darwin
import Dispatch
import Foundation

enum HostResolutionError: LocalizedError, Sendable {
    case empty
    case notFound(String)
    case system(Int32)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入 IP 地址或域名"
        case .notFound(let host):
            return "无法解析 \(host)，请检查域名或当前网络"
        case .system(let code):
            return "域名解析失败（错误码 \(code)）"
        }
    }
}

enum HostResolver {
    /// Resolves a host name to one IPv4 address. Numeric addresses bypass DNS.
    static func resolveIPv4(_ input: String) async -> Result<IPv4Address, HostResolutionError> {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return .failure(.empty) }
        if let address = IPv4Address(host) { return .success(address) }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<IPv4Address, HostResolutionError>, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: blockingResolve(host))
            }
        }
    }

    private static func blockingResolve(_ host: String) -> Result<IPv4Address, HostResolutionError> {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = 0
        hints.ai_flags = 0

        var result: UnsafeMutablePointer<addrinfo>?
        let status = host.withCString { name in
            getaddrinfo(name, nil, &hints, &result)
        }

        guard status == 0, let first = result else {
            if status == EAI_NONAME {
                return .failure(.notFound(host))
            }
            return .failure(.system(status))
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ai_next }
            guard let socketAddress = item.pointee.ai_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                IPv4Address(value: UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
            }
            return .success(address)
        }

        return .failure(.notFound(host))
    }
}
