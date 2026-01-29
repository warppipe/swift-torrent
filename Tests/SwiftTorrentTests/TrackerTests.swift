import XCTest
@testable import SwiftTorrent

final class TrackerTests: XCTestCase {
    func testParseCompactPeers() throws {
        // Create a mock bencoded tracker response with compact peers
        let encoder = BencodeEncoder()

        // 6 bytes: 192.168.1.1:6881
        var peerData = Data()
        peerData.append(contentsOf: [192, 168, 1, 1])
        peerData.append(contentsOf: UInt16(6881).bigEndianBytes)
        // 6 bytes: 10.0.0.1:8080
        peerData.append(contentsOf: [10, 0, 0, 1])
        peerData.append(contentsOf: UInt16(8080).bigEndianBytes)

        let response: BencodeValue = .dictionary([
            (key: Data("complete".utf8), value: .integer(10)),
            (key: Data("incomplete".utf8), value: .integer(5)),
            (key: Data("interval".utf8), value: .integer(1800)),
            (key: Data("peers".utf8), value: .string(peerData)),
        ])

        let data = encoder.encode(response)
        let decoded = try BencodeDecoder().decode(data)

        // Verify structure
        XCTAssertEqual(decoded["interval"]?.integerValue, 1800)
        XCTAssertEqual(decoded["complete"]?.integerValue, 10)
        XCTAssertEqual(decoded["peers"]?.stringValue?.count, 12)
    }

    func testTrackerErrorResponse() throws {
        let encoder = BencodeEncoder()
        let response: BencodeValue = .dictionary([
            (key: Data("failure reason".utf8), value: .string(Data("Torrent not found".utf8))),
        ])
        let data = encoder.encode(response)
        let decoded = try BencodeDecoder().decode(data)
        XCTAssertEqual(decoded["failure reason"]?.utf8String, "Torrent not found")
    }
}
