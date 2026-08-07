//
//  YAMLSpec.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Yams

enum YAMLSpec {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: jsonData(fromYAML: data))
    }
    
    static func jsonData(fromYAML data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "spec file is not valid UTF-8")
            )
        }
        
        let root: Node?
        
        do {
            root = try Yams.compose(yaml: text)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "The given data was not valid YAML.",
                    underlyingError: error
                )
            )
        }
        
        guard let root else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "empty YAML document")
            )
        }
        
        return try JSONSerialization.data(
            withJSONObject: jsonObject(root),
            options: [.fragmentsAllowed]
        )
    }
    
    // MARK: - Private
    private static func jsonObject(_ node: Node) throws -> Any {
        switch node {
        case .scalar(let scalar):
            return try jsonScalar(scalar)
        
        case .sequence(let sequence):
            return try sequence.map(jsonObject)
        
        case .mapping(let mapping):
            var object: [String: Any] = [:]
            
            for (key, value) in mapping {
                guard case .scalar(let scalarKey) = key else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: [],
                            debugDescription: "non-scalar mapping key is not supported in specs"
                        )
                    )
                }
                
                object[scalarKey.string] = try jsonObject(value)
            }
            
            return object
        
        case .alias:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "YAML anchors/aliases are not supported in specs"
                )
            )
        }
    }
    
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
    
    private static func jsonScalar(_ scalar: Node.Scalar) throws -> Any {
        guard scalar.style == .plain || scalar.style == .any else { return scalar.string }
        
        let text = scalar.string
        
        switch text {
        case "", "~", "null":
            return NSNull()
        
        case "true":
            return true
        
        case "false":
            return false
        
        default:
            if matches(text, #"^-?(0|[1-9][0-9]*)$"#), let integer = Int(text) { return integer }
            
            if
                matches(text, #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#),
                let double = Double(text)
            {
                guard double.isFinite else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: [],
                            debugDescription: "numeric literal '\(text)' overflows the JSON number range"
                                + " — quote it if you meant a string"
                        )
                    )
                }
                
                return double
            }
            
            return text
        }
    }
}
