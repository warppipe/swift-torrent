import Foundation
import Crypto

/// BEP-9 ut_metadata implementation for fetching torrent metadata via magnet links.
public actor MetadataExchange {
    private let infoHash: InfoHash
    private let localMetadataID: UInt8 = 1

    private var peerMetadataID: UInt8?
    private var metadataSize: Int?
    private var metadataPieces: [Int: Data] = [:]
    private var totalPieces: Int = 0
    private var isComplete: Bool = false

    public static let metadataPieceSize = 16384

    public enum Result {
        case none
        case sendMessage(PeerMessage)
        case requestMore([PeerMessage])
        case metadataComplete(TorrentInfo)
    }

    public init(infoHash: InfoHash) {
        self.infoHash = infoHash
    }

    /// Build extended handshake payload (bencoded).
    public func buildExtendedHandshake() -> Data {
        let encoder = BencodeEncoder()
        let msg = BencodeValue.dictionary([
            (key: Data("m".utf8), value: BencodeValue.dictionary([
                (key: Data("ut_metadata".utf8), value: .integer(Int64(localMetadataID)))
            ]))
        ])
        return encoder.encode(msg)
    }

    /// Handle an incoming extended message.
    public func handleExtendedMessage(id: UInt8, payload: Data) -> Result {
        if id == 0 {
            return handleExtendedHandshake(payload: payload)
        } else if id == localMetadataID {
            return handleMetadataMessage(payload: payload)
        }
        return .none
    }

    private func handleExtendedHandshake(payload: Data) -> Result {
        let decoder = BencodeDecoder()
        guard let value = try? decoder.decode(payload) else { return .none }

        // Extract peer's ut_metadata ID
        if let m = value["m"],
           let utMetadata = m["ut_metadata"]?.integerValue {
            peerMetadataID = UInt8(utMetadata)
        }

        // Extract metadata_size
        if let size = value["metadata_size"]?.integerValue {
            metadataSize = Int(size)
            totalPieces = (Int(size) + Self.metadataPieceSize - 1) / Self.metadataPieceSize
        }

        // If we have both, start requesting metadata pieces
        guard let peerID = peerMetadataID, metadataSize != nil else { return .none }

        var requests: [PeerMessage] = []
        for piece in 0..<totalPieces {
            let requestPayload = buildMetadataRequest(piece: piece, peerMetadataID: peerID)
            requests.append(.extended(id: peerID, payload: requestPayload))
        }
        return .requestMore(requests)
    }

    private func handleMetadataMessage(payload: Data) -> Result {
        let decoder = BencodeDecoder()
        // The payload is: bencoded dict + raw data
        // We need to find where the bencoded dict ends
        guard let (value, range) = try? decoder.decodeWithRange(payload) else { return .none }

        guard let msgType = value["msg_type"]?.integerValue,
              let piece = value["piece"]?.integerValue else { return .none }

        let pieceIndex = Int(piece)

        switch msgType {
        case 1: // data
            let dataStart = range.upperBound
            let pieceData = Data(payload[dataStart...])
            metadataPieces[pieceIndex] = pieceData

            // Check if we have all pieces
            if metadataPieces.count == totalPieces {
                return assembleMetadata()
            }
            return .none

        case 2: // reject
            return .none

        default:
            return .none
        }
    }

    private func assembleMetadata() -> Result {
        var assembled = Data()
        for i in 0..<totalPieces {
            guard let piece = metadataPieces[i] else { return .none }
            assembled.append(piece)
        }

        // Verify SHA-1 matches info hash
        let hash = Data(Insecure.SHA1.hash(data: assembled))
        guard hash == infoHash.bytes else {
            metadataPieces.removeAll()
            return .none
        }

        isComplete = true

        // Parse into TorrentInfo
        guard let info = try? parseInfoFromMetadata(assembled) else { return .none }
        return .metadataComplete(info)
    }

    private func parseInfoFromMetadata(_ data: Data) throws -> TorrentInfo {
        let decoder = BencodeDecoder()
        let infoValue = try decoder.decode(data)

        guard case .dictionary = infoValue else {
            throw TorrentInfoError.invalidFormat("Metadata is not a dictionary")
        }
        guard let nameValue = infoValue["name"], let name = nameValue.utf8String else {
            throw TorrentInfoError.invalidFormat("Missing 'name'")
        }
        guard let plValue = infoValue["piece length"], let pieceLength = plValue.integerValue else {
            throw TorrentInfoError.invalidFormat("Missing 'piece length'")
        }
        guard let piecesValue = infoValue["pieces"], let pieces = piecesValue.stringValue else {
            throw TorrentInfoError.invalidFormat("Missing 'pieces'")
        }

        let isPrivate = infoValue["private"]?.integerValue == 1

        var files: [TorrentInfo.FileEntry] = []
        var totalSize: Int64 = 0

        if let filesValue = infoValue["files"]?.listValue {
            for fileValue in filesValue {
                guard let length = fileValue["length"]?.integerValue,
                      let pathList = fileValue["path"]?.listValue else {
                    throw TorrentInfoError.invalidFormat("Invalid file entry")
                }
                let pathComponents = pathList.compactMap { $0.utf8String }
                let path = ([name] + pathComponents).joined(separator: "/")
                files.append(TorrentInfo.FileEntry(path: path, length: length, offset: totalSize))
                totalSize += length
            }
        } else if let length = infoValue["length"]?.integerValue {
            files.append(TorrentInfo.FileEntry(path: name, length: length, offset: 0))
            totalSize = length
        } else {
            throw TorrentInfoError.invalidFormat("Missing 'length' or 'files'")
        }

        return TorrentInfo(
            infoHash: infoHash, name: name, pieceLength: Int(pieceLength),
            pieces: pieces, totalSize: totalSize, files: files,
            isPrivate: isPrivate, comment: nil, createdBy: nil,
            creationDate: nil, announceURL: nil, announceList: []
        )
    }

    private func buildMetadataRequest(piece: Int, peerMetadataID: UInt8) -> Data {
        let encoder = BencodeEncoder()
        let msg = BencodeValue.dictionary([
            (key: Data("msg_type".utf8), value: .integer(0)), // request
            (key: Data("piece".utf8), value: .integer(Int64(piece)))
        ])
        return encoder.encode(msg)
    }
}
