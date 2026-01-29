import Foundation

/// Base protocol for all alert types.
public protocol Alert: Sendable {
    var timestamp: Date { get }
    var category: AlertCategory { get }
}

public enum AlertCategory: Sendable {
    case status
    case error
    case peer
    case tracker
    case storage
    case dht
}
