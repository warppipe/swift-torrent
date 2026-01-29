import Foundation

/// Parameters for adding a torrent to a session.
public struct AddTorrentParams: Sendable {
    public var torrentInfo: TorrentInfo?
    public var magnetLink: MagnetLink?
    public var savePath: String?
    public var resumeData: ResumeData?
    public var paused: Bool

    public init(torrentInfo: TorrentInfo? = nil, magnetLink: MagnetLink? = nil,
                savePath: String? = nil, resumeData: ResumeData? = nil, paused: Bool = false) {
        self.torrentInfo = torrentInfo
        self.magnetLink = magnetLink
        self.savePath = savePath
        self.resumeData = resumeData
        self.paused = paused
    }

    /// Create from a .torrent file path.
    public static func fromFile(_ path: String, savePath: String? = nil) throws -> AddTorrentParams {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let info = try TorrentInfo.parse(from: data)
        return AddTorrentParams(torrentInfo: info, savePath: savePath)
    }

    /// Create from a magnet URI.
    public static func fromMagnet(_ uri: String, savePath: String? = nil) throws -> AddTorrentParams {
        guard let magnet = MagnetLink(uri: uri) else {
            throw AddTorrentError.invalidMagnetLink
        }
        return AddTorrentParams(magnetLink: magnet, savePath: savePath)
    }

    /// The info hash (from either torrent info or magnet link).
    public var infoHash: InfoHash? {
        torrentInfo?.infoHash ?? magnetLink?.infoHash
    }
}

public enum AddTorrentError: Error {
    case invalidMagnetLink
    case noInfoHash
}
