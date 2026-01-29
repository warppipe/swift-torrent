import Foundation

/// Rarest-first piece selection strategy.
public struct PiecePicker: Sendable {
    private let pieceCount: Int
    private var availability: [Int]  // how many peers have each piece

    public init(pieceCount: Int) {
        self.pieceCount = pieceCount
        self.availability = [Int](repeating: 0, count: pieceCount)
    }

    /// Update availability from a peer's bitfield.
    public mutating func addPeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] += 1
            }
        }
    }

    /// Remove a peer's bitfield from availability counts.
    public mutating func removePeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] = max(0, availability[i] - 1)
            }
        }
    }

    /// Increment availability for a single piece (peer sent "have").
    public mutating func addHave(_ pieceIndex: Int) {
        guard pieceIndex >= 0 && pieceIndex < pieceCount else { return }
        availability[pieceIndex] += 1
    }

    /// Pick the next piece to request using rarest-first strategy.
    /// `have` is our own bitfield; `peerHas` is the peer's bitfield.
    public func pick(have: Bitfield, peerHas: Bitfield) -> Int? {
        var best: Int?
        var bestAvail = Int.max

        for i in 0..<pieceCount {
            // We don't have it, peer does have it
            if !have.get(i) && peerHas.get(i) {
                if availability[i] < bestAvail {
                    bestAvail = availability[i]
                    best = i
                }
            }
        }

        return best
    }

    /// Pick multiple pieces (for pipelining).
    public func pickMultiple(have: Bitfield, peerHas: Bitfield, count: Int) -> [Int] {
        var candidates: [(index: Int, avail: Int)] = []
        for i in 0..<pieceCount {
            if !have.get(i) && peerHas.get(i) {
                candidates.append((i, availability[i]))
            }
        }
        candidates.sort { $0.avail < $1.avail }
        return Array(candidates.prefix(count).map(\.index))
    }
}
