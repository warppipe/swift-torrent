import Foundation

/// Represents a bencoded value.
public enum BencodeValue: Equatable, Sendable {
    case integer(Int64)
    case string(Data)
    case list([BencodeValue])
    case dictionary([(key: Data, value: BencodeValue)])

    // MARK: - Convenience accessors

    public var integerValue: Int64? {
        if case .integer(let v) = self { return v }
        return nil
    }

    public var stringValue: Data? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var utf8String: String? {
        if case .string(let v) = self { return String(data: v, encoding: .utf8) }
        return nil
    }

    public var listValue: [BencodeValue]? {
        if case .list(let v) = self { return v }
        return nil
    }

    public var dictionaryValue: [(key: Data, value: BencodeValue)]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }

    /// Subscript dictionary by string key.
    public subscript(_ key: String) -> BencodeValue? {
        guard case .dictionary(let pairs) = self else { return nil }
        let keyData = Data(key.utf8)
        return pairs.first(where: { $0.key == keyData })?.value
    }

    // MARK: - Equatable

    public static func == (lhs: BencodeValue, rhs: BencodeValue) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let a), .integer(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.list(let a), .list(let b)):
            return a == b
        case (.dictionary(let a), .dictionary(let b)):
            guard a.count == b.count else { return false }
            for (pairA, pairB) in zip(a, b) {
                if pairA.key != pairB.key || pairA.value != pairB.value { return false }
            }
            return true
        default:
            return false
        }
    }
}
