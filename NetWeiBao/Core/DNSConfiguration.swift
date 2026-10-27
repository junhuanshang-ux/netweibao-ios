import Foundation

enum DNSConfiguration {
    /// Best-effort read of the system resolver configuration.
    /// iOS may hide or sandbox this file; an empty result is reported as unknown.
    static func servers() -> [String] {
        guard let contents = try? String(
            contentsOfFile: "/etc/resolv.conf",
            encoding: .utf8
        ) else {
            return []
        }

        var result: [String] = []
        var seen = Set<String>()

        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0] == "nameserver" else { continue }
            let server = String(parts[1])
            guard seen.insert(server).inserted else { continue }
            result.append(server)
        }

        return result
    }
}
