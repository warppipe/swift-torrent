import Foundation

/// Storage for DHT peer announcements with expiration.
public struct DHTStorage: Sendable {
    private var peerStore: [Data: [PeerEntry]]  // info_hash -> peers
    private let maxPeersPerHash: Int
    private let expirationInterval: TimeInterval

    public init(maxPeersPerHash: Int = 100, expirationInterval: TimeInterval = 30 * 60) {
        self.peerStore = [:]
        self.maxPeersPerHash = maxPeersPerHash
        self.expirationInterval = expirationInterval
    }

    /// Store a peer for an info hash.
    public mutating func addPeer(infoHash: Data, address: String, port: UInt16) {
        let entry = PeerEntry(address: address, port: port, addedAt: Date())
        var peers = peerStore[infoHash] ?? []
        // Remove existing entry for same address:port
        peers.removeAll { $0.address == address && $0.port == port }
        peers.append(entry)
        // Trim to max
        if peers.count > maxPeersPerHash {
            peers = Array(peers.suffix(maxPeersPerHash))
        }
        peerStore[infoHash] = peers
    }

    /// Get peers for an info hash.
    public func getPeers(infoHash: Data) -> [(String, UInt16)] {
        let cutoff = Date().addingTimeInterval(-expirationInterval)
        return (peerStore[infoHash] ?? [])
            .filter { $0.addedAt > cutoff }
            .map { ($0.address, $0.port) }
    }

    /// Remove expired entries.
    public mutating func removeExpired() {
        let cutoff = Date().addingTimeInterval(-expirationInterval)
        for (hash, peers) in peerStore {
            let filtered = peers.filter { $0.addedAt > cutoff }
            if filtered.isEmpty {
                peerStore.removeValue(forKey: hash)
            } else {
                peerStore[hash] = filtered
            }
        }
    }

    private struct PeerEntry: Sendable {
        let address: String
        let port: UInt16
        let addedAt: Date
    }
}
