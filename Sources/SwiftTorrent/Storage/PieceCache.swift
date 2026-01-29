import Foundation

/// LRU piece cache for reducing disk reads.
public actor PieceCache {
    private var cache: [Int: Data]  // piece index -> data
    private var accessOrder: [Int]  // LRU order (most recent at end)
    private let maxPieces: Int

    public init(maxPieces: Int = 64) {
        self.cache = [:]
        self.accessOrder = []
        self.maxPieces = maxPieces
    }

    /// Get a piece from cache.
    public func get(_ pieceIndex: Int) -> Data? {
        guard let data = cache[pieceIndex] else { return nil }
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == pieceIndex }
        accessOrder.append(pieceIndex)
        return data
    }

    /// Put a piece into cache.
    public func put(_ pieceIndex: Int, data: Data) {
        cache[pieceIndex] = data
        accessOrder.removeAll { $0 == pieceIndex }
        accessOrder.append(pieceIndex)

        // Evict oldest if over capacity
        while cache.count > maxPieces, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }

    /// Clear the cache.
    public func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    public func count() -> Int {
        cache.count
    }
}
