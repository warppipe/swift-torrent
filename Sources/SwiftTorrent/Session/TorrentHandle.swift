import Foundation
import NIOCore
import NIOPosix

/// Per-torrent controller tying peers, pieces, and disk together.
public actor TorrentHandle {
    public let infoHash: InfoHash
    private let info: TorrentInfo?
    private let savePath: String
    private let peerID: Data
    private let group: EventLoopGroup

    private var peerManager: PeerManager
    private var pieceManager: PieceManager?
    private var piecePicker: PiecePicker?
    private var diskIO: DiskIO?
    private var trackerManager: TrackerManager?
    private var state: TorrentState = .paused
    private var totalDownloaded: Int64 = 0
    private var totalUploaded: Int64 = 0

    public init(params: AddTorrentParams, settings: SessionSettings, group: EventLoopGroup) {
        let hash = params.infoHash!
        self.infoHash = hash
        self.info = params.torrentInfo
        self.savePath = params.savePath ?? settings.savePath
        self.peerID = generatePeerID()
        self.group = group
        self.peerManager = PeerManager(
            infoHash: hash.bytes, peerID: peerID, group: group,
            maxConnections: settings.maxConnectionsPerTorrent
        )

        if let info = params.torrentInfo {
            self.pieceManager = PieceManager(info: info)
            self.piecePicker = PiecePicker(pieceCount: info.pieceCount)
            self.diskIO = DiskIO(
                basePath: savePath,
                fileStorage: FileStorage(info: info)
            )
            self.trackerManager = TrackerManager(info: info, group: group)
        }
    }

    /// Start downloading.
    public func start() async throws {
        guard state == .paused || state == .stopped else { return }
        state = .downloading

        // Announce to trackers
        if let info = info, let trackerMgr = trackerManager {
            let params = AnnounceParams(
                infoHash: infoHash, peerID: peerID, port: 6881,
                left: info.totalSize - totalDownloaded, event: "started"
            )
            if let response = try? await trackerMgr.announce(params: params) {
                for (address, port) in response.peers {
                    await peerManager.addPeer(address: address, port: port)
                }
            }
        }
    }

    /// Pause the torrent.
    public func pause() {
        state = .paused
    }

    /// Resume the torrent.
    public func resume() async throws {
        try await start()
    }

    /// Get current status snapshot.
    public func status() async -> TorrentStatus {
        let progress = await pieceManager?.progress() ?? 0
        let completed = await pieceManager?.getCompleted()
        return TorrentStatus(
            infoHash: infoHash,
            name: info?.name ?? "Unknown",
            state: state,
            progress: progress,
            downloadRate: 0,
            uploadRate: 0,
            totalDownloaded: totalDownloaded,
            totalUploaded: totalUploaded,
            totalSize: info?.totalSize ?? 0,
            numPeers: await peerManager.connectionCount,
            numSeeds: 0,
            piecesCompleted: completed?.popcount ?? 0,
            piecesTotal: info?.pieceCount ?? 0
        )
    }

    /// Generate resume data for saving state.
    public func generateResumeData() async -> ResumeData? {
        guard let completed = await pieceManager?.getCompleted() else { return nil }
        return ResumeData(
            infoHash: infoHash, completedPieces: completed,
            uploaded: totalUploaded, downloaded: totalDownloaded,
            savePath: savePath
        )
    }
}
