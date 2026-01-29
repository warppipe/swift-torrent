import Foundation

/// HTTP tracker client (BEP-3).
public struct HTTPTracker: Sendable {
    public let announceURL: String

    public init(announceURL: String) {
        self.announceURL = announceURL
    }

    /// Announce to the tracker.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        var components = URLComponents(string: announceURL)
        components?.queryItems = [
            URLQueryItem(name: "info_hash", value: params.infoHash.urlEncoded),
            URLQueryItem(name: "peer_id", value: String(data: params.peerID, encoding: .ascii) ?? ""),
            URLQueryItem(name: "port", value: String(params.port)),
            URLQueryItem(name: "uploaded", value: String(params.uploaded)),
            URLQueryItem(name: "downloaded", value: String(params.downloaded)),
            URLQueryItem(name: "left", value: String(params.left)),
            URLQueryItem(name: "compact", value: "1"),
            URLQueryItem(name: "numwant", value: String(params.numWant)),
        ]
        if let event = params.event {
            components?.queryItems?.append(URLQueryItem(name: "event", value: event))
        }

        guard let url = components?.url else {
            throw TrackerError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseAnnounceResponse(data)
    }

    private func parseAnnounceResponse(_ data: Data) throws -> AnnounceResponse {
        let decoder = BencodeDecoder()
        let value = try decoder.decode(data)

        if let failure = value["failure reason"]?.utf8String {
            throw TrackerError.failure(failure)
        }

        let interval = value["interval"]?.integerValue.map(Int.init) ?? 1800
        let seeders = value["complete"]?.integerValue.map(Int.init) ?? 0
        let leechers = value["incomplete"]?.integerValue.map(Int.init) ?? 0

        var peers: [(String, UInt16)] = []

        if let peersData = value["peers"]?.stringValue {
            // Compact format: 6 bytes per peer (4 IP + 2 port)
            var offset = 0
            while offset + 6 <= peersData.count {
                let ip = "\(peersData[offset]).\(peersData[offset+1]).\(peersData[offset+2]).\(peersData[offset+3])"
                let port = UInt16(peersData[offset+4]) << 8 | UInt16(peersData[offset+5])
                peers.append((ip, port))
                offset += 6
            }
        } else if let peersList = value["peers"]?.listValue {
            // Dictionary format
            for peerValue in peersList {
                if let ip = peerValue["ip"]?.utf8String,
                   let port = peerValue["port"]?.integerValue {
                    peers.append((ip, UInt16(port)))
                }
            }
        }

        return AnnounceResponse(
            interval: interval, seeders: seeders, leechers: leechers, peers: peers
        )
    }
}

public struct AnnounceParams: Sendable {
    public let infoHash: InfoHash
    public let peerID: Data
    public let port: UInt16
    public let uploaded: Int64
    public let downloaded: Int64
    public let left: Int64
    public let numWant: Int
    public let event: String?  // "started", "stopped", "completed"

    public init(infoHash: InfoHash, peerID: Data, port: UInt16,
                uploaded: Int64 = 0, downloaded: Int64 = 0, left: Int64,
                numWant: Int = 50, event: String? = nil) {
        self.infoHash = infoHash
        self.peerID = peerID
        self.port = port
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.left = left
        self.numWant = numWant
        self.event = event
    }
}

public struct AnnounceResponse: Sendable {
    public let interval: Int
    public let seeders: Int
    public let leechers: Int
    public let peers: [(String, UInt16)]
}

public enum TrackerError: Error, Equatable {
    case invalidURL
    case failure(String)
    case invalidResponse
    case connectionFailed
}
