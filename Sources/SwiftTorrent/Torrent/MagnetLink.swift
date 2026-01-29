import Foundation

/// Parses and generates magnet URIs (BEP-9).
public struct MagnetLink: Sendable {
    public let infoHash: InfoHash
    public let displayName: String?
    public let trackers: [String]
    public let webSeeds: [String]

    public init(infoHash: InfoHash, displayName: String? = nil, trackers: [String] = [], webSeeds: [String] = []) {
        self.infoHash = infoHash
        self.displayName = displayName
        self.trackers = trackers
        self.webSeeds = webSeeds
    }

    /// Parse a magnet URI string.
    public init?(uri: String) {
        guard uri.hasPrefix("magnet:?") else { return nil }
        let query = String(uri.dropFirst("magnet:?".count))
        let params = query.split(separator: "&").map { param -> (String, String) in
            let parts = param.split(separator: "=", maxSplits: 1)
            let key = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            return (key, value.removingPercentEncoding ?? value)
        }

        var hash: InfoHash?
        var name: String?
        var trackers: [String] = []
        var webSeeds: [String] = []

        for (key, value) in params {
            switch key {
            case "xt":
                // urn:btih:<hex or base32>
                if value.hasPrefix("urn:btih:") {
                    let hashStr = String(value.dropFirst("urn:btih:".count))
                    if hashStr.count == 40 {
                        hash = InfoHash(hex: hashStr)
                    } else if hashStr.count == 32 {
                        // Base32 decode
                        if let decoded = Self.base32Decode(hashStr) {
                            hash = InfoHash(bytes: decoded)
                        }
                    }
                }
            case "dn":
                name = value
            case "tr":
                trackers.append(value)
            case "ws":
                webSeeds.append(value)
            default:
                break
            }
        }

        guard let infoHash = hash else { return nil }
        self.infoHash = infoHash
        self.displayName = name
        self.trackers = trackers
        self.webSeeds = webSeeds
    }

    /// Generate a magnet URI string.
    public var uri: String {
        var parts = ["magnet:?xt=urn:btih:\(infoHash.description)"]
        if let name = displayName {
            parts.append("dn=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")
        }
        for tracker in trackers {
            parts.append("tr=\(tracker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tracker)")
        }
        return parts.joined(separator: "&")
    }

    // MARK: - Base32

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Decode(_ input: String) -> Data? {
        let chars = input.uppercased()
        var bits = 0
        var value: UInt32 = 0
        var output = Data()

        for ch in chars {
            guard let idx = base32Alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | UInt32(idx)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return output
    }
}
