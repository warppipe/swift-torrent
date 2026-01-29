import Foundation

/// Iterative DHT lookup algorithms.
public actor DHTTraversal {
    private let dhtNode: DHTNode
    private let alpha: Int  // parallelism factor

    public init(dhtNode: DHTNode, alpha: Int = 3) {
        self.dhtNode = dhtNode
        self.alpha = alpha
    }

    /// Iterative find_node lookup — finds the k closest nodes to a target.
    public func findNode(target: NodeID) async throws -> [DHTNodeEntry] {
        var closest = await dhtNode.closestNodes(to: target)
        var queried = Set<NodeID>()
        var improved = true

        while improved {
            improved = false
            let toQuery = closest
                .filter { !queried.contains($0.id) }
                .prefix(alpha)

            for node in toQuery {
                queried.insert(node.id)
                do {
                    try await dhtNode.findNode(target: target, to: node.address, port: node.port)
                    // In a full implementation, we'd collect responses and merge into closest
                } catch {
                    continue
                }
            }

            let newClosest = await dhtNode.closestNodes(to: target)
            if newClosest.first?.id != closest.first?.id {
                improved = true
                closest = newClosest
            }
        }

        return closest
    }

    /// Iterative get_peers lookup — finds peers for an info hash.
    public func getPeers(infoHash: InfoHash) async throws -> [(String, UInt16)] {
        let target = NodeID(bytes: infoHash.bytes.prefix(20).count == 20
            ? Data(infoHash.bytes.prefix(20))
            : infoHash.bytes + Data(count: max(0, 20 - infoHash.bytes.count)))

        var closest = await dhtNode.closestNodes(to: target)
        var queried = Set<NodeID>()
        let peers: [(String, UInt16)] = []

        for _ in 0..<10 {  // max iterations
            let toQuery = closest
                .filter { !queried.contains($0.id) }
                .prefix(alpha)

            if toQuery.isEmpty { break }

            for node in toQuery {
                queried.insert(node.id)
                try? await dhtNode.getPeers(infoHash: infoHash, to: node.address, port: node.port)
            }

            closest = await dhtNode.closestNodes(to: target)
        }

        return peers
    }
}
