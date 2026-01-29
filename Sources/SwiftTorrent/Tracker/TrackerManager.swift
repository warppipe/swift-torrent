import Foundation
import NIOCore

/// Coordinates multiple trackers with tier support.
public actor TrackerManager {
    private let tiers: [[String]]
    private let group: EventLoopGroup
    private var lastResponse: AnnounceResponse?
    private var announceInterval: Int = 1800

    public init(tiers: [[String]], group: EventLoopGroup) {
        self.tiers = tiers
        self.group = group
    }

    /// Convenience: create from TorrentInfo.
    public init(info: TorrentInfo, group: EventLoopGroup) {
        var tiers = info.announceList
        if tiers.isEmpty, let url = info.announceURL {
            tiers = [[url]]
        }
        self.tiers = tiers
        self.group = group
    }

    /// Announce to all tracker tiers, returning the first successful response.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        for tier in tiers {
            for urlString in tier {
                do {
                    let response: AnnounceResponse
                    if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                        let tracker = HTTPTracker(announceURL: urlString)
                        response = try await tracker.announce(params: params)
                    } else if urlString.hasPrefix("udp://") {
                        guard let components = URLComponents(string: urlString),
                              let host = components.host,
                              let port = components.port else {
                            continue
                        }
                        let tracker = UDPTracker(host: host, port: port, group: group)
                        response = try await tracker.announce(params: params)
                    } else {
                        continue
                    }
                    lastResponse = response
                    announceInterval = response.interval
                    return response
                } catch {
                    continue // Try next tracker in tier
                }
            }
        }
        throw TrackerError.connectionFailed
    }

    public func getInterval() -> Int {
        announceInterval
    }
}
