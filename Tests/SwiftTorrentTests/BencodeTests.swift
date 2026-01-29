import XCTest
@testable import SwiftTorrent

final class BencodeTests: XCTestCase {
    let encoder = BencodeEncoder()
    let decoder = BencodeDecoder()

    // MARK: - Integer

    func testEncodeDecodeInteger() throws {
        let value = BencodeValue.integer(42)
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "i42e")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    func testNegativeInteger() throws {
        let value = BencodeValue.integer(-1)
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "i-1e")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    func testZeroInteger() throws {
        let value = BencodeValue.integer(0)
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "i0e")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - String

    func testEncodeDecodeString() throws {
        let value = BencodeValue.string(Data("hello".utf8))
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "5:hello")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    func testEmptyString() throws {
        let value = BencodeValue.string(Data())
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "0:")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - List

    func testEncodeDecodeList() throws {
        let value = BencodeValue.list([.integer(1), .string(Data("two".utf8)), .integer(3)])
        let data = encoder.encode(value)
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    func testEmptyList() throws {
        let value = BencodeValue.list([])
        let data = encoder.encode(value)
        XCTAssertEqual(String(data: data, encoding: .ascii), "le")
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - Dictionary

    func testEncodeDecodeDictionary() throws {
        let value = BencodeValue.dictionary([
            (key: Data("cow".utf8), value: .string(Data("moo".utf8))),
            (key: Data("spam".utf8), value: .string(Data("eggs".utf8))),
        ])
        let data = encoder.encode(value)
        let decoded = try decoder.decode(data)
        // Keys should be sorted in output
        XCTAssertEqual(decoded, value)
    }

    func testDictionarySubscript() throws {
        let data = Data("d3:fooi42ee".utf8)
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded["foo"]?.integerValue, 42)
        XCTAssertNil(decoded["bar"])
    }

    // MARK: - Round-trip

    func testNestedRoundTrip() throws {
        let value = BencodeValue.dictionary([
            (key: Data("info".utf8), value: .dictionary([
                (key: Data("name".utf8), value: .string(Data("test.txt".utf8))),
                (key: Data("piece length".utf8), value: .integer(262144)),
            ])),
            (key: Data("announce".utf8), value: .string(Data("http://tracker.example.com/announce".utf8))),
        ])
        let data = encoder.encode(value)
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded["info"]?["name"]?.utf8String, "test.txt")
        XCTAssertEqual(decoded["info"]?["piece length"]?.integerValue, 262144)
    }

    // MARK: - Error cases

    func testInvalidInput() {
        XCTAssertThrowsError(try decoder.decode(Data()))
        XCTAssertThrowsError(try decoder.decode(Data("x".utf8)))
    }
}
