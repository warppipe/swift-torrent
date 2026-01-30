import XCTest
import Foundation
import Crypto
import NIOPosix
@testable import SwiftTorrent

final class PeerStateTests: XCTestCase {
    func testInitialState() async {
        let state = PeerState(pieceCount: 10)
        let choking = await state.peerChoking
        let interested = await state.peerInterested
        let amChoking = await state.amChoking
        let amInterested = await state.amInterested
        XCTAssertTrue(choking)
        XCTAssertFalse(interested)
        XCTAssertTrue(amChoking)
        XCTAssertFalse(amInterested)
    }

    func testChokeUnchokeTransitions() async {
        let state = PeerState(pieceCount: 10)
        await state.setPeerChoking(false)
        var val = await state.getPeerChoking()
        XCTAssertFalse(val)
        await state.setPeerChoking(true)
        val = await state.getPeerChoking()
        XCTAssertTrue(val)
    }

    func testInterestedTransitions() async {
        let state = PeerState(pieceCount: 10)
        await state.setAmInterested(true)
        var val = await state.getAmInterested()
        XCTAssertTrue(val)
        await state.setAmInterested(false)
        val = await state.getAmInterested()
        XCTAssertFalse(val)
    }

    func testPendingRequests() async {
        let state = PeerState(pieceCount: 10, maxPipelineDepth: 3)
        var canReq = await state.canRequest
        XCTAssertTrue(canReq)
        var count = await state.pendingCount
        XCTAssertEqual(count, 0)

        let r1 = PeerState.BlockRequest(pieceIndex: 0, offset: 0, length: 16384)
        let r2 = PeerState.BlockRequest(pieceIndex: 0, offset: 16384, length: 16384)
        let r3 = PeerState.BlockRequest(pieceIndex: 0, offset: 32768, length: 16384)

        await state.addPendingRequest(r1)
        await state.addPendingRequest(r2)
        canReq = await state.canRequest
        XCTAssertTrue(canReq)
        count = await state.pendingCount
        XCTAssertEqual(count, 2)

        await state.addPendingRequest(r3)
        canReq = await state.canRequest
        XCTAssertFalse(canReq)

        await state.removePendingRequest(r1)
        canReq = await state.canRequest
        XCTAssertTrue(canReq)
    }

    func testBitfield() async {
        let state = PeerState(pieceCount: 10)
        var bf = Bitfield(count: 10)
        bf.set(3)
        bf.set(7)
        await state.setPeerBitfield(bf)

        let peerBF = await state.getPeerBitfield()
        XCTAssertTrue(peerBF.get(3))
        XCTAssertTrue(peerBF.get(7))
        XCTAssertFalse(peerBF.get(0))
    }

    func testSetHave() async {
        let state = PeerState(pieceCount: 10)
        await state.setHave(5)
        let bf = await state.getPeerBitfield()
        XCTAssertTrue(bf.get(5))
        XCTAssertFalse(bf.get(4))
    }

    func testClearPendingRequests() async {
        let state = PeerState(pieceCount: 10)
        let r1 = PeerState.BlockRequest(pieceIndex: 0, offset: 0, length: 16384)
        await state.addPendingRequest(r1)
        var count = await state.pendingCount
        XCTAssertEqual(count, 1)
        await state.clearPendingRequests()
        count = await state.pendingCount
        XCTAssertEqual(count, 0)
    }
}

final class BlockSplittingTests: XCTestCase {
    func testStandardPieceBlockCount() async {
        let info = makeTorrentInfo(pieceLength: 262144, totalSize: 1048576)
        let pm = PieceManager(info: info)
        let count = await pm.blockCount(for: 0)
        XCTAssertEqual(count, 16)
    }

    func testLastPieceBlockCount() async {
        let info = makeTorrentInfo(pieceLength: 262144, totalSize: 300000)
        let pm = PieceManager(info: info)
        let lastIdx = await pm.getPieceCount() - 1
        let count = await pm.blockCount(for: lastIdx)
        XCTAssertEqual(count, 3)
    }

    func testSmallPiece() async {
        let info = makeTorrentInfo(pieceLength: 8192, totalSize: 8192)
        let pm = PieceManager(info: info)
        let count = await pm.blockCount(for: 0)
        XCTAssertEqual(count, 1)
    }
}

