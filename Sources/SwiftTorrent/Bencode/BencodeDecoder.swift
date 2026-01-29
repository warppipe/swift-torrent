import Foundation

public enum BencodeError: Error, Equatable {
    case unexpectedEnd
    case invalidFormat(String)
    case invalidInteger
    case invalidStringLength
    case invalidDictionaryKey
}

public struct BencodeDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> BencodeValue {
        var index = data.startIndex
        let result = try decodeValue(data, index: &index)
        return result
    }

    /// Decode and also return the raw bytes consumed for the value, useful for info_hash computation.
    public func decodeWithRange(_ data: Data) throws -> (value: BencodeValue, range: Range<Data.Index>) {
        var index = data.startIndex
        let start = index
        let result = try decodeValue(data, index: &index)
        return (result, start..<index)
    }

    private func decodeValue(_ data: Data, index: inout Data.Index) throws -> BencodeValue {
        guard index < data.endIndex else { throw BencodeError.unexpectedEnd }

        switch data[index] {
        case UInt8(ascii: "i"):
            return try decodeInteger(data, index: &index)
        case UInt8(ascii: "l"):
            return try decodeList(data, index: &index)
        case UInt8(ascii: "d"):
            return try decodeDictionary(data, index: &index)
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try decodeString(data, index: &index)
        default:
            throw BencodeError.invalidFormat("Unexpected byte: \(data[index])")
        }
    }

    private func decodeInteger(_ data: Data, index: inout Data.Index) throws -> BencodeValue {
        index = data.index(after: index) // skip 'i'
        guard let endIdx = data[index...].firstIndex(of: UInt8(ascii: "e")) else {
            throw BencodeError.unexpectedEnd
        }
        guard let str = String(data: data[index..<endIdx], encoding: .ascii),
              let value = Int64(str) else {
            throw BencodeError.invalidInteger
        }
        index = data.index(after: endIdx) // skip 'e'
        return .integer(value)
    }

    private func decodeString(_ data: Data, index: inout Data.Index) throws -> BencodeValue {
        guard let colonIdx = data[index...].firstIndex(of: UInt8(ascii: ":")) else {
            throw BencodeError.unexpectedEnd
        }
        guard let lenStr = String(data: data[index..<colonIdx], encoding: .ascii),
              let length = Int(lenStr), length >= 0 else {
            throw BencodeError.invalidStringLength
        }
        let start = data.index(after: colonIdx)
        let end = data.index(start, offsetBy: length)
        guard end <= data.endIndex else { throw BencodeError.unexpectedEnd }
        index = end
        return .string(Data(data[start..<end]))
    }

    private func decodeList(_ data: Data, index: inout Data.Index) throws -> BencodeValue {
        index = data.index(after: index) // skip 'l'
        var items: [BencodeValue] = []
        while index < data.endIndex && data[index] != UInt8(ascii: "e") {
            items.append(try decodeValue(data, index: &index))
        }
        guard index < data.endIndex else { throw BencodeError.unexpectedEnd }
        index = data.index(after: index) // skip 'e'
        return .list(items)
    }

    private func decodeDictionary(_ data: Data, index: inout Data.Index) throws -> BencodeValue {
        index = data.index(after: index) // skip 'd'
        var pairs: [(key: Data, value: BencodeValue)] = []
        while index < data.endIndex && data[index] != UInt8(ascii: "e") {
            let keyValue = try decodeString(data, index: &index)
            guard case .string(let keyData) = keyValue else {
                throw BencodeError.invalidDictionaryKey
            }
            let value = try decodeValue(data, index: &index)
            pairs.append((key: keyData, value: value))
        }
        guard index < data.endIndex else { throw BencodeError.unexpectedEnd }
        index = data.index(after: index) // skip 'e'
        return .dictionary(pairs)
    }
}
