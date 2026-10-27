import Darwin
import Foundation

/// A small, allocation-free IPv4 value type.
/// `value` is always stored in host byte order; socket conversion happens explicitly.
struct IPv4Address: Hashable, Comparable, CustomStringConvertible, Identifiable, Sendable {
    let value: UInt32

    var id: UInt32 { value }

    init(value: UInt32) {
        self.value = value
    }

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var raw = in_addr()
        let result = trimmed.withCString { inet_pton(AF_INET, $0, &raw) }
        guard result == 1 else { return nil }

        self.value = UInt32(bigEndian: raw.s_addr)
    }

    init(a: UInt8, b: UInt8, c: UInt8, d: UInt8) {
        self.value = UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    static let zero = IPv4Address(value: 0)
    static let broadcast = IPv4Address(value: UInt32.max)

    var description: String {
        var raw = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        let converted: Bool = withUnsafePointer(to: &raw) { pointer in
            buffer.withUnsafeMutableBufferPointer { output in
                guard let base = output.baseAddress else { return false }
                return inet_ntop(
                    AF_INET,
                    UnsafeRawPointer(pointer),
                    base,
                    socklen_t(output.count)
                ) != nil
            }
        }

        guard converted else { return "0.0.0.0" }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return "0.0.0.0" }
            return String(cString: base)
        }
    }

    var networkOrder: UInt32 {
        value.bigEndian
    }

    var sockaddr: sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: value.bigEndian)
        return address
    }

    func adding(_ delta: UInt32) -> IPv4Address {
        IPv4Address(value: value &+ delta)
    }

    var isLoopback: Bool {
        value & 0xFF00_0000 == 0x7F00_0000
    }

    var isLinkLocal: Bool {
        value & 0xFFFF_0000 == 0xA9FE_0000
    }

    var isPrivate: Bool {
        if value & 0xFF00_0000 == 0x0A00_0000 { return true }
        if value & 0xFFF0_0000 == 0xAC10_0000 { return true }
        if value & 0xFFFF_0000 == 0xC0A8_0000 { return true }
        if isLinkLocal { return true }
        if value & 0xFFC0_0000 == 0x6440_0000 { return true }
        return false
    }

    var isMulticast: Bool {
        value & 0xF000_0000 == 0xE000_0000
    }

    static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.value < rhs.value
    }
}
