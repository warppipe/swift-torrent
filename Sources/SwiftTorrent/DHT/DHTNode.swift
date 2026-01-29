import Foundation
import NIOCore
import NIOPosix

/// A DHT node that handles KRPC queries (BEP-5).
public actor DHTNode {
    public let nodeID: NodeID
    private var routingTable: DHTRoutingTable
    private var storage: DHTStorage
    private let group: EventLoopGroup
    private var channel: Channel?
    private let port: Int

    public init(nodeID: NodeID = .random(), port: Int = 6881, group: EventLoopGroup) {
        self.nodeID = nodeID
        self.routingTable = DHTRoutingTable(ownID: nodeID)
        self.storage = DHTStorage()
        self.group = group
        self.port = port
    }

    /// Start the DHT node, binding to a UDP port.
    public func start() async throws {
        self.channel = try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "0.0.0.0", port: port)
            .get()
        // Store channel for sending
        // In a full implementation, add a channel handler for incoming messages
    }

    /// Send a ping query.
    public func ping(to address: String, port: UInt16) async throws {
        let txID = generateTransactionID()
        let msg = DHTMessage.query(
            transactionID: txID,
            queryType: .ping,
            arguments: [
                (key: Data("id".utf8), value: .string(nodeID.bytes))
            ]
        )
        try await sendMessage(msg, to: address, port: port)
    }

    /// Send a find_node query.
    public func findNode(target: NodeID, to address: String, port: UInt16) async throws {
        let txID = generateTransactionID()
        let msg = DHTMessage.query(
            transactionID: txID,
            queryType: .findNode,
            arguments: [
                (key: Data("id".utf8), value: .string(nodeID.bytes)),
                (key: Data("target".utf8), value: .string(target.bytes)),
            ]
        )
        try await sendMessage(msg, to: address, port: port)
    }

    /// Send a get_peers query.
    public func getPeers(infoHash: InfoHash, to address: String, port: UInt16) async throws {
        let txID = generateTransactionID()
        let msg = DHTMessage.query(
            transactionID: txID,
            queryType: .getPeers,
            arguments: [
                (key: Data("id".utf8), value: .string(nodeID.bytes)),
                (key: Data("info_hash".utf8), value: .string(infoHash.bytes)),
            ]
        )
        try await sendMessage(msg, to: address, port: port)
    }

    /// Send an announce_peer query.
    public func announcePeer(infoHash: InfoHash, port: UInt16, token: Data,
                              to address: String, nodePort: UInt16) async throws {
        let txID = generateTransactionID()
        let msg = DHTMessage.query(
            transactionID: txID,
            queryType: .announcePeer,
            arguments: [
                (key: Data("id".utf8), value: .string(nodeID.bytes)),
                (key: Data("implied_port".utf8), value: .integer(0)),
                (key: Data("info_hash".utf8), value: .string(infoHash.bytes)),
                (key: Data("port".utf8), value: .integer(Int64(port))),
                (key: Data("token".utf8), value: .string(token)),
            ]
        )
        try await sendMessage(msg, to: address, port: nodePort)
    }

    /// Get closest nodes from routing table.
    public func closestNodes(to target: NodeID) -> [DHTNodeEntry] {
        routingTable.closestNodes(to: target)
    }

    /// Add a node to the routing table.
    public func addNode(_ entry: DHTNodeEntry) {
        _ = routingTable.insert(entry)
    }

    // MARK: - Private

    private func generateTransactionID() -> Data {
        var data = Data(count: 2)
        data[0] = UInt8.random(in: 0...255)
        data[1] = UInt8.random(in: 0...255)
        return data
    }

    private func sendMessage(_ msg: DHTMessage, to address: String, port: UInt16) async throws {
        guard let ch = channel else { return }
        let data = msg.encode()
        let remoteAddr = try SocketAddress(ipAddress: address, port: Int(port))
        var buf = ch.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        let envelope = AddressedEnvelope(remoteAddress: remoteAddr, data: buf)
        try await ch.writeAndFlush(envelope).get()
    }
}
