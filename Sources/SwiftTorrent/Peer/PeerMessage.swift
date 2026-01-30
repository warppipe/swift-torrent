import Foundation

/// All peer wire protocol messages (BEP-3).
public enum PeerMessage: Equatable, Sendable {
    case keepAlive
    case choke
    case unchoke
    case interested
    case notInterested
    case have(pieceIndex: UInt32)
    case bitfield(Data)
    case request(index: UInt32, begin: UInt32, length: UInt32)
    case piece(index: UInt32, begin: UInt32, block: Data)
    case cancel(index: UInt32, begin: UInt32, length: UInt32)
    case port(UInt16)
    case extended(id: UInt8, payload: Data)

    // Message IDs
    public static let chokeID: UInt8 = 0
    public static let unchokeID: UInt8 = 1
    public static let interestedID: UInt8 = 2
    public static let notInterestedID: UInt8 = 3
    public static let haveID: UInt8 = 4
    public static let bitfieldID: UInt8 = 5
    public static let requestID: UInt8 = 6
    public static let pieceID: UInt8 = 7
    public static let cancelID: UInt8 = 8
    public static let portID: UInt8 = 9
    public static let extendedID: UInt8 = 20

    /// Serialize to wire format: <length prefix><message ID><payload>
    public func encode() -> Data {
        var data = Data()
        switch self {
        case .keepAlive:
            data.append(contentsOf: UInt32(0).bigEndianBytes)

        case .choke:
            data.append(contentsOf: UInt32(1).bigEndianBytes)
            data.append(Self.chokeID)

        case .unchoke:
            data.append(contentsOf: UInt32(1).bigEndianBytes)
            data.append(Self.unchokeID)

        case .interested:
            data.append(contentsOf: UInt32(1).bigEndianBytes)
            data.append(Self.interestedID)

        case .notInterested:
            data.append(contentsOf: UInt32(1).bigEndianBytes)
            data.append(Self.notInterestedID)

        case .have(let index):
            data.append(contentsOf: UInt32(5).bigEndianBytes)
            data.append(Self.haveID)
            data.append(contentsOf: index.bigEndianBytes)

        case .bitfield(let bf):
            data.append(contentsOf: UInt32(1 + UInt32(bf.count)).bigEndianBytes)
            data.append(Self.bitfieldID)
            data.append(bf)

        case .request(let index, let begin, let length):
            data.append(contentsOf: UInt32(13).bigEndianBytes)
            data.append(Self.requestID)
            data.append(contentsOf: index.bigEndianBytes)
            data.append(contentsOf: begin.bigEndianBytes)
            data.append(contentsOf: length.bigEndianBytes)

        case .piece(let index, let begin, let block):
            data.append(contentsOf: UInt32(9 + UInt32(block.count)).bigEndianBytes)
            data.append(Self.pieceID)
            data.append(contentsOf: index.bigEndianBytes)
            data.append(contentsOf: begin.bigEndianBytes)
            data.append(block)

        case .cancel(let index, let begin, let length):
            data.append(contentsOf: UInt32(13).bigEndianBytes)
            data.append(Self.cancelID)
            data.append(contentsOf: index.bigEndianBytes)
            data.append(contentsOf: begin.bigEndianBytes)
            data.append(contentsOf: length.bigEndianBytes)

        case .port(let port):
            data.append(contentsOf: UInt32(3).bigEndianBytes)
            data.append(Self.portID)
            data.append(contentsOf: port.bigEndianBytes)

        case .extended(let id, let payload):
            data.append(contentsOf: UInt32(2 + UInt32(payload.count)).bigEndianBytes)
            data.append(Self.extendedID)
            data.append(id)
            data.append(payload)
        }
        return data
    }

    /// Parse a message from payload (after length prefix has been consumed).
    /// `payload` does NOT include the 4-byte length prefix.
    public static func decode(from payload: Data) throws -> PeerMessage {
        guard !payload.isEmpty else { return .keepAlive }
        let id = payload[payload.startIndex]
        let rest = payload.dropFirst()

        switch id {
        case chokeID: return .choke
        case unchokeID: return .unchoke
        case interestedID: return .interested
        case notInterestedID: return .notInterested

        case haveID:
            guard rest.count >= 4 else { throw PeerMessageError.invalidPayload }
            return .have(pieceIndex: rest.readUInt32BE(at: 0))

        case bitfieldID:
            return .bitfield(Data(rest))

        case requestID:
            guard rest.count >= 12 else { throw PeerMessageError.invalidPayload }
            return .request(
                index: rest.readUInt32BE(at: 0),
                begin: rest.readUInt32BE(at: 4),
                length: rest.readUInt32BE(at: 8)
            )

        case pieceID:
            guard rest.count >= 8 else { throw PeerMessageError.invalidPayload }
            return .piece(
                index: rest.readUInt32BE(at: 0),
                begin: rest.readUInt32BE(at: 4),
                block: Data(rest.dropFirst(8))
            )

        case cancelID:
            guard rest.count >= 12 else { throw PeerMessageError.invalidPayload }
            return .cancel(
                index: rest.readUInt32BE(at: 0),
                begin: rest.readUInt32BE(at: 4),
                length: rest.readUInt32BE(at: 8)
            )

        case portID:
            guard rest.count >= 2 else { throw PeerMessageError.invalidPayload }
            return .port(rest.readUInt16BE(at: 0))

        case extendedID:
            guard rest.count >= 1 else { throw PeerMessageError.invalidPayload }
            let extID = rest[rest.startIndex]
            return .extended(id: extID, payload: Data(rest.dropFirst()))

        default:
            throw PeerMessageError.unknownMessageID(id)
        }
    }
}

public enum PeerMessageError: Error, Equatable {
    case invalidPayload
    case unknownMessageID(UInt8)
}

// MARK: - Data helpers

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be) { Array($0) }
    }
}

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be) { Array($0) }
    }
}

extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        let start = self.startIndex + offset
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buf in
            self.copyBytes(to: buf, from: start..<start+4)
        }
        return UInt32(bigEndian: value)
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        let start = self.startIndex + offset
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buf in
            self.copyBytes(to: buf, from: start..<start+2)
        }
        return UInt16(bigEndian: value)
    }
}
