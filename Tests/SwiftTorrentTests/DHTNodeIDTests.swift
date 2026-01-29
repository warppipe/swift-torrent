import XCTest
@testable import SwiftTorrent

final class DHTNodeIDTests: XCTestCase {
    func testRandom() {
        let id1 = NodeID.random()
        let id2 = NodeID.random()
        XCTAssertEqual(id1.bytes.count, 20)
        XCTAssertNotEqual(id1, id2) // extremely unlikely to collide
    }

    func testDistanceSelf() {
        let id = NodeID.random()
        let dist = id.distance(to: id)
        XCTAssertEqual(dist, Data(count: 20))
    }

    func testDistanceSymmetry() {
        let a = NodeID.random()
        let b = NodeID.random()
        XCTAssertEqual(a.distance(to: b), b.distance(to: a))
    }

    func testBucketIndex() {
        let a = NodeID(bytes: Data(repeating: 0, count: 20))
        var bBytes = Data(repeating: 0, count: 20)
        bBytes[0] = 0x80 // highest bit set -> distance has bit 159 set
        let b = NodeID(bytes: bBytes)
        let idx = a.bucketIndex(relativeTo: b)
        XCTAssertEqual(idx, 159)
    }

    func testDistanceComparison() {
        let d1 = Data([0x00, 0x01])
        let d2 = Data([0x00, 0x02])
        XCTAssertTrue(distanceLessThan(d1, d2))
        XCTAssertFalse(distanceLessThan(d2, d1))
        XCTAssertFalse(distanceLessThan(d1, d1))
    }

    func testDescription() {
        let bytes = Data(repeating: 0xFF, count: 20)
        let id = NodeID(bytes: bytes)
        XCTAssertEqual(id.description, String(repeating: "ff", count: 20))
    }
}
