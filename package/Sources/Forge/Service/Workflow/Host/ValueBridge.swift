//
//  ValueBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// Two mirrors of JSON meet here — the kernel's Value and forge's JSONValue.
// The bridge exists only while the old engine's edges (output extraction, the
// daemon RPC surface) still speak JSONValue; it goes with them.
enum ValueBridge {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func value(_ json: JSONValue) -> Spec.Value {
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

    static func json(_ value: Spec.Value) -> JSONValue {
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

        case .array(let array):
            return .array(array.map(json))

        case .object(let object):
            return .object(object.mapValues(json))
        }
    }

    // MARK: - Private
}
