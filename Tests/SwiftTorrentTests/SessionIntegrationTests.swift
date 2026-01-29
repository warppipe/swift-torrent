import XCTest
@testable import SwiftTorrent

final class SessionIntegrationTests: XCTestCase {
    func testCreateSession() async throws {
        let settings = SessionSettings(listenPort: 0, dhtEnabled: false)
        let session = Session(settings: settings)

        let torrents = await session.allTorrents()
        XCTAssertTrue(torrents.isEmpty)
    }

    func testHandshakeRoundTrip() throws {
        let infoHash = Data(repeating: 0xAB, count: 20)
        let peerID = Data(repeating: 0xCD, count: 20)

        let handshake = Handshake(infoHash: infoHash, peerID: peerID)
        let encoded = handshake.encode()
        XCTAssertEqual(encoded.count, Handshake.length)

        let decoded = try Handshake.decode(from: encoded)
        XCTAssertEqual(decoded.infoHash, infoHash)
        XCTAssertEqual(decoded.peerID, peerID)
        XCTAssertEqual(decoded, handshake)
    }

    func testGeneratePeerID() {
        let id = generatePeerID()
        XCTAssertEqual(id.count, 20)
        XCTAssertTrue(id.starts(with: Data("-ST0001-".utf8)))
    }

    func testResumeDataRoundTrip() throws {
        let hash = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        var pieces = Bitfield(count: 16)
        pieces.set(0)
        pieces.set(5)
        pieces.set(15)

        let original = ResumeData(
            infoHash: hash, completedPieces: pieces,
            uploaded: 1000, downloaded: 5000, savePath: "/tmp/test"
        )

        let encoded = original.encode()
        let decoded = try ResumeData.decode(from: encoded)

        XCTAssertEqual(decoded.infoHash, hash)
        XCTAssertEqual(decoded.uploaded, 1000)
        XCTAssertEqual(decoded.downloaded, 5000)
        XCTAssertEqual(decoded.savePath, "/tmp/test")
    }

    func testFileStorageSlices() {
        let files = [
            TorrentInfo.FileEntry(path: "file1.txt", length: 100, offset: 0),
            TorrentInfo.FileEntry(path: "file2.txt", length: 200, offset: 100),
        ]
        let storage = FileStorage(files: files, pieceLength: 150, totalSize: 300)

        XCTAssertEqual(storage.pieceCount, 2)
        XCTAssertEqual(storage.pieceSize(0), 150)
        XCTAssertEqual(storage.pieceSize(1), 150)

        // First piece spans file1 (100 bytes) and file2 (50 bytes)
        let slices0 = storage.fileSlices(forPiece: 0)
        XCTAssertEqual(slices0.count, 2)
        XCTAssertEqual(slices0[0].path, "file1.txt")
        XCTAssertEqual(slices0[0].length, 100)
        XCTAssertEqual(slices0[1].path, "file2.txt")
        XCTAssertEqual(slices0[1].length, 50)
    }

    func testDHTMessageRoundTrip() throws {
        let txID = Data([0x01, 0x02])
        let msg = DHTMessage.query(
            transactionID: txID,
            queryType: .ping,
            arguments: [(key: Data("id".utf8), value: .string(Data(repeating: 0xAA, count: 20)))]
        )
        let encoded = msg.encode()
        let decoded = try DHTMessage.decode(from: encoded)

        if case .query(let decodedTxID, let queryType, _) = decoded {
            XCTAssertEqual(decodedTxID, txID)
            XCTAssertEqual(queryType, .ping)
        } else {
            XCTFail("Expected query message")
        }
    }
}
