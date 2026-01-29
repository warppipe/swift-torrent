import XCTest
@testable import SwiftTorrent

final class PiecePickerTests: XCTestCase {
    func testRarestFirst() {
        var picker = PiecePicker(pieceCount: 5)

        // Peer 1 has pieces 0, 1, 2
        var bf1 = Bitfield(count: 5)
        bf1.set(0); bf1.set(1); bf1.set(2)
        picker.addPeerBitfield(bf1)

        // Peer 2 has pieces 0, 1, 3
        var bf2 = Bitfield(count: 5)
        bf2.set(0); bf2.set(1); bf2.set(3)
        picker.addPeerBitfield(bf2)

        // Availability: 0->2, 1->2, 2->1, 3->1, 4->0
        // Peer with pieces 2 and 3 — should pick 2 or 3 (rarest)
        var peerBF = Bitfield(count: 5)
        peerBF.set(2); peerBF.set(3)

        let have = Bitfield(count: 5) // we have nothing
        let picked = picker.pick(have: have, peerHas: peerBF)
        XCTAssertNotNil(picked)
        XCTAssertTrue(picked == 2 || picked == 3) // both have availability 1
    }

    func testAlreadyHave() {
        var picker = PiecePicker(pieceCount: 3)
        var bf = Bitfield(count: 3)
        bf.set(0); bf.set(1); bf.set(2)
        picker.addPeerBitfield(bf)

        // We already have everything
        var have = Bitfield(count: 3)
        have.set(0); have.set(1); have.set(2)

        let picked = picker.pick(have: have, peerHas: bf)
        XCTAssertNil(picked)
    }

    func testPickMultiple() {
        var picker = PiecePicker(pieceCount: 5)
        var bf = Bitfield(count: 5)
        for i in 0..<5 { bf.set(i) }
        picker.addPeerBitfield(bf)

        let have = Bitfield(count: 5)
        let picked = picker.pickMultiple(have: have, peerHas: bf, count: 3)
        XCTAssertEqual(picked.count, 3)
    }

    func testAddHave() {
        var picker = PiecePicker(pieceCount: 3)
        picker.addHave(1)
        picker.addHave(1)
        // Piece 1 should have availability 2, others 0
        // When picking from a peer that has all, piece 0 or 2 should be picked (avail 0)
        var peerBF = Bitfield(count: 3)
        peerBF.set(0); peerBF.set(1); peerBF.set(2)
        let have = Bitfield(count: 3)
        let picked = picker.pick(have: have, peerHas: peerBF)
        XCTAssertTrue(picked == 0 || picked == 2)
    }
}
