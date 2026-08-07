//
//  ValueDecoder.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Decodes Codable types directly from a Value tree. Serializing through JSON text
// would collapse the scalar typing the loader fixed — `3.0` re-reads as int — so
// the loader's Value is the decoding source itself, with no round trip.
struct ValueDecoder: Decoder {
    private struct AnyKey: CodingKey {
        // MARK: - Property
        let stringValue: String
        let intValue: Int?

        // MARK: - Initializer
        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }

        // MARK: - Public
        // MARK: - Private
    }

    private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        // MARK: - Property
        let object: [String: Value]
        let codingPath: [CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        var allKeys: [Key] {
            object.keys.compactMap { key in Key(stringValue: key) }
        }

        // MARK: - Initializer
        // MARK: - Public
        func contains(_ key: Key) -> Bool {
            object[key.stringValue] != nil
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            try value(forKey: key) == .null
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try T(from: decoder(forKey: key))
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try decoder(forKey: key).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try decoder(forKey: key).unkeyedContainer()
        }

        func superDecoder() throws -> Decoder {
            guard let key = Key(stringValue: "super") else {
                throw DecodingError.keyNotFound(
                    AnyKey(stringValue: "super"),
                    .init(codingPath: codingPath, debugDescription: "no super key")
                )
            }

            return try decoder(forKey: key)
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            try decoder(forKey: key)
        }

        // MARK: - Private
        private func value(forKey key: Key) throws -> Value {
            guard let value = object[key.stringValue] else {
                throw DecodingError.keyNotFound(
                    key,
                    .init(
                        codingPath: codingPath,
                        debugDescription: "no value for key '\(key.stringValue)'"
                    )
                )
            }

            return value
        }

        private func decoder(forKey key: Key) throws -> ValueDecoder {
            ValueDecoder(
                value: try value(forKey: key),
                codingPath: codingPath + [key],
                userInfo: userInfo
            )
        }
    }

    private struct UnkeyedContainer: UnkeyedDecodingContainer {
        // MARK: - Property
        let array: [Value]
        let codingPath: [CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        var count: Int? { array.count }

        var isAtEnd: Bool { currentIndex >= array.count }

        private(set) var currentIndex = 0

        // MARK: - Initializer
        // MARK: - Public
        mutating func decodeNil() throws -> Bool {
            guard try current() == .null else { return false }

            currentIndex += 1

            return true
        }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            let decoded = try T(from: ValueDecoder(
                value: try current(),
                codingPath: codingPath + [AnyKey(intValue: currentIndex)],
                userInfo: userInfo
            ))

            currentIndex += 1

            return decoded
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type
        ) throws -> KeyedDecodingContainer<NestedKey> {
            let container = try ValueDecoder(
                value: try current(),
                codingPath: codingPath + [AnyKey(intValue: currentIndex)],
                userInfo: userInfo
            ).container(keyedBy: type)

            currentIndex += 1

            return container
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let container = try ValueDecoder(
                value: try current(),
                codingPath: codingPath + [AnyKey(intValue: currentIndex)],
                userInfo: userInfo
            ).unkeyedContainer()

            currentIndex += 1

            return container
        }

        mutating func superDecoder() throws -> Decoder {
            let decoder = ValueDecoder(
                value: try current(),
                codingPath: codingPath + [AnyKey(intValue: currentIndex)],
                userInfo: userInfo
            )

            currentIndex += 1

            return decoder
        }

        // MARK: - Private
        private func current() throws -> Value {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(
                    Value.self,
                    .init(
                        codingPath: codingPath,
                        debugDescription: "unkeyed container is at end"
                    )
                )
            }

            return array[currentIndex]
        }
    }

    private struct SingleContainer: SingleValueDecodingContainer {
        // MARK: - Property
        let value: Value
        let codingPath: [CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        // MARK: - Initializer
        // MARK: - Public
        func decodeNil() -> Bool {
            value == .null
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            guard case .bool(let bool) = value else { throw mismatch(type) }

            return bool
        }

        func decode(_ type: String.Type) throws -> String {
            guard case .string(let string) = value else { throw mismatch(type) }

            return string
        }

        func decode(_ type: Int.Type) throws -> Int {
            guard case .int(let integer) = value else { throw mismatch(type) }

            return integer
        }

        func decode(_ type: Double.Type) throws -> Double {
            switch value {
            case .double(let double):
                return double

            case .int(let integer):
                return Double(integer)

            default:
                throw mismatch(type)
            }
        }

        func decode(_ type: Float.Type) throws -> Float {
            Float(try decode(Double.self))
        }

        func decode(_ type: Int8.Type) throws -> Int8 { try narrowed(type) }

        func decode(_ type: Int16.Type) throws -> Int16 { try narrowed(type) }

        func decode(_ type: Int32.Type) throws -> Int32 { try narrowed(type) }

        func decode(_ type: Int64.Type) throws -> Int64 { try narrowed(type) }

        func decode(_ type: UInt.Type) throws -> UInt { try narrowed(type) }

        func decode(_ type: UInt8.Type) throws -> UInt8 { try narrowed(type) }

        func decode(_ type: UInt16.Type) throws -> UInt16 { try narrowed(type) }

        func decode(_ type: UInt32.Type) throws -> UInt32 { try narrowed(type) }

        func decode(_ type: UInt64.Type) throws -> UInt64 { try narrowed(type) }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try T(from: ValueDecoder(
                value: value,
                codingPath: codingPath,
                userInfo: userInfo
            ))
        }

        // MARK: - Private
        private func narrowed<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            guard
                case .int(let integer) = value,
                let narrowed = T(exactly: integer)
            else {
                throw mismatch(type)
            }

            return narrowed
        }

        private func mismatch(_ type: Any.Type) -> DecodingError {
            .typeMismatch(
                type,
                .init(
                    codingPath: codingPath,
                    debugDescription: "expected \(type), found \(value.typeName)"
                )
            )
        }
    }

    // MARK: - Property
    let value: Value
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    // MARK: - Initializer
    // MARK: - Public
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = value else {
            throw DecodingError.typeMismatch(
                [String: Value].self,
                .init(
                    codingPath: codingPath,
                    debugDescription: "expected object, found \(value.typeName)"
                )
            )
        }

        return KeyedDecodingContainer(KeyedContainer(
            object: object,
            codingPath: codingPath,
            userInfo: userInfo
        ))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = value else {
            throw DecodingError.typeMismatch(
                [Value].self,
                .init(
                    codingPath: codingPath,
                    debugDescription: "expected array, found \(value.typeName)"
                )
            )
        }

        return UnkeyedContainer(array: array, codingPath: codingPath, userInfo: userInfo)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleContainer(value: value, codingPath: codingPath, userInfo: userInfo)
    }
}
