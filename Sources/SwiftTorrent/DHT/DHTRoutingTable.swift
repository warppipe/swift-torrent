import Foundation

/// A DHT node entry in the routing table.
public struct DHTNodeEntry: Sendable {
    public let id: NodeID
    public let address: String
    public let port: UInt16
    public var lastSeen: Date

    public init(id: NodeID, address: String, port: UInt16) {
        self.id = id
        self.address = address
        self.port = port
        self.lastSeen = Date()
    }
}

/// Kademlia k-bucket routing table (BEP-5).
public struct DHTRoutingTable: Sendable {
    public static let k = 8  // max nodes per bucket
    public static let bucketCount = 160

    public let ownID: NodeID
    private var buckets: [[DHTNodeEntry]]

    public init(ownID: NodeID) {
        self.ownID = ownID
        self.buckets = Array(repeating: [], count: Self.bucketCount)
    }

    /// Insert or update a node in the routing table.
    public mutating func insert(_ node: DHTNodeEntry) -> Bool {
        let index = ownID.bucketIndex(relativeTo: node.id)
        let bucketIdx = min(index, Self.bucketCount - 1)

        // Check if node already exists
        if let existingIdx = buckets[bucketIdx].firstIndex(where: { $0.id == node.id }) {
            buckets[bucketIdx][existingIdx].lastSeen = Date()
            return true
        }

        // Bucket not full — add
        if buckets[bucketIdx].count < Self.k {
            buckets[bucketIdx].append(node)
            return true
        }

        // Bucket full — could implement splitting or eviction
        return false
    }

    /// Find the closest nodes to a target ID.
    public func closestNodes(to target: NodeID, count: Int = Self.k) -> [DHTNodeEntry] {
        let all = buckets.flatMap { $0 }
        let sorted = all.sorted { a, b in
            distanceLessThan(a.id.distance(to: target), b.id.distance(to: target))
        }
        return Array(sorted.prefix(count))
    }

    /// Get a specific bucket.
    public func bucket(at index: Int) -> [DHTNodeEntry] {
        guard index >= 0 && index < Self.bucketCount else { return [] }
        return buckets[index]
    }

    /// Total number of nodes.
    public var nodeCount: Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    /// Remove stale nodes older than the given interval.
    public mutating func removeStaleNodes(olderThan interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        for i in 0..<buckets.count {
            buckets[i].removeAll { $0.lastSeen < cutoff }
        }
    }
}
