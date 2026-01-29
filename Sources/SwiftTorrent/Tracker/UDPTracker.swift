import Foundation
import NIOCore
import NIOPosix

/// UDP tracker client (BEP-15).
public final class UDPTracker: Sendable {
    public let host: String
    public let port: Int
    private let group: EventLoopGroup

    public init(host: String, port: Int, group: EventLoopGroup) {
        self.host = host
        self.port = port
        self.group = group
    }

    /// Announce to the UDP tracker.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        let channel = try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "0.0.0.0", port: 0)
            .get()

        let remoteAddr = try SocketAddress(ipAddress: host, port: port)

        // Step 1: Connect request
        let transactionID = UInt32.random(in: 0...UInt32.max)
        var connectReq = Data()
        connectReq.append(contentsOf: UInt64(0x41727101980).bigEndianBytes) // magic
        connectReq.append(contentsOf: UInt32(0).bigEndianBytes) // action: connect
        connectReq.append(contentsOf: transactionID.bigEndianBytes)

        var buf = channel.allocator.buffer(capacity: connectReq.count)
        buf.writeBytes(connectReq)
        let envelope = AddressedEnvelope(remoteAddress: remoteAddr, data: buf)
        try await channel.writeAndFlush(envelope).get()

        // Read connect response
        // In a real implementation, this would use a proper response handler.
        // For now, we create a simplified response flow.
        let connectionID: UInt64 = 0  // placeholder — real impl reads from channel

        // Step 2: Announce request
        var announceReq = Data()
        announceReq.append(contentsOf: connectionID.bigEndianBytes)
        announceReq.append(contentsOf: UInt32(1).bigEndianBytes) // action: announce
        let announceTxID = UInt32.random(in: 0...UInt32.max)
        announceReq.append(contentsOf: announceTxID.bigEndianBytes)
        announceReq.append(params.infoHash.bytes)
        announceReq.append(params.peerID)
        announceReq.append(contentsOf: params.downloaded.bigEndianBytes)
        announceReq.append(contentsOf: params.left.bigEndianBytes)
        announceReq.append(contentsOf: params.uploaded.bigEndianBytes)
        announceReq.append(contentsOf: UInt32(0).bigEndianBytes) // event: none
        announceReq.append(contentsOf: UInt32(0).bigEndianBytes) // IP
        announceReq.append(contentsOf: UInt32.random(in: 0...UInt32.max).bigEndianBytes) // key
        announceReq.append(contentsOf: Int32(params.numWant).bigEndianBytes)
        announceReq.append(contentsOf: params.port.bigEndianBytes)

        var abuf = channel.allocator.buffer(capacity: announceReq.count)
        abuf.writeBytes(announceReq)
        let aenvelope = AddressedEnvelope(remoteAddress: remoteAddr, data: abuf)
        try await channel.writeAndFlush(aenvelope).get()

        // Clean up
        try await channel.close().get()

        // Placeholder response — real implementation reads UDP responses
        return AnnounceResponse(interval: 1800, seeders: 0, leechers: 0, peers: [])
    }
}

// MARK: - Big-endian helpers

extension UInt64 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be) { Array($0) }
    }
}

extension Int64 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be) { Array($0) }
    }
}

extension Int32 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be) { Array($0) }
    }
}
