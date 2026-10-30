//
//  OutputSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct OutputSpec: Sendable, Equatable {
    enum Extractor: Sendable, Equatable {
        case path(String)
        case regex(String)
        case line(Int)
    }
    
    enum CoerceType: String, Sendable, Decodable, Equatable {
        case string
        case int
        case float
        case bool
        case json
    }
    
    // MARK: - Property
    let extractor: Extractor
    let type: CoerceType
    let `default`: JSONValue?
    
    var canOmit: Bool { `default` != nil }
    
    // MARK: - Initializer
    init(
        extractor: Extractor,
        type: CoerceType = .string,
        default: JSONValue? = nil
    ) {
        self.extractor = extractor
        self.type = type
        self.default = `default`
    }
    
    // MARK: - Public
    // MARK: - Private
}

extension OutputSpec: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case regex
        case line
        case type
        case `default`
    }
    
    init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self.extractor = .path(path)
            self.type = .string
            self.default = nil
            
            return
        }
        
        try SpecGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "step output")
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        var found: [String] = []
        
        if container.contains(.path) { found.append("path") }
        if container.contains(.regex) { found.append("regex") }
        if container.contains(.line) { found.append("line") }
        
        guard found.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "OutputSpec must declare exactly one of"
                        + " {path, regex, line}; got: \(found)"
                )
            )
        }
        
        if container.contains(.path) {
            self.extractor = .path(try container.decode(String.self, forKey: .path))
        } else if container.contains(.regex) {
            self.extractor = .regex(try container.decode(String.self, forKey: .regex))
        } else {
            self.extractor = .line(try container.decode(Int.self, forKey: .line))
        }
        
        self.type = try container.decodeIfPresent(CoerceType.self, forKey: .type) ?? .string
        self.default = container.contains(.default)
            ? try container.decode(JSONValue.self, forKey: .default)
            : nil
    }
}
