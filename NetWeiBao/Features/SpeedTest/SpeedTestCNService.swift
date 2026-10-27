import CommonCrypto
import Foundation

/// Adapter for the public web test used by www.speedtest.cn.
/// The node list is an internal, AES-encrypted web response; it can change
/// without notice and is not a documented public API.
final class SpeedTestCNService: @unchecked Sendable {
    static let shared = SpeedTestCNService()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let key = Data("5ECC5D62140EC099".utf8)
    private let iv = Data("E63EA892A702EEAA".utf8)

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    func resolveNode() async throws -> SpeedTestNode {
        let encoded = try await fetchNodeData()
        guard let cipher = Data(base64Encoded: encoded) else {
            throw SpeedTestError.message("测速网节点数据不是有效的 Base64。")
        }

        let plain = try decrypt(cipher)
        guard let root = try? JSONSerialization.jsonObject(with: plain),
              let object = root as? [String: Any],
              let rows = object["data"] as? [[String: Any]]
        else {
            throw SpeedTestError.message("测速网节点 JSON 结构无效（解密后无法读取 data 数组）。")
        }

        let candidates = rows.compactMap(makeNode).sorted {
            $0.distance < $1.distance
        }
        guard let first = candidates.first else {
            throw SpeedTestError.message("测速网没有返回可用的国内测速节点。")
        }
        return first.node
    }

    private func fetchNodeData() async throws -> String {
        guard var components = URLComponents(
            string: "https://nodes-api.speedtest.cn/"
        ) else {
            throw SpeedTestError.message("测速网节点接口地址无效。")
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: "multi"),
            URLQueryItem(name: "https", value: "1"),
            URLQueryItem(name: "browser", value: "1"),
            URLQueryItem(name: "domainType", value: "2"),
            URLQueryItem(name: "use_cdn", value: "1"),
            URLQueryItem(name: "short_sign", value: "1")
        ]
        guard let url = components.url else {
            throw SpeedTestError.message("测速网节点接口地址无效。")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.speedtest.cn/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw SpeedTestError.httpStatus(
                (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }

        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              let encoded = object["data"] as? String
        else {
            let preview = String(data: data.prefix(160), encoding: .utf8) ?? "—"
            throw SpeedTestError.message("测速网节点接口返回格式异常：\(preview)")
        }
        return encoded
    }

    private func makeNode(_ row: [String: Any]) -> (distance: Int, node: SpeedTestNode)? {
        guard intValue(row["is_cdn"]) != 1,
              let downloadString = stringValue(row["downloadUrl"]),
              let uploadString = stringValue(row["uploadUrl"]),
              let pingString = stringValue(row["pingUrl"]),
              let downloadURL = URL(string: downloadString),
              let uploadURL = URL(string: uploadString),
              let pingURL = URL(string: pingString)
        else {
            return nil
        }

        var components = URLComponents(
            url: downloadURL,
            resolvingAgainstBaseURL: false
        )
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        guard let baseURL = components?.url else { return nil }

        let province = stringValue(row["province"]) ?? ""
        let city = stringValue(row["city"]) ?? ""
        let operatorName = stringValue(row["operator"]) ?? "测速网"
        let location = [province, city]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let name = location.isEmpty
            ? "测速网 · \(operatorName)"
            : "测速网 · \(location) · \(operatorName)"

        let speedNode = SpeedTestNode(
            name: name,
            baseURL: baseURL,
            downloadPath: path(for: downloadURL, fallback: "download"),
            uploadPath: path(for: uploadURL, fallback: "upload"),
            pingPath: path(for: pingURL, fallback: "hello"),
            downloadSizeParameter: "size",
            maxDownloadMegabytesPerRequest: 10,
            maxUploadMegabytesPerRequest: 10,
            referer: "https://www.speedtest.cn/"
        )
        return (intValue(row["distance"]) ?? Int.max, speedNode)
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func path(for url: URL, fallback: String) -> String {
        let value = url.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return value.isEmpty ? fallback : value
    }

    private func decrypt(_ cipher: Data) throws -> Data {
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var moved = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            cipher.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            cipher.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw SpeedTestError.message("测速网节点数据解密失败（\(status)）。")
        }

        output.removeSubrange(moved..<output.count)
        return output
    }
}