final class PieceManagerBlockTests: XCTestCase {
    func testBlockReceiptAndCompletion() async {
        let data = Data(repeating: 0xAB, count: 32768)
        let hash = Data(Insecure.SHA1.hash(data: data))
        let info = makeTorrentInfo(pieceLength: 32768, totalSize: 32768, pieceHashes: hash)
        let pm = PieceManager(info: info)

        await pm.startPiece(0)
        let inProg1 = await pm.isInProgress(0)
        XCTAssertTrue(inProg1)

        await pm.addBlock(pieceIndex: 0, offset: 0, data: Data(repeating: 0xAB, count: 16384))
        await pm.addBlock(pieceIndex: 0, offset: 16384, data: Data(repeating: 0xAB, count: 16384))

        let buffer = await pm.getPieceBuffer(0)
        XCTAssertEqual(buffer?.count, 32768)

        let verified = await pm.completePiece(0)
        XCTAssertTrue(verified)
        let has = await pm.hasPiece(0)
        XCTAssertTrue(has)
        let inProg2 = await pm.isInProgress(0)
        XCTAssertFalse(inProg2)
    }

    func testHashMismatchRejection() async {
        let badHash = Data(repeating: 0x00, count: 20)
        let info = makeTorrentInfo(pieceLength: 16384, totalSize: 16384, pieceHashes: badHash)
        let pm = PieceManager(info: info)

        await pm.startPiece(0)
        await pm.addBlock(pieceIndex: 0, offset: 0, data: Data(repeating: 0xFF, count: 16384))

        let verified = await pm.completePiece(0)
        XCTAssertFalse(verified)
        let has = await pm.hasPiece(0)
        XCTAssertFalse(has)
        let inProg = await pm.isInProgress(0)
        XCTAssertFalse(inProg)
    }
}

final class PiecePickerIntegrationTests: XCTestCase {
    func testRarestFirstPicking() {
        var picker = PiecePicker(pieceCount: 5)
        var have = Bitfield(count: 5)

        var peerA = Bitfield(count: 5)
        peerA.set(0); peerA.set(1); peerA.set(2)
        picker.addPeerBitfield(peerA)

        var peerB = Bitfield(count: 5)
        peerB.set(0); peerB.set(1)
        picker.addPeerBitfield(peerB)

        var peerC = Bitfield(count: 5)
        peerC.set(0)
        picker.addPeerBitfield(peerC)

        let picked = picker.pick(have: have, peerHas: peerA)
        XCTAssertEqual(picked, 2)

        have.set(2)
        let picked2 = picker.pick(have: have, peerHas: peerA)
        XCTAssertEqual(picked2, 1)
    }

    func testPickMultiple() {
        var picker = PiecePicker(pieceCount: 4)
        var peerBF = Bitfield(count: 4)
        peerBF.set(0); peerBF.set(1); peerBF.set(2); peerBF.set(3)
        picker.addPeerBitfield(peerBF)

        let have = Bitfield(count: 4)
        let picks = picker.pickMultiple(have: have, peerHas: peerBF, count: 3)
        XCTAssertEqual(picks.count, 3)
    }
}

final class MetadataExchangeTests: XCTestCase {
    func testExtendedHandshake() async {
        let hash = InfoHash(bytes: Data(repeating: 0xAA, count: 20))
        let metaEx = MetadataExchange(infoHash: hash)
        let payload = await metaEx.buildExtendedHandshake()

        let decoder = BencodeDecoder()
        let value = try! decoder.decode(payload)
        let utMeta = value["m"]?["ut_metadata"]?.integerValue
        XCTAssertEqual(utMeta, 1)
    }

    func testMetadataAssemblyAndVerification() async {
        let encoder = BencodeEncoder()
        let infoDict = BencodeValue.dictionary([
            (key: Data("length".utf8), value: .integer(1024)),
            (key: Data("name".utf8), value: .string(Data("test.txt".utf8))),
            (key: Data("piece length".utf8), value: .integer(512)),
            (key: Data("pieces".utf8), value: .string(Data(repeating: 0, count: 40)))
        ])
        let infoData = encoder.encode(infoDict)
        let infoHash = InfoHash.v1(from: infoData)

        let metaEx = MetadataExchange(infoHash: infoHash)

        let peerHandshake = encoder.encode(BencodeValue.dictionary([
            (key: Data("m".utf8), value: BencodeValue.dictionary([
                (key: Data("ut_metadata".utf8), value: .integer(2))
            ])),
            (key: Data("metadata_size".utf8), value: .integer(Int64(infoData.count)))
        ]))

        let result1 = await metaEx.handleExtendedMessage(id: 0, payload: peerHandshake)
        if case .requestMore(let messages) = result1 {
            XCTAssertEqual(messages.count, 1)
        } else {
            XCTFail("Expected requestMore")
        }

        let pieceResponse = encoder.encode(BencodeValue.dictionary([
            (key: Data("msg_type".utf8), value: .integer(1)),
            (key: Data("piece".utf8), value: .integer(0)),
            (key: Data("total_size".utf8), value: .integer(Int64(infoData.count)))
        ]))
        var fullPayload = pieceResponse
        fullPayload.append(infoData)

        let result2 = await metaEx.handleExtendedMessage(id: 1, payload: fullPayload)
        if case .metadataComplete(let torrentInfo) = result2 {
            XCTAssertEqual(torrentInfo.name, "test.txt")
            XCTAssertEqual(torrentInfo.totalSize, 1024)
        } else {
            XCTFail("Expected metadataComplete, got \(result2)")
        }
    }
}

