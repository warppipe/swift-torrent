import Foundation

/// Configuration settings for a Session.
public struct SessionSettings: Sendable {
    public var listenPort: UInt16
    public var maxConnections: Int
    public var maxConnectionsPerTorrent: Int
    public var downloadRateLimit: Int  // bytes/sec, 0 = unlimited
    public var uploadRateLimit: Int
    public var dhtEnabled: Bool
    public var dhtPort: Int
    public var userAgent: String
    public var savePath: String

    public init(
        listenPort: UInt16 = 6881,
        maxConnections: Int = 200,
        maxConnectionsPerTorrent: Int = 50,
        downloadRateLimit: Int = 0,
        uploadRateLimit: Int = 0,
        dhtEnabled: Bool = true,
        dhtPort: Int = 6881,
        userAgent: String = "SwiftTorrent/1.0",
        savePath: String = NSTemporaryDirectory()
    ) {
        self.listenPort = listenPort
        self.maxConnections = maxConnections
        self.maxConnectionsPerTorrent = maxConnectionsPerTorrent
        self.downloadRateLimit = downloadRateLimit
        self.uploadRateLimit = uploadRateLimit
        self.dhtEnabled = dhtEnabled
        self.dhtPort = dhtPort
        self.userAgent = userAgent
        self.savePath = savePath
    }
}
