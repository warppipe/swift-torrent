import Foundation
import NIOCore
import NIOPosix

/// Errors thrown by TorrentHandle wait methods.
public enum TorrentError: Error {
    case timeout
}

/// Per-torrent controller tying peers, pieces, and disk together.
public actor TorrentHandle {
    public let infoHash: InfoHash
    private var info: TorrentInfo?
    private let magnetLink: MagnetLink?
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
    private var lastDownloadRateSample: Int64 = 0
    private var lastUploadRateSample: Int64 = 0
    private var downloadRate: Double = 0
    private var uploadRate: Double = 0
    private var reannounceTask: Task<Void, Never>?
    private var downloadMonitorTask: Task<Void, Never>?
    private var metadataExchange: MetadataExchange?
    private var metadataContinuations: [UInt64: CheckedContinuation<TorrentInfo, Error>] = [:]
    private var completionContinuations: [UInt64: CheckedContinuation<Void, Error>] = [:]
    private var nextWaitID: UInt64 = 0

    public init(params: AddTorrentParams, settings: SessionSettings, group: EventLoopGroup) {
        let hash = params.infoHash!
        self.infoHash = hash
        self.info = params.torrentInfo
        self.magnetLink = params.magnetLink
        self.savePath = params.savePath ?? settings.savePath
        self.peerID = generatePeerID()
        self.group = group
        self.peerManager = PeerManager(
            infoHash: hash.bytes, peerID: peerID, group: group,
            maxConnections: settings.maxConnectionsPerTorrent
        )

        if let magnet = params.magnetLink, !magnet.trackers.isEmpty {
            let tiers = magnet.trackers.map { [$0] }
            self.trackerManager = TrackerManager(tiers: tiers, group: group)
        }
    }

    private func setupDownloadComponents(info: TorrentInfo) async {
        self.info = info
        let pm = PieceManager(info: info)
        let pp = PiecePicker(pieceCount: info.pieceCount)
        let fs = FileStorage(info: info)
        let dio = DiskIO(basePath: savePath, fileStorage: fs)
        self.pieceManager = pm
        self.piecePicker = pp
        self.diskIO = dio

        if self.trackerManager == nil {
            self.trackerManager = TrackerManager(info: info, group: group)
        }

        await peerManager.configure(
            pieceManager: pm, piecePicker: pp, diskIO: dio,
            pieceCount: info.pieceCount
        )
    }

    /// Complete initialization for .torrent-file init path (must be called after init).
    internal func finishInitialization() async {
        if let info = self.info {
            await setupDownloadComponents(info: info)
        }
    }

    /// Start downloading.
    public func start() async throws {
        guard state == .paused || state == .stopped else { return }

        if info != nil {
            state = .downloading
            // Allocate files on disk
            try? await diskIO?.allocateFiles()
            startDownloadMonitor()
        } else if magnetLink != nil {
            state = .downloadingMetadata
            // Set up metadata exchange
            let metaEx = MetadataExchange(infoHash: infoHash)
            self.metadataExchange = metaEx
            await peerManager.configureMagnet(metadataExchange: metaEx)
            let weakSelf = self
            await peerManager.setOnMetadataReceived { info in
                Task { await weakSelf.onMetadataReceived(info: info) }
            }
        } else {
            state = .downloading
        }

        // Announce to trackers
        if let trackerMgr = trackerManager {
            let left = info?.totalSize ?? 0
            let params = AnnounceParams(
                infoHash: infoHash, peerID: peerID, port: 6881,
                left: left - totalDownloaded, event: "started"
            )
            await announceToAllTrackers(trackerMgr: trackerMgr, params: params)
            startReannounceLoop(trackerMgr: trackerMgr)
        }
    }

    private func onMetadataReceived(info: TorrentInfo) async {
        await setupDownloadComponents(info: info)
        state = .downloading
        try? await diskIO?.allocateFiles()
        startDownloadMonitor()

        // Resume all waiting metadata continuations
        let conts = metadataContinuations
        metadataContinuations.removeAll()
        for (_, cont) in conts {
            cont.resume(returning: info)
        }
    }

    private func startDownloadMonitor() {
        downloadMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { break }
                let complete = await self.checkCompletion()
                if complete {
                    await self.transitionToSeeding()
                    break
                }
                await self.peerManager.checkTimeouts()
            }
        }
    }

    private func checkCompletion() async -> Bool {
        guard let pm = pieceManager else { return false }
        return await pm.isComplete()
    }

    private func transitionToSeeding() {
        state = .seeding
        downloadMonitorTask?.cancel()

        // Resume all waiting completion continuations
        let conts = completionContinuations
        completionContinuations.removeAll()
        for (_, cont) in conts {
            cont.resume()
        }
    }

    /// Announce to all tracker tiers concurrently.
    private func announceToAllTrackers(trackerMgr: TrackerManager, params: AnnounceParams) async {
        if let response = try? await trackerMgr.announce(params: params) {
            for (address, port) in response.peers {
                await peerManager.addPeer(address: address, port: port)
            }
        }
    }

    /// Periodically re-announce to trackers.
    private func startReannounceLoop(trackerMgr: TrackerManager) {
        reannounceTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await trackerMgr.getInterval()
                try? await Task.sleep(for: .seconds(max(interval, 60)))
                guard let self, !Task.isCancelled else { break }

                let left = await self.getRemainingBytes()
                let infoHash = await self.infoHash
                let peerID = await self.peerID
                let uploaded = await self.totalUploaded
                let downloaded = await self.totalDownloaded
                let params = AnnounceParams(
                    infoHash: infoHash, peerID: peerID, port: 6881,
                    uploaded: uploaded, downloaded: downloaded,
                    left: left
                )
                if let response = try? await trackerMgr.announce(params: params) {
                    for (address, port) in response.peers {
                        await self.peerManager.addPeer(address: address, port: port)
                    }
                }
            }
        }
    }

    private func getRemainingBytes() -> Int64 {
        (info?.totalSize ?? 0) - totalDownloaded
    }

    /// Pause the torrent.
    public func pause() {
        state = .paused
        reannounceTask?.cancel()
        downloadMonitorTask?.cancel()
    }

    /// Resume the torrent.
    public func resume() async throws {
        try await start()
    }

    /// Get current status snapshot.
    public func status() async -> TorrentStatus {
        let progress = await pieceManager?.progress() ?? 0
        let completed = await pieceManager?.getCompleted()
        let name: String
        if let info = info {
            name = info.name
        } else if let dn = magnetLink?.displayName {
            name = dn
        } else {
            name = "Unknown"
        }
        return TorrentStatus(
            infoHash: infoHash,
            name: name,
            state: state,
            progress: progress,
            downloadRate: downloadRate,
            uploadRate: uploadRate,
            totalDownloaded: totalDownloaded,
            totalUploaded: totalUploaded,
            totalSize: info?.totalSize ?? 0,
            numPeers: await peerManager.connectionCount,
            numSeeds: 0,
            piecesCompleted: completed?.popcount ?? 0,
            piecesTotal: info?.pieceCount ?? 0
        )
    }

    /// Returns the file entries for this torrent, or nil if metadata is not yet available.
    public func getFiles() -> [TorrentInfo.FileEntry]? {
        info?.files
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

    /// Wait until metadata is available, or return immediately if already present.
    public func waitForMetadata(timeout seconds: Int) async throws -> TorrentInfo {
        if let info = self.info {
            return info
        }

        let id = nextWaitID
        nextWaitID += 1

        return try await withCheckedThrowingContinuation { continuation in
            metadataContinuations[id] = continuation

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                if let cont = await self.removeMetadataContinuation(id: id) {
                    cont.resume(throwing: TorrentError.timeout)
                }
            }
        }
    }

    private func removeMetadataContinuation(id: UInt64) -> CheckedContinuation<TorrentInfo, Error>? {
        metadataContinuations.removeValue(forKey: id)
    }

    /// Wait until all pieces are downloaded, or return immediately if already complete.
    public func waitForCompletion(timeout seconds: Int) async throws {
        if state == .seeding {
            return
        }

        let id = nextWaitID
        nextWaitID += 1

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            completionContinuations[id] = continuation

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                if let cont = await self.removeCompletionContinuation(id: id) {
                    cont.resume(throwing: TorrentError.timeout)
                }
            }
        }
    }

    private func removeCompletionContinuation(id: UInt64) -> CheckedContinuation<Void, Error>? {
        completionContinuations.removeValue(forKey: id)
    }
}