final class DiskIOMultiFileTests: XCTestCase {
    func testMultiFileWriteRead() async throws {
        let tmpDir = NSTemporaryDirectory() + "swifttorrent_test_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let files: [TorrentInfo.FileEntry] = [
            .init(path: "test/a.bin", length: 100, offset: 0),
            .init(path: "test/b.bin", length: 100, offset: 100)
        ]
        let fs = FileStorage(files: files, pieceLength: 64, totalSize: 200)
        let dio = DiskIO(basePath: tmpDir, fileStorage: fs)

        try await dio.allocateFiles()

        let piece0 = Data(repeating: 0xAA, count: 64)
        try await dio.writePiece(index: 0, data: piece0)

        let piece1 = Data(repeating: 0xBB, count: 64)
        try await dio.writePiece(index: 1, data: piece1)

        let read0 = try await dio.readPiece(index: 0)
        XCTAssertEqual(read0, piece0)

        let read1 = try await dio.readPiece(index: 1)
        XCTAssertEqual(read1, piece1)

        let piece3 = Data(repeating: 0xDD, count: 8)
        try await dio.writePiece(index: 3, data: piece3)
        let read3 = try await dio.readPiece(index: 3)
        XCTAssertEqual(read3, piece3)
    }
}

final class ExtendedMessageTests: XCTestCase {
    func testEncodeDecodeExtended() throws {
        let payload = Data("test payload".utf8)
        let msg = PeerMessage.extended(id: 1, payload: payload)
        let encoded = msg.encode()
        let decoded = try PeerMessage.decode(from: Data(encoded.dropFirst(4)))
        XCTAssertEqual(decoded, msg)
    }

    func testExtendedKeepAliveStillWorks() throws {
        let msg = PeerMessage.keepAlive
        let encoded = msg.encode()
        XCTAssertEqual(encoded.count, 4)
    }
}

final class HandshakeExtensionBitTests: XCTestCase {
    func testDefaultReservedHasExtensionBit() {
        let hs = Handshake(infoHash: Data(repeating: 0, count: 20), peerID: Data(repeating: 0, count: 20))
        XCTAssertEqual(hs.reserved[5] & 0x10, 0x10)
    }

    func testCustomReservedPreserved() {
        let custom = Data(count: 8)
        let hs = Handshake(infoHash: Data(repeating: 0, count: 20), peerID: Data(repeating: 0, count: 20), reserved: custom)
        XCTAssertEqual(hs.reserved[5] & 0x10, 0)
    }
}

final class TorrentHandleGetFilesTests: XCTestCase {
    func testGetFilesReturnsNilWithoutInfo() async throws {
        let settings = SessionSettings(listenPort: 0, savePath: NSTemporaryDirectory())
        let params = try AddTorrentParams.fromMagnet(
            "magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&dn=Test",
            savePath: NSTemporaryDirectory()
        )
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let handle = TorrentHandle(params: params, settings: settings, group: group)
        let files = await handle.getFiles()
        XCTAssertNil(files)
    }

    func testGetFilesReturnsFilesWithInfo() async throws {
        let info = makeTorrentInfo(pieceLength: 16384, totalSize: 32768)
        let params = AddTorrentParams(torrentInfo: info, savePath: NSTemporaryDirectory())
        let settings = SessionSettings(listenPort: 0, savePath: NSTemporaryDirectory())
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let handle = TorrentHandle(params: params, settings: settings, group: group)
        let files = await handle.getFiles()
        XCTAssertNotNil(files)
        XCTAssertEqual(files?.count, 1)
        XCTAssertEqual(files?.first?.path, "test")
    }
}

// MARK: - Helpers

func makeTorrentInfo(pieceLength: Int, totalSize: Int64, pieceHashes: Data? = nil) -> TorrentInfo {
    let pieceCount = Int((totalSize + Int64(pieceLength) - 1) / Int64(pieceLength))
    let hashes = pieceHashes ?? Data(repeating: 0, count: pieceCount * 20)
    return TorrentInfo(
        infoHash: InfoHash(bytes: Data(repeating: 0, count: 20)),
        name: "test",
        pieceLength: pieceLength,
        pieces: hashes,
        totalSize: totalSize,
        files: [TorrentInfo.FileEntry(path: "test", length: totalSize, offset: 0)],
        isPrivate: false,
        comment: nil,
        createdBy: nil,
        creationDate: nil,
        announceURL: nil,
        announceList: []
    )
}
