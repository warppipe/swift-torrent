import Foundation

/// A compact bit array backed by `[UInt64]` for tracking piece availability.
public struct Bitfield: Sendable, Equatable {
    public private(set) var storage: [UInt64]
    public let count: Int

    public init(count: Int) {
        self.count = count
        let words = (count + 63) / 64
        self.storage = [UInt64](repeating: 0, count: words)
    }

    /// Initialize from raw bytes (network format, big-endian bit ordering).
    public init(data: Data, count: Int) {
        self.count = count
        let words = (count + 63) / 64
        var stor = [UInt64](repeating: 0, count: words)
        for i in 0..<min(data.count * 8, count) {
            let byteIdx = i / 8
            let bitIdx = 7 - (i % 8) // big-endian bit order
            if data[data.startIndex + byteIdx] & (1 << bitIdx) != 0 {
                let wordIdx = i / 64
                let wordBit = i % 64
                stor[wordIdx] |= (1 << wordBit)
            }
        }
        self.storage = stor
    }

    public func get(_ index: Int) -> Bool {
        guard index >= 0 && index < count else { return false }
        let wordIdx = index / 64
        let bitIdx = index % 64
        return storage[wordIdx] & (1 << bitIdx) != 0
    }

    public mutating func set(_ index: Int) {
        guard index >= 0 && index < count else { return }
        let wordIdx = index / 64
        let bitIdx = index % 64
        storage[wordIdx] |= (1 << bitIdx)
    }

    public mutating func clear(_ index: Int) {
        guard index >= 0 && index < count else { return }
        let wordIdx = index / 64
        let bitIdx = index % 64
        storage[wordIdx] &= ~(1 << bitIdx)
    }

    /// Number of set bits.
    public var popcount: Int {
        storage.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// Whether all bits are set.
    public var allSet: Bool {
        popcount == count
    }

    /// Whether no bits are set.
    public var isEmpty: Bool {
        popcount == 0
    }

    /// Serialize to bytes (big-endian bit order) for network transmission.
    public func toData() -> Data {
        let byteCount = (count + 7) / 8
        var data = Data(count: byteCount)
        for i in 0..<count {
            if get(i) {
                let byteIdx = i / 8
                let bitIdx = 7 - (i % 8)
                data[byteIdx] |= (1 << bitIdx)
            }
        }
        return data
    }
}
