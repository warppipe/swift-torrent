import Foundation
import Crypto

/// Represents a parsed .torrent file.
public struct TorrentInfo: Sendable {
    public let infoHash: InfoHash
    public let name: String
    public let pieceLength: Int
    public let pieces: Data  // concatenated SHA-1 hashes, 20 bytes each
    public let totalSize: Int64
    public let files: [FileEntry]
    public let isPrivate: Bool
    public let comment: String?
    public let createdBy: String?
    public let creationDate: Date?
    public let announceURL: String?
    public let announceList: [[String]]

    /// A single file within the torrent.
    public struct FileEntry: Sendable {
        public let path: String
        public let length: Int64
        public let offset: Int64  // byte offset within the torrent data
    }

    public var pieceCount: Int {
        pieces.count / 20
    }

    /// Parse a .torrent file from raw data.
    public static func parse(from data: Data) throws -> TorrentInfo {
        let decoder = BencodeDecoder()
        let root = try decoder.decode(data)

        guard case .dictionary = root else {
            throw TorrentInfoError.invalidFormat("Root is not a dictionary")
        }
        guard let infoValue = root["info"],
              case .dictionary = infoValue else {
            throw TorrentInfoError.invalidFormat("Missing 'info' dictionary")
        }

        // Find the raw bytes of the info dictionary for hashing
        let infoData = try findInfoDictBytes(in: data)
        let infoHash = InfoHash.v1(from: infoData)

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

        // Parse files
        var files: [FileEntry] = []
        var totalSize: Int64 = 0

        if let filesValue = infoValue["files"]?.listValue {
            // Multi-file torrent
            for fileValue in filesValue {
                guard let length = fileValue["length"]?.integerValue,
                      let pathList = fileValue["path"]?.listValue else {
                    throw TorrentInfoError.invalidFormat("Invalid file entry")
                }
                let pathComponents = pathList.compactMap { $0.utf8String }
                let path = ([name] + pathComponents).joined(separator: "/")
                files.append(FileEntry(path: path, length: length, offset: totalSize))
                totalSize += length
            }
        } else if let length = infoValue["length"]?.integerValue {
            // Single-file torrent
            files.append(FileEntry(path: name, length: length, offset: 0))
            totalSize = length
        } else {
            throw TorrentInfoError.invalidFormat("Missing 'length' or 'files'")
        }

        let comment = root["comment"]?.utf8String
        let createdBy = root["created by"]?.utf8String
        let creationDate: Date? = root["creation date"]?.integerValue.map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
        let announceURL = root["announce"]?.utf8String
        var announceList: [[String]] = []
        if let al = root["announce-list"]?.listValue {
            for tier in al {
                if let urls = tier.listValue {
                    announceList.append(urls.compactMap { $0.utf8String })
                }
            }
        }

        return TorrentInfo(
            infoHash: infoHash, name: name, pieceLength: Int(pieceLength),
            pieces: pieces, totalSize: totalSize, files: files,
            isPrivate: isPrivate, comment: comment, createdBy: createdBy,
            creationDate: creationDate, announceURL: announceURL,
            announceList: announceList
        )
    }

    /// Extract raw bytes of the "info" dictionary value from bencoded data.
    private static func findInfoDictBytes(in data: Data) throws -> Data {
        // Search for "4:info" key then capture the value
        guard let range = data.range(of: Data("4:info".utf8)) else {
            throw TorrentInfoError.invalidFormat("Cannot find info key")
        }
        let valueStart = range.upperBound
        // Parse from valueStart to find where the value ends
        var index = valueStart
        try skipBencodeValue(data, index: &index)
        return Data(data[valueStart..<index])
    }

    private static func skipBencodeValue(_ data: Data, index: inout Data.Index) throws {
        guard index < data.endIndex else { throw BencodeError.unexpectedEnd }
        switch data[index] {
        case UInt8(ascii: "i"):
            guard let end = data[index...].firstIndex(of: UInt8(ascii: "e")) else {
                throw BencodeError.unexpectedEnd
            }
            index = data.index(after: end)
        case UInt8(ascii: "l"), UInt8(ascii: "d"):
            index = data.index(after: index)
            while index < data.endIndex && data[index] != UInt8(ascii: "e") {
                try skipBencodeValue(data, index: &index)
            }
            guard index < data.endIndex else { throw BencodeError.unexpectedEnd }
            index = data.index(after: index)
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            guard let colon = data[index...].firstIndex(of: UInt8(ascii: ":")) else {
                throw BencodeError.unexpectedEnd
            }
            guard let lenStr = String(data: data[index..<colon], encoding: .ascii),
                  let len = Int(lenStr) else {
                throw BencodeError.invalidStringLength
            }
            index = data.index(colon, offsetBy: 1 + len)
        default:
            throw BencodeError.invalidFormat("Unexpected byte in skip")
        }
    }
}

public enum TorrentInfoError: Error, Equatable {
    case invalidFormat(String)
}
