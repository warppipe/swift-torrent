import Foundation

/// 160-bit DHT node identifier.
public struct NodeID: Hashable, Sendable, CustomStringConvertible {
    public let bytes: Data  // 20 bytes

    public init(bytes: Data) {
        precondition(bytes.count == 20)
        self.bytes = bytes
    }

    /// Generate a random node ID.
    public static func random() -> NodeID {
        var data = Data(count: 20)
        for i in 0..<20 {
            data[i] = UInt8.random(in: 0...255)
        }
        return NodeID(bytes: data)
    }

    /// XOR distance between two node IDs.
    public func distance(to other: NodeID) -> Data {
        var result = Data(count: 20)
        for i in 0..<20 {
            result[i] = bytes[bytes.startIndex + i] ^ other.bytes[other.bytes.startIndex + i]
        }
        return result
    }

    /// The index of the highest set bit in the distance (0-159), used for bucket selection.
    public func bucketIndex(relativeTo other: NodeID) -> Int {
        let dist = distance(to: other)
        for i in 0..<20 {
            let byte = dist[i]
            if byte != 0 {
                let bit = 7 - byte.leadingZeroBitCount
                return (19 - i) * 8 + bit
            }
        }
        return 0
    }

    public var description: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Compare distances: returns true if d1 < d2.
public func distanceLessThan(_ d1: Data, _ d2: Data) -> Bool {
    for i in 0..<min(d1.count, d2.count) {
        if d1[d1.startIndex + i] < d2[d2.startIndex + i] { return true }
        if d1[d1.startIndex + i] > d2[d2.startIndex + i] { return false }
    }
    return false
}
