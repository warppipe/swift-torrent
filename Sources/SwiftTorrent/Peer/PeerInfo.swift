import Foundation

/// Information about a connected peer.
public struct PeerInfo: Sendable, Identifiable {
    public let id: Data          // 20-byte peer ID
    public let address: String
    public let port: UInt16

    public var isChoked: Bool
    public var isInterested: Bool
    public var amChoking: Bool
    public var amInterested: Bool
    public var downloadRate: Double  // bytes per second
    public var uploadRate: Double
    public var peerBitfield: Bitfield?

    public init(id: Data, address: String, port: UInt16) {
        self.id = id
        self.address = address
        self.port = port
        self.isChoked = true
        self.isInterested = false
        self.amChoking = true
        self.amInterested = false
        self.downloadRate = 0
        self.uploadRate = 0
    }
}
