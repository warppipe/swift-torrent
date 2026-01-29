import XCTest
@testable import SwiftTorrent

final class BitfieldTests: XCTestCase {
    func testBasicOperations() {
        var bf = Bitfield(count: 100)
        XCTAssertEqual(bf.count, 100)
        XCTAssertTrue(bf.isEmpty)
        XCTAssertFalse(bf.get(0))

        bf.set(0)
        XCTAssertTrue(bf.get(0))
        XCTAssertEqual(bf.popcount, 1)

        bf.set(99)
        XCTAssertTrue(bf.get(99))
        XCTAssertEqual(bf.popcount, 2)

        bf.clear(0)
        XCTAssertFalse(bf.get(0))
        XCTAssertEqual(bf.popcount, 1)
    }

    func testAllSet() {
        var bf = Bitfield(count: 8)
        for i in 0..<8 { bf.set(i) }
        XCTAssertTrue(bf.allSet)
    }

    func testOutOfBounds() {
        var bf = Bitfield(count: 10)
        bf.set(100) // should be no-op
        XCTAssertFalse(bf.get(100))
        XCTAssertFalse(bf.get(-1))
    }

    func testDataRoundTrip() {
        var bf = Bitfield(count: 16)
        bf.set(0)
        bf.set(7)
        bf.set(8)
        bf.set(15)

        let data = bf.toData()
        XCTAssertEqual(data.count, 2)

        let bf2 = Bitfield(data: data, count: 16)
        XCTAssertTrue(bf2.get(0))
        XCTAssertTrue(bf2.get(7))
        XCTAssertTrue(bf2.get(8))
        XCTAssertTrue(bf2.get(15))
        XCTAssertFalse(bf2.get(1))
        XCTAssertEqual(bf2.popcount, 4)
    }

    func testLargeCount() {
        var bf = Bitfield(count: 1000)
        bf.set(999)
        XCTAssertTrue(bf.get(999))
        XCTAssertEqual(bf.popcount, 1)
    }
}
