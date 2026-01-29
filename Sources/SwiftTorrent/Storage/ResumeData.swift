import Foundation

/// Save and restore torrent state via bencoding.
public struct ResumeData: Sendable {
    public let infoHash: InfoHash
    public let completedPieces: Bitfield
    public let uploaded: Int64
    public let downloaded: Int64
    public let savePath: String

    public init(infoHash: InfoHash, completedPieces: Bitfield,
                uploaded: Int64, downloaded: Int64, savePath: String) {
        self.infoHash = infoHash
        self.completedPieces = completedPieces
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.savePath = savePath
    }

    /// Encode to bencoded data.
    public func encode() -> Data {
        let piecesData = completedPieces.toData()
        let value: BencodeValue = .dictionary([
            (key: Data("completed_pieces".utf8), value: .string(piecesData)),
            (key: Data("downloaded".utf8), value: .integer(downloaded)),
            (key: Data("info_hash".utf8), value: .string(infoHash.bytes)),
            (key: Data("save_path".utf8), value: .string(Data(savePath.utf8))),
            (key: Data("uploaded".utf8), value: .integer(uploaded)),
        ])
        return BencodeEncoder().encode(value)
    }

    /// Decode from bencoded data.
    public static func decode(from data: Data) throws -> ResumeData {
        let decoder = BencodeDecoder()
        let value = try decoder.decode(data)

        guard let hashData = value["info_hash"]?.stringValue,
              let piecesData = value["completed_pieces"]?.stringValue,
              let uploaded = value["uploaded"]?.integerValue,
              let downloaded = value["downloaded"]?.integerValue,
              let savePath = value["save_path"]?.utf8String else {
            throw ResumeDataError.invalidFormat
        }

        let infoHash = InfoHash(bytes: hashData)
        let pieceCount = piecesData.count * 8
        let completedPieces = Bitfield(data: piecesData, count: pieceCount)

        return ResumeData(
            infoHash: infoHash, completedPieces: completedPieces,
            uploaded: uploaded, downloaded: downloaded, savePath: savePath
        )
    }
}

public enum ResumeDataError: Error {
    case invalidFormat
}
