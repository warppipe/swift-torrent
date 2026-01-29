import XCTest
@testable import SwiftTorrent

final class MagnetLinkTests: XCTestCase {
    func testParseBasicMagnet() {
        let uri = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=TestFile"
        let magnet = MagnetLink(uri: uri)
        XCTAssertNotNil(magnet)
        XCTAssertEqual(magnet?.displayName, "TestFile")
        XCTAssertEqual(magnet?.infoHash.description, "0123456789abcdef0123456789abcdef01234567")
    }

    func testParseWithTrackers() {
        let uri = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.example.com/announce&tr=http://tracker2.example.com/announce"
        let magnet = MagnetLink(uri: uri)
        XCTAssertNotNil(magnet)
        XCTAssertEqual(magnet?.trackers.count, 2)
    }

    func testInvalidMagnet() {
        XCTAssertNil(MagnetLink(uri: "not a magnet"))
        XCTAssertNil(MagnetLink(uri: "magnet:?foo=bar"))
    }

    func testGenerateURI() {
        let hash = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        let magnet = MagnetLink(infoHash: hash, displayName: "Test")
        let uri = magnet.uri
        XCTAssertTrue(uri.hasPrefix("magnet:?"))
        XCTAssertTrue(uri.contains("xt=urn:btih:"))
        XCTAssertTrue(uri.contains("dn=Test"))
    }

    func testBase32Decode() {
        // "ORSXG5A=" is base32 for "test"
        let decoded = MagnetLink.base32Decode("ORSXG5A")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "test")
    }

    func testRoundTrip() {
        let hash = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        let original = MagnetLink(infoHash: hash, displayName: "MyTorrent", trackers: ["http://tracker.example.com/announce"])
        let uri = original.uri
        let parsed = MagnetLink(uri: uri)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.infoHash, original.infoHash)
        XCTAssertEqual(parsed?.displayName, "MyTorrent")
    }
}
