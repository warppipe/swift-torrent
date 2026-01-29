import XCTest
@testable import SwiftTorrent

final class TorrentInfoTests: XCTestCase {
    /// Create a minimal valid single-file .torrent bencoded data.
    private func makeSingleFileTorrent() -> Data {
        // Manually construct bencoded data for a simple torrent
        let encoder = BencodeEncoder()
        let pieces = Data(repeating: 0xAB, count: 20) // one fake piece hash

        let info: BencodeValue = .dictionary([
            (key: Data("length".utf8), value: .integer(1024)),
            (key: Data("name".utf8), value: .string(Data("testfile.txt".utf8))),
            (key: Data("piece length".utf8), value: .integer(262144)),
            (key: Data("pieces".utf8), value: .string(pieces)),
        ])

        let root: BencodeValue = .dictionary([
            (key: Data("announce".utf8), value: .string(Data("http://tracker.example.com/announce".utf8))),
            (key: Data("info".utf8), value: info),
        ])

        return encoder.encode(root)
    }

    func testParseSingleFile() throws {
        let data = makeSingleFileTorrent()
        let info = try TorrentInfo.parse(from: data)

        XCTAssertEqual(info.name, "testfile.txt")
        XCTAssertEqual(info.pieceLength, 262144)
        XCTAssertEqual(info.totalSize, 1024)
        XCTAssertEqual(info.files.count, 1)
        XCTAssertEqual(info.files[0].path, "testfile.txt")
        XCTAssertEqual(info.files[0].length, 1024)
        XCTAssertEqual(info.announceURL, "http://tracker.example.com/announce")
        XCTAssertFalse(info.isPrivate)
        XCTAssertEqual(info.pieceCount, 1)
    }

    func testParseMultiFile() throws {
        let encoder = BencodeEncoder()
        let pieces = Data(repeating: 0xCD, count: 20)

        let file1: BencodeValue = .dictionary([
            (key: Data("length".utf8), value: .integer(500)),
            (key: Data("path".utf8), value: .list([.string(Data("sub".utf8)), .string(Data("file1.txt".utf8))])),
        ])
        let file2: BencodeValue = .dictionary([
            (key: Data("length".utf8), value: .integer(300)),
            (key: Data("path".utf8), value: .list([.string(Data("file2.txt".utf8))])),
        ])

        let info: BencodeValue = .dictionary([
            (key: Data("files".utf8), value: .list([file1, file2])),
            (key: Data("name".utf8), value: .string(Data("mydir".utf8))),
            (key: Data("piece length".utf8), value: .integer(262144)),
            (key: Data("pieces".utf8), value: .string(pieces)),
        ])

        let root: BencodeValue = .dictionary([
            (key: Data("announce".utf8), value: .string(Data("http://t.example.com/a".utf8))),
            (key: Data("info".utf8), value: info),
        ])

        let data = encoder.encode(root)
        let parsed = try TorrentInfo.parse(from: data)

        XCTAssertEqual(parsed.name, "mydir")
        XCTAssertEqual(parsed.files.count, 2)
        XCTAssertEqual(parsed.files[0].path, "mydir/sub/file1.txt")
        XCTAssertEqual(parsed.files[1].path, "mydir/file2.txt")
        XCTAssertEqual(parsed.totalSize, 800)
    }

    func testInfoHashConsistency() throws {
        let data = makeSingleFileTorrent()
        let info1 = try TorrentInfo.parse(from: data)
        let info2 = try TorrentInfo.parse(from: data)
        XCTAssertEqual(info1.infoHash, info2.infoHash)
    }
}
