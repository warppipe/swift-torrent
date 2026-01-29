import XCTest
@testable import SwiftTorrent

final class DHTRoutingTableTests: XCTestCase {
    func testInsertAndFind() {
        let ownID = NodeID.random()
        var table = DHTRoutingTable(ownID: ownID)

        let node = DHTNodeEntry(id: NodeID.random(), address: "1.2.3.4", port: 6881)
        let inserted = table.insert(node)
        XCTAssertTrue(inserted)
        XCTAssertEqual(table.nodeCount, 1)
    }

    func testClosestNodes() {
        let ownID = NodeID.random()
        var table = DHTRoutingTable(ownID: ownID)

        for _ in 0..<20 {
            let node = DHTNodeEntry(id: NodeID.random(), address: "1.2.3.4", port: 6881)
            _ = table.insert(node)
        }

        let target = NodeID.random()
        let closest = table.closestNodes(to: target, count: 8)
        XCTAssertLessThanOrEqual(closest.count, 8)

        // Verify ordering: each should be closer than the next
        for i in 0..<closest.count - 1 {
            let d1 = closest[i].id.distance(to: target)
            let d2 = closest[i + 1].id.distance(to: target)
            XCTAssertTrue(distanceLessThan(d1, d2) || d1 == d2)
        }
    }

    func testBucketFull() {
        let ownID = NodeID(bytes: Data(repeating: 0, count: 20))
        var table = DHTRoutingTable(ownID: ownID)

        // Fill a bucket (all nodes that map to same bucket)
        var inserted = 0
        for i in 0..<20 {
            var bytes = Data(repeating: 0, count: 20)
            bytes[0] = 0x80 // same top bit -> same bucket
            bytes[19] = UInt8(i)
            let node = DHTNodeEntry(id: NodeID(bytes: bytes), address: "1.2.3.\(i)", port: 6881)
            if table.insert(node) { inserted += 1 }
        }
        // Should be capped at k=8
        XCTAssertEqual(inserted, DHTRoutingTable.k)
    }

    func testRemoveStale() {
        let ownID = NodeID.random()
        var table = DHTRoutingTable(ownID: ownID)

        let node = DHTNodeEntry(id: NodeID.random(), address: "1.2.3.4", port: 6881)
        _ = table.insert(node)
        XCTAssertEqual(table.nodeCount, 1)

        // Remove nodes older than 0 seconds (all nodes)
        table.removeStaleNodes(olderThan: 0)
        XCTAssertEqual(table.nodeCount, 0)
    }
}
