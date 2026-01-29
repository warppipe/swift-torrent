import Foundation
import Crypto

/// A BitTorrent info hash — SHA-1 (v1) or SHA-256 (v2).
public struct InfoHash: Hashable, Sendable, CustomStringConvertible {
    public enum Version: Sendable {
        case v1  // SHA-1, 20 bytes
        case v2  // SHA-256, 32 bytes
    }

    public let bytes: Data
    public let version: Version

    public var description: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Create an info hash from raw bytes.
    public init(bytes: Data) {
        self.bytes = bytes
        self.version = bytes.count == 32 ? .v2 : .v1
    }

    /// Compute SHA-1 info hash from the raw bencoded info dictionary.
    public static func v1(from infoData: Data) -> InfoHash {
        let digest = Insecure.SHA1.hash(data: infoData)
        return InfoHash(bytes: Data(digest))
    }

    /// Compute SHA-256 info hash from the raw bencoded info dictionary.
    public static func v2(from infoData: Data) -> InfoHash {
        let digest = SHA256.hash(data: infoData)
        return InfoHash(bytes: Data(digest))
    }

    /// Create from hex string.
    public init?(hex: String) {
        guard hex.count == 40 || hex.count == 64 else { return nil }
        var data = Data()
        var chars = hex.makeIterator()
        while let c1 = chars.next(), let c2 = chars.next() {
            guard let byte = UInt8(String([c1, c2]), radix: 16) else { return nil }
            data.append(byte)
        }
        self.init(bytes: data)
    }

    /// URL-encoded form for tracker announces.
    public var urlEncoded: String {
        bytes.map { byte in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_~"))
            let str = String(format: "%c", byte)
            if let scalar = str.unicodeScalars.first, allowed.contains(scalar) {
                return str
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }
}
