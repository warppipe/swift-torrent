import Foundation
import NIOCore
import NIOPosix
import NIOExtras

/// Manages a single peer TCP connection using SwiftNIO.
public final class PeerConnection: @unchecked Sendable {
    public let address: String
    public let port: UInt16

    private var _channel: Channel?
    private let lock = NSLock()
    private let infoHash: Data
    private let peerID: Data

    public init(address: String, port: UInt16, infoHash: Data, peerID: Data) {
        self.address = address
        self.port = port
        self.infoHash = infoHash
        self.peerID = peerID
    }

    private func setChannel(_ ch: Channel) {
        lock.lock()
        _channel = ch
        lock.unlock()
    }

    private func getChannel() -> Channel? {
        lock.lock()
        defer { lock.unlock() }
        return _channel
    }

    public func connect(on group: EventLoopGroup) async throws -> Channel {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let decoder = ByteToMessageHandler(PeerMessageDecoder())
                let encoder = PeerMessageEncoder()
                return channel.pipeline.addHandler(decoder).flatMap { _ in
                    channel.pipeline.addHandler(encoder)
                }
            }
        let ch = try await bootstrap.connect(host: address, port: Int(port)).get()

        setChannel(ch)

        // Send handshake
        let handshake = Handshake(infoHash: infoHash, peerID: peerID)
        var buffer = ch.allocator.buffer(capacity: Handshake.length)
        buffer.writeBytes(handshake.encode())
        try await ch.writeAndFlush(buffer).get()

        return ch
    }

    public func send(_ message: PeerMessage) async throws {
        guard let ch = getChannel() else {
            throw PeerConnectionError.notConnected
        }
        try await ch.writeAndFlush(message).get()
    }

    public func close() async throws {
        guard let ch = getChannel() else { return }
        try await ch.close().get()
    }
}

public enum PeerConnectionError: Error {
    case notConnected
    case handshakeFailed
}

// MARK: - NIO Channel Handlers

/// Decodes peer wire protocol messages from byte stream.
final class PeerMessageDecoder: ByteToMessageDecoder {
    typealias InboundOut = PeerMessage

    private var handshakeReceived = false

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if !handshakeReceived {
            guard buffer.readableBytes >= Handshake.length else { return .needMoreData }
            guard let bytes = buffer.readBytes(length: Handshake.length) else { return .needMoreData }
            let _ = try Handshake.decode(from: Data(bytes))
            handshakeReceived = true
            return .continue
        }

        guard buffer.readableBytes >= 4 else { return .needMoreData }
        let lengthBytes = buffer.getBytes(at: buffer.readerIndex, length: 4)!
        let length = Data(lengthBytes).readUInt32BE(at: 0)

        if length == 0 {
            buffer.moveReaderIndex(forwardBy: 4)
            context.fireChannelRead(wrapInboundOut(.keepAlive))
            return .continue
        }

        guard buffer.readableBytes >= 4 + Int(length) else { return .needMoreData }
        buffer.moveReaderIndex(forwardBy: 4)
        guard let payload = buffer.readBytes(length: Int(length)) else { return .needMoreData }
        let message = try PeerMessage.decode(from: Data(payload))
        context.fireChannelRead(wrapInboundOut(message))
        return .continue
    }
}

/// Encodes peer wire protocol messages to byte stream.
final class PeerMessageEncoder: ChannelOutboundHandler {
    typealias OutboundIn = PeerMessage
    typealias OutboundOut = ByteBuffer

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let msg = unwrapOutboundIn(data)
        let encoded = msg.encode()
        var buffer = context.channel.allocator.buffer(capacity: encoded.count)
        buffer.writeBytes(encoded)
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}
