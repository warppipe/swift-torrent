import Foundation

/// Current state of a torrent.
public enum TorrentState: String, Sendable {
    case checkingFiles = "checking_files"
    case downloadingMetadata = "downloading_metadata"
    case downloading
    case seeding
    case paused
    case stopped
    case error
}

/// A snapshot of a torrent's current status.
public struct TorrentStatus: Sendable {
    public let infoHash: InfoHash
    public let name: String
    public let state: TorrentState
    public let progress: Double        // 0.0 to 1.0
    public let downloadRate: Double    // bytes per second
    public let uploadRate: Double
    public let totalDownloaded: Int64
    public let totalUploaded: Int64
    public let totalSize: Int64
    public let numPeers: Int
    public let numSeeds: Int
    public let piecesCompleted: Int
    public let piecesTotal: Int
}
