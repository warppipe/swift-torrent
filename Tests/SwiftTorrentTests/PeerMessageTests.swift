import XCTest
@testable import SwiftTorrent

final class PeerMessageTests: XCTestCase {
    func testKeepAlive() throws {
        let msg = PeerMessage.keepAlive
        let data = msg.encode()
        XCTAssertEqual(data.count, 4)
        // Length prefix should be 0
        XCTAssertEqual(data.readUInt32BE(at: 0), 0)
        let decoded = try PeerMessage.decode(from: Data())
        XCTAssertEqual(decoded, .keepAlive)
    }

    func testChoke() throws {
        let msg = PeerMessage.choke
        let data = msg.encode()
        XCTAssertEqual(data.readUInt32BE(at: 0), 1) // length
        XCTAssertEqual(data[4], PeerMessage.chokeID)
        let decoded = try PeerMessage.decode(from: Data([PeerMessage.chokeID]))
        XCTAssertEqual(decoded, .choke)
    }

    func testUnchoke() throws {
        let decoded = try PeerMessage.decode(from: Data([PeerMessage.unchokeID]))
        XCTAssertEqual(decoded, .unchoke)
    }

    func testInterested() throws {
        let decoded = try PeerMessage.decode(from: Data([PeerMessage.interestedID]))
        XCTAssertEqual(decoded, .interested)
    }

    func testNotInterested() throws {
        let decoded = try PeerMessage.decode(from: Data([PeerMessage.notInterestedID]))
        XCTAssertEqual(decoded, .notInterested)
    }

    func testHave() throws {
        let msg = PeerMessage.have(pieceIndex: 42)
        let data = msg.encode()
        let payload = data.dropFirst(4) // skip length
        let decoded = try PeerMessage.decode(from: Data(payload))
        XCTAssertEqual(decoded, msg)
    }

    func testRequest() throws {
        let msg = PeerMessage.request(index: 1, begin: 0, length: 16384)
        let data = msg.encode()
        let payload = data.dropFirst(4)
        let decoded = try PeerMessage.decode(from: Data(payload))
        XCTAssertEqual(decoded, msg)
    }

    func testPiece() throws {
        let block = Data([1, 2, 3, 4, 5])
        let msg = PeerMessage.piece(index: 0, begin: 0, block: block)
        let data = msg.encode()
        let payload = data.dropFirst(4)
        let decoded = try PeerMessage.decode(from: Data(payload))
        XCTAssertEqual(decoded, msg)
    }

    func testCancel() throws {
        let msg = PeerMessage.cancel(index: 1, begin: 0, length: 16384)
        let data = msg.encode()
        let payload = data.dropFirst(4)
        let decoded = try PeerMessage.decode(from: Data(payload))
        XCTAssertEqual(decoded, msg)
    }

    func testPort() throws {
        let msg = PeerMessage.port(6881)
        let data = msg.encode()
        let payload = data.dropFirst(4)
        let decoded = try PeerMessage.decode(from: Data(payload))
        XCTAssertEqual(decoded, msg)
    }

    func testUnknownMessageID() {
        XCTAssertThrowsError(try PeerMessage.decode(from: Data([255])))
    }
}
