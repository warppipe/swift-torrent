import Foundation

// MARK: - Status Alerts

public struct TorrentAddedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.status
    public let infoHash: InfoHash
    public let name: String
}

public struct TorrentRemovedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.status
    public let infoHash: InfoHash
}

public struct TorrentFinishedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.status
    public let infoHash: InfoHash
}

public struct StateChangedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.status
    public let infoHash: InfoHash
    public let previousState: TorrentState
    public let newState: TorrentState
}

// MARK: - Peer Alerts

public struct PeerConnectedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.peer
    public let address: String
    public let port: UInt16
}

public struct PeerDisconnectedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.peer
    public let address: String
    public let port: UInt16
    public let reason: String?
}

// MARK: - Tracker Alerts

public struct TrackerResponseAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.tracker
    public let url: String
    public let numPeers: Int
}

public struct TrackerErrorAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.error
    public let url: String
    public let message: String
}

// MARK: - Storage Alerts

public struct PieceFinishedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.storage
    public let pieceIndex: Int
}

public struct HashFailedAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.storage
    public let pieceIndex: Int
}

// MARK: - Error Alerts

public struct FileErrorAlert: Alert {
    public let timestamp = Date()
    public let category = AlertCategory.error
    public let path: String
    public let error: String
}
