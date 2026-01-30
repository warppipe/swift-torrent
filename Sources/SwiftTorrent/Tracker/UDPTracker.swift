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
        // Resolve hostname to IP address first
        let resolvedHost: String
        if host.first?.isLetter == true {
            // It's a hostname, resolve it
            resolvedHost = try await resolveHostname(host)
        } else {
            resolvedHost = host
        }

        let handler = UDPResponseHandler()
        let channel = try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(handler)
            }
            .bind(host: "0.0.0.0", port: 0)
            .get()

        defer {
            channel.close(promise: nil)
        }

        let remoteAddr = try SocketAddress(ipAddress: resolvedHost, port: port)

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

        // Read connect response (16 bytes: action(4) + txid(4) + connection_id(8))
        let connectResponse = try await handler.waitForResponse(timeout: .seconds(5))
        guard connectResponse.count >= 16 else {
            throw TrackerError.invalidResponse
        }
        let respAction = connectResponse.readUInt32BE(at: 0)
        let respTxID = connectResponse.readUInt32BE(at: 4)
        guard respAction == 0, respTxID == transactionID else {
            throw TrackerError.invalidResponse
        }
        let connectionID = connectResponse.readUInt64BE(at: 8)

        // Step 2: Announce request
        let announceTxID = UInt32.random(in: 0...UInt32.max)
        var announceReq = Data()
        announceReq.append(contentsOf: connectionID.bigEndianBytes)
        announceReq.append(contentsOf: UInt32(1).bigEndianBytes) // action: announce
        announceReq.append(contentsOf: announceTxID.bigEndianBytes)
        announceReq.append(params.infoHash.bytes)
        announceReq.append(params.peerID)
        announceReq.append(contentsOf: params.downloaded.bigEndianBytes)
        announceReq.append(contentsOf: params.left.bigEndianBytes)
        announceReq.append(contentsOf: params.uploaded.bigEndianBytes)
        announceReq.append(contentsOf: UInt32(2).bigEndianBytes) // event: started
        announceReq.append(contentsOf: UInt32(0).bigEndianBytes) // IP
        announceReq.append(contentsOf: UInt32.random(in: 0...UInt32.max).bigEndianBytes) // key
        announceReq.append(contentsOf: Int32(params.numWant).bigEndianBytes)
        announceReq.append(contentsOf: params.port.bigEndianBytes)

        var abuf = channel.allocator.buffer(capacity: announceReq.count)
        abuf.writeBytes(announceReq)
        let aenvelope = AddressedEnvelope(remoteAddress: remoteAddr, data: abuf)
        try await channel.writeAndFlush(aenvelope).get()

        // Read announce response (20+ bytes: action(4) + txid(4) + interval(4) + leechers(4) + seeders(4) + peers(6*N))
        let announceResponse = try await handler.waitForResponse(timeout: .seconds(5))
        guard announceResponse.count >= 20 else {
            throw TrackerError.invalidResponse
        }
        let annAction = announceResponse.readUInt32BE(at: 0)
        let annTxID = announceResponse.readUInt32BE(at: 4)
        guard annAction == 1, annTxID == announceTxID else {
            throw TrackerError.invalidResponse
        }

        let interval = Int(announceResponse.readUInt32BE(at: 8))
        let leechers = Int(announceResponse.readUInt32BE(at: 12))
        let seeders = Int(announceResponse.readUInt32BE(at: 16))

        // Parse compact peers (6 bytes each: 4 IP + 2 port)
        var peers: [(String, UInt16)] = []
        var offset = 20
        while offset + 6 <= announceResponse.count {
            let ip = "\(announceResponse[announceResponse.startIndex + offset]).\(announceResponse[announceResponse.startIndex + offset + 1]).\(announceResponse[announceResponse.startIndex + offset + 2]).\(announceResponse[announceResponse.startIndex + offset + 3])"
            let peerPort = announceResponse.readUInt16BE(at: offset + 4)
            peers.append((ip, peerPort))
            offset += 6
        }

        return AnnounceResponse(interval: interval, seeders: seeders, leechers: leechers, peers: peers)
    }

    private func resolveHostname(_ hostname: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = Int32(SOCK_DGRAM)
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &result)
                guard status == 0, let addrInfo = result else {
                    continuation.resume(throwing: TrackerError.connectionFailed)
                    return
                }
                defer { freeaddrinfo(result) }
                let addr = addrInfo.pointee.ai_addr!
                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, addrInfo.pointee.ai_addrlen, &hostBuf, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST)
                continuation.resume(returning: String(cString: hostBuf))
            }
        }
    }
}

/// NIO channel handler that collects UDP responses.
private final class UDPResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let lock = NSLock()
    private var continuations: [UInt64: CheckedContinuation<Data, Error>] = [:]
    private var nextID: UInt64 = 0
    private var receivedData: [Data] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        let responseData = Data(bytes)

        lock.lock()
        if let firstKey = continuations.keys.sorted().first {
            let cont = continuations.removeValue(forKey: firstKey)!
            lock.unlock()
            cont.resume(returning: responseData)
        } else {
            receivedData.append(responseData)
            lock.unlock()
        }
    }

    func waitForResponse(timeout: TimeAmount) async throws -> Data {
        // Check if we already have data
        lock.lock()
        if !receivedData.isEmpty {
            let data = receivedData.removeFirst()
            lock.unlock()
            return data
        }
        lock.unlock()

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !receivedData.isEmpty {
                let data = receivedData.removeFirst()
                lock.unlock()
                continuation.resume(returning: data)
            } else {
                let id = nextID
                nextID += 1
                continuations[id] = continuation
                lock.unlock()

                // Timeout
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    self.lock.lock()
                    if let cont = self.continuations.removeValue(forKey: id) {
                        self.lock.unlock()
                        cont.resume(throwing: TrackerError.connectionFailed)
                    } else {
                        self.lock.unlock()
                    }
                }
            }
        }
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

extension Data {
    func readUInt64BE(at offset: Int) -> UInt64 {
        let start = self.startIndex + offset
        var value: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buf in
            self.copyBytes(to: buf, from: start..<start+8)
        }
        return UInt64(bigEndian: value)
    }
}
