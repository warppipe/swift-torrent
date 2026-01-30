import Foundation
import Crypto

/// Tracks piece completion and verifies SHA-1 hashes.
public actor PieceManager {
    private let pieceCount: Int
    private let pieceLength: Int
    private let totalSize: Int64
    private let pieceHashes: Data  // concatenated 20-byte SHA-1 hashes
    private var completed: Bitfield
    private var inProgress: Set<Int>
    private var pieceBuffers: [Int: Data]

    public init(info: TorrentInfo) {
        self.pieceCount = info.pieceCount
        self.pieceLength = info.pieceLength
        self.totalSize = info.totalSize
        self.pieceHashes = info.pieces
        self.completed = Bitfield(count: info.pieceCount)
        self.inProgress = []
        self.pieceBuffers = [:]
    }

    /// Mark a piece as being downloaded.
    public func startPiece(_ index: Int) {
        inProgress.insert(index)
        pieceBuffers[index] = Data()
    }

    /// Add a block to a piece being downloaded.
    public func addBlock(pieceIndex: Int, offset: Int, data: Data) {
        guard var buffer = pieceBuffers[pieceIndex] else { return }
        // Ensure buffer is large enough
        let needed = offset + data.count
        if buffer.count < needed {
            buffer.append(Data(count: needed - buffer.count))
        }
        buffer.replaceSubrange(offset..<offset + data.count, with: data)
        pieceBuffers[pieceIndex] = buffer
    }

    /// Verify and complete a piece.
    public func completePiece(_ index: Int) -> Bool {
        guard let buffer = pieceBuffers[index] else { return false }

        // Verify hash
        let expectedHash = pieceHashes.subdata(in: index * 20..<(index + 1) * 20)
        let actualHash = Data(Insecure.SHA1.hash(data: buffer))

        guard actualHash == expectedHash else {
            // Hash mismatch — piece is corrupt
            pieceBuffers.removeValue(forKey: index)
            inProgress.remove(index)
            return false
        }

        completed.set(index)
        inProgress.remove(index)
        pieceBuffers.removeValue(forKey: index)
        return true
    }

    /// Get the completed bitfield.
    public func getCompleted() -> Bitfield {
        completed
    }

    /// Check if a piece is complete.
    public func hasPiece(_ index: Int) -> Bool {
        completed.get(index)
    }

    /// Check if all pieces are complete.
    public func isComplete() -> Bool {
        completed.allSet
    }

    /// Get progress as a fraction.
    public func progress() -> Double {
        guard pieceCount > 0 else { return 1.0 }
        return Double(completed.popcount) / Double(pieceCount)
    }

    /// Expected size of a specific piece.
    public func expectedPieceSize(_ index: Int) -> Int {
        let start = Int64(index) * Int64(pieceLength)
        return Int(min(Int64(pieceLength), totalSize - start))
    }

    /// Get the assembled piece data buffer (before completion/verification).
    public func getPieceBuffer(_ index: Int) -> Data? {
        pieceBuffers[index]
    }

    /// Number of 16KB blocks in a piece.
    public func blockCount(for pieceIndex: Int) -> Int {
        let size = expectedPieceSize(pieceIndex)
        return (size + 16383) / 16384
    }

    /// Whether a piece is currently being downloaded.
    public func isInProgress(_ index: Int) -> Bool {
        inProgress.contains(index)
    }

    /// The standard piece length for this torrent.
    public func getPieceLength() -> Int {
        pieceLength
    }

    /// Total number of pieces.
    public func getPieceCount() -> Int {
        pieceCount
    }
}
