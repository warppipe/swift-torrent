import Foundation

/// Tracks per-peer protocol state for download orchestration.
public actor PeerState {
    public var amChoking: Bool = true
    public var amInterested: Bool = false
    public var peerChoking: Bool = true
    public var peerInterested: Bool = false
    public var peerBitfield: Bitfield
    public var supportsExtensions: Bool = false

    /// Pending block requests: (pieceIndex, offset, length) → timestamp
    public struct BlockRequest: Hashable, Sendable {
        public let pieceIndex: Int
        public let offset: Int
        public let length: Int
    }
    private var pendingRequests: [BlockRequest: Date] = [:]
    public let maxPipelineDepth: Int

    public init(pieceCount: Int, maxPipelineDepth: Int = 5) {
        self.peerBitfield = Bitfield(count: pieceCount)
        self.maxPipelineDepth = maxPipelineDepth
    }

    public func getPeerBitfield() -> Bitfield {
        peerBitfield
    }

    public func getPeerChoking() -> Bool {
        peerChoking
    }

    public func getAmInterested() -> Bool {
        amInterested
    }

    public var pendingCount: Int {
        pendingRequests.count
    }

    public var canRequest: Bool {
        pendingRequests.count < maxPipelineDepth
    }

    public func getPendingRequests() -> [BlockRequest: Date] {
        pendingRequests
    }

    public func hasPending(_ request: BlockRequest) -> Bool {
        pendingRequests[request] != nil
    }

    public func setPeerBitfield(_ bf: Bitfield) {
        peerBitfield = bf
    }

    public func setHave(_ index: Int) {
        peerBitfield.set(index)
    }

    public func setPeerChoking(_ choking: Bool) {
        peerChoking = choking
    }

    public func setPeerInterested(_ interested: Bool) {
        peerInterested = interested
    }

    public func setAmChoking(_ choking: Bool) {
        amChoking = choking
    }

    public func setAmInterested(_ interested: Bool) {
        amInterested = interested
    }

    public func addPendingRequest(_ request: BlockRequest) {
        pendingRequests[request] = Date()
    }

    public func removePendingRequest(_ request: BlockRequest) {
        pendingRequests.removeValue(forKey: request)
    }

    public func clearPendingRequests() {
        pendingRequests.removeAll()
    }

    /// Returns requests older than the given timeout interval.
    public func timedOutRequests(timeout: TimeInterval = 30) -> [BlockRequest] {
        let cutoff = Date().addingTimeInterval(-timeout)
        return pendingRequests.filter { $0.value < cutoff }.map(\.key)
    }
}
