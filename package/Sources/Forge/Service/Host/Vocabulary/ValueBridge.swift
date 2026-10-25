//
//  ValueBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Converts between Warp's Value and Forge's JSONValue, where a verb's
// arguments and results meet the JSON that Forge's services and RPC speak.
enum ValueBridge {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func value(_ json: JSONValue) throws -> Warp.Value {
        switch json {
        case .null:
            return .null

        case let .bool(bool):
            return .bool(bool)

        case let .int(int):
            return .int(int)

        case let .double(double):
            return .double(double)

        case let .string(string):
            return .string(string)

        case let .array(array):
            return .array(try array.map(value))

        case let .object(object):
            return .dictionary(
                try Value.Dictionary(
                    try object.map { key, field in (key: Value.string(key), value: try value(field)) }
                )
            )
        }
    }

    static func json(_ value: Warp.Value) throws -> JSONValue {
        switch value {
        case .null:
            return .null

        case let .bool(bool):
            return .bool(bool)

        case let .int(int):
            return .int(int)

        case let .double(double):
            return .double(double)

        case let .string(string):
            return .string(string)

        case let .bytes(bytes):
            return .array(bytes.map { byte in .int(Int(byte)) })

        case .procedure:
            throw UnwritableValue("a procedure has no JSON form")

        case let .array(array):
            return .array(try array.map(json))

        case let .dictionary(dictionary):
            var object: [String: JSONValue] = [:]

            for (key, field) in zip(dictionary.keys, dictionary.values) {
                let name = text(key)

                guard object[name] == nil else {
                    throw UnwritableValue("two keys of a dictionary write the one JSON key '\(name)'")
                }

                object[name] = try json(field)
            }

            return .object(object)

        case let .struct(instance):
            return .object(
                Dictionary(
                    try zip(instance.names, instance.values).map { name, field in (name.spelling, try json(field)) },
                    uniquingKeysWith: { first, _ in first }
                )
            )

        case let .existential(existential):
            return try json(existential.value)
        }
    }

    // The fields of a struct or the entries of a dictionary, under their names; null
    // holds none.
    static func fields(_ value: Warp.Value) throws -> [String: Warp.Value] {
        switch value {
        case .null:
            return [:]

        case let .dictionary(dictionary):
            return Dictionary(
                zip(dictionary.keys, dictionary.values).map { key, field in (text(key), field) },
                uniquingKeysWith: { first, _ in first }
            )

        case let .struct(instance):
            return Dictionary(
                zip(instance.names, instance.values).map { name, field in (name.spelling, field) },
                uniquingKeysWith: { first, _ in first }
            )

        case let .existential(existential):
            return try fields(existential.value)

        case let other:
            throw ExecutionError("a dictionary was expected, and \(other.nominal) arrived")
        }
    }

    // The same, each value spelled as text.
    static func strings(_ value: Warp.Value) throws -> [String: String] {
        try fields(value).mapValues(text)
    }

    // A value spelled the way a command line or a template wants it: a string
    // as its characters, anything else in the language's own spelling.
    static func text(_ value: Warp.Value) -> String {
        Rendering(value).text()
    }

    // A number however the notation wrote it — `timeout: 30` reads as int, and
    // a step deadline does not care which spelling it arrived in.
    static func number(_ value: Warp.Value) -> Double? {
        switch value {
        case let .double(double):
            return double

        case let .int(integer):
            return Double(integer)

        default:
            return nil
        }
    }

    // A Codable payload carried through as data.
    static func value<T: Encodable>(_ payload: T) throws -> Warp.Value {
        try value(try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(payload)))
    }

    // A value read back as a Codable payload: the other way of `value(_:)`.
    static func decode<T: Decodable>(
        _ type: T.Type,
        from value: Warp.Value
    ) throws -> T {
        try JSONDecoder().decode(
            type,
            from: try JSONEncoder().encode(json(value))
        )
    }

    // MARK: - Private
}
