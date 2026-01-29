# SwiftTorrent

![screenshot](https://github.com/warppipe/SwiftTorrent/raw/gh-pages/img/SwiftTorrent.png)](https://github.com/warppipe/SwiftTorrent)

A pure Swift BitTorrent library targeting macOS 14+ and iOS 17+. Implements BEP-3 (peer wire protocol), BEP-5 (DHT), and BEP-15 (UDP trackers) with no C/C++ dependencies.

## Features

- Bencode encoding/decoding
- .torrent file parsing and creation
- Magnet link support
- Peer wire protocol (choke, unchoke, interested, have, bitfield, request, piece, cancel)
- HTTP and UDP tracker clients
- Kademlia DHT with k-bucket routing table
- Rarest-first piece selection
- Async disk I/O with piece caching
- Resume data for saving/restoring state
- Event notifications via `AsyncStream<Alert>`

## Requirements

- Swift 5.9+
- macOS 14+ / iOS 17+

## Dependencies

- [swift-nio](https://github.com/apple/swift-nio) — async TCP/UDP networking
- [swift-nio-extras](https://github.com/apple/swift-nio-extras) — byte buffer utilities
- [swift-crypto](https://github.com/apple/swift-crypto) — SHA-1, SHA-256

## Build

```bash
swift build
swift test
```

## Usage

### Add a torrent from a .torrent file

```swift
import SwiftTorrent

let session = Session(settings: SessionSettings(
    listenPort: 6881,
    savePath: "/Users/me/Downloads"
))

let params = try AddTorrentParams.fromFile("/path/to/file.torrent",
                                           savePath: "/Users/me/Downloads")
let handle = try await session.addTorrent(params)
try await handle.start()

// Monitor progress
let status = await handle.status()
print("Progress: \(Int(status.progress * 100))%")
print("Peers: \(status.numPeers)")
```

### Add a torrent from a magnet link

```swift
let params = try AddTorrentParams.fromMagnet(
    "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Example",
    savePath: "/Users/me/Downloads"
)
let handle = try await session.addTorrent(params)
```

### Listen for alerts

```swift
Task {
    for await alert in session.alerts {
        switch alert {
        case let a as TorrentFinishedAlert:
            print("Finished: \(a.infoHash)")
        case let a as PieceFinishedAlert:
            print("Piece \(a.pieceIndex) complete")
        case let a as TrackerResponseAlert:
            print("Tracker \(a.url): \(a.numPeers) peers")
        default:
            break
        }
    }
}
```

### Parse a .torrent file

```swift
let data = try Data(contentsOf: URL(fileURLWithPath: "example.torrent"))
let info = try TorrentInfo.parse(from: data)

print("Name: \(info.name)")
print("Size: \(info.totalSize) bytes")
print("Pieces: \(info.pieceCount)")
print("Info hash: \(info.infoHash)")

for file in info.files {
    print("  \(file.path) (\(file.length) bytes)")
}
```

### Parse a magnet link

```swift
if let magnet = MagnetLink(uri: "magnet:?xt=urn:btih:...&dn=MyFile&tr=http://tracker.example.com/announce") {
    print("Hash: \(magnet.infoHash)")
    print("Name: \(magnet.displayName ?? "unknown")")
    print("Trackers: \(magnet.trackers)")
}
```

### Bencode encoding/decoding

```swift
let decoder = BencodeDecoder()
let value = try decoder.decode(rawData)
print(value["info"]?["name"]?.utf8String ?? "")

let encoder = BencodeEncoder()
let encoded = encoder.encode(.dictionary([
    (key: Data("key".utf8), value: .string(Data("value".utf8)))
]))
```

### Save and restore resume data

```swift
// Save
if let resumeData = await handle.generateResumeData() {
    let encoded = resumeData.encode()
    try encoded.write(to: URL(fileURLWithPath: "resume.dat"))
}

// Restore
let saved = try Data(contentsOf: URL(fileURLWithPath: "resume.dat"))
let resumeData = try ResumeData.decode(from: saved)
let params = AddTorrentParams(resumeData: resumeData)
```

## Architecture

```
Session (actor)
├── TorrentHandle (actor, per-torrent)
│   ├── PeerManager (actor) → PeerConnection (SwiftNIO)
│   ├── PieceManager (actor) → Bitfield, PiecePicker
│   ├── TrackerManager (actor) → HTTPTracker, UDPTracker
│   └── DiskIO (actor) → FileStorage, PieceCache
├── DHTNode (actor) → DHTRoutingTable, DHTTraversal, DHTStorage
└── Alerts → AsyncStream<Alert>
```

## License

MIT
