import XCTest
@testable import SwiftTorrent

final class InfoHashTests: XCTestCase {
    func testFromHex() {
        let hash = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")
        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.bytes.count, 20)
        XCTAssertEqual(hash?.version, .v1)
    }

    func testInvalidHex() {
        XCTAssertNil(InfoHash(hex: "short"))
        XCTAssertNil(InfoHash(hex: "xyz"))
    }

    func testV1Hash() {
        let data = Data("test info dictionary".utf8)
        let hash = InfoHash.v1(from: data)
        XCTAssertEqual(hash.bytes.count, 20)
        XCTAssertEqual(hash.version, .v1)
    }

    func testV2Hash() {
        let data = Data("test info dictionary".utf8)
        let hash = InfoHash.v2(from: data)
        XCTAssertEqual(hash.bytes.count, 32)
        XCTAssertEqual(hash.version, .v2)
    }

    func testDescription() {
        let hash = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        XCTAssertEqual(hash.description, "0123456789abcdef0123456789abcdef01234567")
    }

    func testEquatable() {
        let h1 = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        let h2 = InfoHash(hex: "0123456789abcdef0123456789abcdef01234567")!
        let h3 = InfoHash(hex: "abcdef0123456789abcdef0123456789abcdef01")!
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, h3)
    }
}
