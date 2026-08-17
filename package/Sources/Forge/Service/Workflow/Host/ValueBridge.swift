//
//  ValueBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Two mirrors of JSON meet here — the kernel's Value and forge's JSONValue.
// The bridge exists only while the old engine's edges (output extraction, the
// daemon RPC surface) still speak JSONValue; it goes with them.
enum ValueBridge {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func value(_ json: JSONValue) -> Warp.Value {
        switch json {
        case .null:
            return .null

        case .bool(let bool):
            return .bool(bool)

        case .int(let int):
            return .int(int)

        case .double(let double):
            return .double(double)

        case .string(let string):
            return .string(string)

        case .array(let array):
            return .array(array.map(value))

        case .object(let object):
            return .object(object.mapValues(value))
        }
    }

    static func json(_ value: Warp.Value) -> JSONValue {
        switch value {
        case .null:
            return .null

        case .bool(let bool):
            return .bool(bool)

        case .int(let int):
            return .int(int)

        case .double(let double):
            return .double(double)

        case .string(let string):
            return .string(string)

        // Nothing crosses out. A procedure is code, and the wire this bridges
        // to carries data — a workflow that answers with one has answered with
        // something JSON has no shape for.
        case .procedure:
            return .null

        case .array(let array):
            return .array(array.map(json))

        case .object(let object):
            return .object(object.mapValues(json))
        }
    }

    // A number however the notation wrote it — `timeout: 30` reads as int, and
    // a host deadline does not care which spelling it arrived in.
    static func number(_ value: Warp.Value) -> Double? {
        switch value {
        case .double(let double):
            return double

        case .int(let integer):
            return Double(integer)

        default:
            return nil
        }
    }

    // A Codable payload carried through the IR as data. A word's arguments are
    // values, so anything a form reads at load and a word needs at run crosses
    // here rather than riding along as a Swift field on the expression.
    // The kernel's Value is Encodable and nothing else — reading a document is
    // the front end's job — so forge's own JSONValue is the crossing point in
    // both directions.
    static func value<T: Encodable>(_ payload: T) throws -> Warp.Value {
        value(try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(payload)))
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from value: Warp.Value
    ) throws -> T? {
        guard value != .null else { return nil }

        return try JSONDecoder().decode(
            type,
            from: try JSONEncoder().encode(json(value))
        )
    }

    // MARK: - Private
}
