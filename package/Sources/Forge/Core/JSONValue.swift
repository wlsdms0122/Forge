//
//  JSONValue.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

indirect enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    
    init(from decoder: Decoder) throws {
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
        
        if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
            
            return
        }
        
        if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
            
            return
        }
        
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "JSONValue could not be decoded"
            )
        )
    }
    
    func encode(to encoder: Encoder) throws {
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
    
    func numericEqual(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case let (.int(left), .double(right)):
            return Double(left) == right
        
        case let (.double(left), .int(right)):
            return left == Double(right)
        
        case let (.array(left), .array(right)):
            return left.count == right.count
                && zip(left, right).allSatisfy { pair in pair.0.numericEqual(pair.1) }
        
        case let (.object(left), .object(right)):
            return left.count == right.count
                && left.allSatisfy { key, value in
                    right[key].map { other in value.numericEqual(other) } ?? false
                }
        
        default:
            return self == other
        }
    }
}
