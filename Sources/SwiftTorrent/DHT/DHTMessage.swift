import Foundation

/// KRPC protocol messages for DHT (BEP-5).
public enum DHTMessage: Sendable {
    case query(transactionID: Data, queryType: QueryType, arguments: [(key: Data, value: BencodeValue)])
    case response(transactionID: Data, values: [(key: Data, value: BencodeValue)])
    case error(transactionID: Data, code: Int, message: String)

    public enum QueryType: String, Sendable {
        case ping
        case findNode = "find_node"
        case getPeers = "get_peers"
        case announcePeer = "announce_peer"
    }

    /// Encode to bencoded data.
    public func encode() -> Data {
        let encoder = BencodeEncoder()
        let value: BencodeValue

        switch self {
        case .query(let txID, let queryType, let args):
            value = .dictionary([
                (key: Data("a".utf8), value: .dictionary(args)),
                (key: Data("q".utf8), value: .string(Data(queryType.rawValue.utf8))),
                (key: Data("t".utf8), value: .string(txID)),
                (key: Data("y".utf8), value: .string(Data("q".utf8))),
            ])

        case .response(let txID, let values):
            value = .dictionary([
                (key: Data("r".utf8), value: .dictionary(values)),
                (key: Data("t".utf8), value: .string(txID)),
                (key: Data("y".utf8), value: .string(Data("r".utf8))),
            ])

        case .error(let txID, let code, let msg):
            value = .dictionary([
                (key: Data("e".utf8), value: .list([.integer(Int64(code)), .string(Data(msg.utf8))])),
                (key: Data("t".utf8), value: .string(txID)),
                (key: Data("y".utf8), value: .string(Data("e".utf8))),
            ])
        }

        return encoder.encode(value)
    }

    /// Decode from bencoded data.
    public static func decode(from data: Data) throws -> DHTMessage {
        let decoder = BencodeDecoder()
        let value = try decoder.decode(data)

        guard let typeStr = value["y"]?.utf8String,
              let txID = value["t"]?.stringValue else {
            throw DHTMessageError.invalidMessage
        }

        switch typeStr {
        case "q":
            guard let queryStr = value["q"]?.utf8String,
                  let queryType = QueryType(rawValue: queryStr),
                  let args = value["a"]?.dictionaryValue else {
                throw DHTMessageError.invalidMessage
            }
            return .query(transactionID: txID, queryType: queryType, arguments: args)

        case "r":
            guard let values = value["r"]?.dictionaryValue else {
                throw DHTMessageError.invalidMessage
            }
            return .response(transactionID: txID, values: values)

        case "e":
            guard let errorList = value["e"]?.listValue,
                  errorList.count >= 2,
                  let code = errorList[0].integerValue,
                  let msg = errorList[1].utf8String else {
                throw DHTMessageError.invalidMessage
            }
            return .error(transactionID: txID, code: Int(code), message: msg)

        default:
            throw DHTMessageError.invalidMessage
        }
    }
}

public enum DHTMessageError: Error {
    case invalidMessage
}
