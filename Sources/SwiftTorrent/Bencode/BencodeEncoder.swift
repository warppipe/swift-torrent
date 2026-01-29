import Foundation

public struct BencodeEncoder: Sendable {
    public init() {}

    public func encode(_ value: BencodeValue) -> Data {
        var data = Data()
        encodeValue(value, into: &data)
        return data
    }

    private func encodeValue(_ value: BencodeValue, into data: inout Data) {
        switch value {
        case .integer(let v):
            data.append(UInt8(ascii: "i"))
            data.append(contentsOf: String(v).utf8)
            data.append(UInt8(ascii: "e"))

        case .string(let v):
            data.append(contentsOf: String(v.count).utf8)
            data.append(UInt8(ascii: ":"))
            data.append(v)

        case .list(let items):
            data.append(UInt8(ascii: "l"))
            for item in items {
                encodeValue(item, into: &data)
            }
            data.append(UInt8(ascii: "e"))

        case .dictionary(let pairs):
            data.append(UInt8(ascii: "d"))
            // Keys must be sorted lexicographically
            let sorted = pairs.sorted { $0.key.lexicographicallyPrecedes($1.key) }
            for pair in sorted {
                data.append(contentsOf: String(pair.key.count).utf8)
                data.append(UInt8(ascii: ":"))
                data.append(pair.key)
                encodeValue(pair.value, into: &data)
            }
            data.append(UInt8(ascii: "e"))
        }
    }
}
