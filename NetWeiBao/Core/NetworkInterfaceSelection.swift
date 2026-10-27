import Darwin
import Foundation

final class NetworkInterfaceSelection: @unchecked Sendable {
    static let shared = NetworkInterfaceSelection()

    private let lock = NSLock()
    private var name: String?

    private init() {}

    var selectedName: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return name
        }
        set {
            lock.lock()
            name = newValue
            lock.unlock()
        }
    }
}

enum InterfaceBinder {
    /// Bind an IPv4 socket to a specific interface when possible.
    /// Failure is non-fatal: the system route remains in effect.
    static func bind(_ fileDescriptor: Int32, to interfaceName: String?) {
        guard let interfaceName, !interfaceName.isEmpty else { return }
        let index = interfaceName.withCString { if_nametoindex($0) }
        guard index > 0 else { return }

        var value = index
        _ = setsockopt(
            fileDescriptor,
            IPPROTO_IP,
            IP_BOUND_IF,
            &value,
            socklen_t(MemoryLayout<UInt32>.size)
        )
    }
}
