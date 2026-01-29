import Foundation
import NIOCore
import NIOPosix

/// Manages the pool of peer connections for a torrent.
public actor PeerManager {
    private let infoHash: Data
    private let peerID: Data
    private let group: EventLoopGroup
    private var connections: [String: PeerConnection] = [:]
    private var peerInfos: [String: PeerInfo] = [:]
    private let maxConnections: Int

    public init(infoHash: Data, peerID: Data, group: EventLoopGroup, maxConnections: Int = 50) {
        self.infoHash = infoHash
        self.peerID = peerID
        self.group = group
        self.maxConnections = maxConnections
    }

    /// Add a peer and attempt connection.
    public func addPeer(address: String, port: UInt16) async {
        let key = "\(address):\(port)"
        guard connections[key] == nil else { return }
        guard connections.count < maxConnections else { return }

        let conn = PeerConnection(address: address, port: port, infoHash: infoHash, peerID: peerID)
        connections[key] = conn
        peerInfos[key] = PeerInfo(id: Data(), address: address, port: port)
    }

    /// Remove a peer.
    public func removePeer(address: String, port: UInt16) async {
        let key = "\(address):\(port)"
        if let conn = connections.removeValue(forKey: key) {
            try? await conn.close()
        }
        peerInfos.removeValue(forKey: key)
    }

    /// Get all connected peer infos.
    public func peers() -> [PeerInfo] {
        Array(peerInfos.values)
    }

    /// Number of active connections.
    public var connectionCount: Int {
        connections.count
    }

    /// Implements the choking algorithm — unchoke top uploaders + one optimistic unchoke.
    public func runChokingAlgorithm() async {
        var peers = Array(peerInfos)

        // Sort by download rate descending
        peers.sort { $0.value.downloadRate > $1.value.downloadRate }

        let unchokeSlots = 4
        for (i, peer) in peers.enumerated() {
            var info = peer.value
            if i < unchokeSlots {
                info.amChoking = false
            } else if i == unchokeSlots {
                // Optimistic unchoke
                info.amChoking = false
            } else {
                info.amChoking = true
            }
            peerInfos[peer.key] = info
        }
    }

    /// Broadcast a have message to all peers.
    public func broadcastHave(pieceIndex: UInt32) async {
        let msg = PeerMessage.have(pieceIndex: pieceIndex)
        for conn in connections.values {
            try? await conn.send(msg)
        }
    }
}
