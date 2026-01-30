import Foundation

/// BitTorrent handshake message.
public struct Handshake: Sendable, Equatable {
    public static let protocolString = "BitTorrent protocol"
    public static let length = 68  // 1 + 19 + 8 + 20 + 20

    public let infoHash: Data   // 20 bytes
    public let peerID: Data     // 20 bytes
    public let reserved: Data   // 8 bytes (extension bits)

    public static func defaultReserved() -> Data {
        var r = Data(count: 8)
        r[5] |= 0x10  // BEP-10 extension protocol
        return r
    }

    public init(infoHash: Data, peerID: Data, reserved: Data? = nil) {
        precondition(infoHash.count == 20)
        precondition(peerID.count == 20)
        self.infoHash = infoHash
        self.peerID = peerID
        self.reserved = reserved ?? Self.defaultReserved()
    }

    /// Encode to wire format.
    public func encode() -> Data {
        var data = Data(capacity: Self.length)
        data.append(UInt8(Self.protocolString.count))
        data.append(contentsOf: Self.protocolString.utf8)
        data.append(reserved)
        data.append(infoHash)
        data.append(peerID)
        return data
    }

    /// Decode from wire format.
    public static func decode(from data: Data) throws -> Handshake {
        guard data.count >= length else {
            throw HandshakeError.tooShort
        }
        let pstrLen = Int(data[data.startIndex])
        guard pstrLen == protocolString.count else {
            throw HandshakeError.invalidProtocol
        }
        let pstr = String(data: data[data.startIndex+1..<data.startIndex+1+pstrLen], encoding: .utf8)
        guard pstr == protocolString else {
            throw HandshakeError.invalidProtocol
        }
        let reservedStart = data.startIndex + 1 + pstrLen
        let reserved = Data(data[reservedStart..<reservedStart+8])
        let hashStart = reservedStart + 8
        let infoHash = Data(data[hashStart..<hashStart+20])
        let peerIDStart = hashStart + 20
        let peerID = Data(data[peerIDStart..<peerIDStart+20])
        return Handshake(infoHash: infoHash, peerID: peerID, reserved: reserved)
    }
}

public enum HandshakeError: Error, Equatable {
    case tooShort
    case invalidProtocol
}

/// Generate a random peer ID in Azureus style: -ST0001-<random 12 bytes>
public func generatePeerID() -> Data {
    var id = Data("-ST0001-".utf8)
    for _ in 0..<12 {
        id.append(UInt8.random(in: 0...255))
    }
    return id
}
