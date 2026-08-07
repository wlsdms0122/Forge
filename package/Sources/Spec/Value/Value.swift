//
//  Value.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public indirect enum Value: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Value])
    case object([String: Value])

    // MARK: - Property
    public var typeName: String {
        switch self {
        case .null:
            return "null"

        case .bool:
            return "bool"

        case .int:
            return "int"

        case .double:
            return "double"

        case .string:
            return "string"

        case .array:
            return "array"

        case .object:
            return "object"
        }
    }

    // MARK: - Initializer
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null

            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)

            return
        }

        if let int = try? container.decode(Int.self) {
            self = .int(int)

            return
        }

        if let double = try? container.decode(Double.self) {
            self = .double(double)

            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)

            return
        }

        if let array = try? container.decode([Value].self) {
            self = .array(array)

            return
        }

        if let object = try? container.decode([String: Value].self) {
            self = .object(object)

            return
        }

        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Value could not be decoded"
            )
        )
    }

    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()

        case .bool(let bool):
            try container.encode(bool)

        case .int(let int):
            try container.encode(int)

        case .double(let double):
            try container.encode(double)

        case .string(let string):
            try container.encode(string)

        case .array(let array):
            try container.encode(array)

        case .object(let object):
            try container.encode(object)
        }
    }

    // The equality conditions test with — strict except that int and double unify
    // across numeric width, applied recursively through arrays and objects.
    public func matches(_ other: Value) -> Bool {
        switch (self, other) {
        case let (.int(left), .double(right)):
            return Double(left) == right

        case let (.double(left), .int(right)):
            return left == Double(right)

        case let (.array(left), .array(right)):
            return left.count == right.count
                && zip(left, right).allSatisfy { pair in pair.0.matches(pair.1) }

        case let (.object(left), .object(right)):
            return left.count == right.count
                && left.allSatisfy { key, value in
                    right[key].map { other in value.matches(other) } ?? false
                }

        default:
            return self == other
        }
    }

    // MARK: - Private
}
