//
//  OutputSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct OutputSpec: Sendable, Equatable {
    enum Extractor: Sendable, Equatable {
        case path(JSONPath)
        case regex(NSRegularExpression)
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

// A declaration that is no extractor is the workflow's defect, refused here
// with `OutputDeclarationError` before any text is read.
extension OutputSpec: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case regex
        case line
        case type
        case `default`
    }
    
    init(from decoder: Decoder) throws {
        let name = (["outputs"] + decoder.codingPath.map(\.stringValue)).joined(separator: ".")
        
        if let expression = try? decoder.singleValueContainer().decode(String.self) {
            self.init(extractor: .path(try Self.path(expression, in: name)))
            
            return
        }
        
        let container: KeyedDecodingContainer<CodingKeys>
        
        do {
            try SpecGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: name)
            
            container = try decoder.container(keyedBy: CodingKeys.self)
        } catch let DecodingError.dataCorrupted(context) {
            throw OutputDeclarationError(context.debugDescription)
        } catch {
            throw OutputDeclarationError(
                "\(name): an extractor is a JSONPath, or a dictionary of path, regex or line"
                    + " with type and default"
            )
        }
        
        let extractors = [CodingKeys.path, .regex, .line].filter(container.contains)
        
        guard extractors.count == 1 else {
            throw OutputDeclarationError(
                "\(name): declare exactly one of path, regex and line, not"
                    + " \(extractors.isEmpty ? "none" : extractors.map(\.stringValue).joined(separator: " and "))"
            )
        }
        
        let extractor: Extractor
        
        switch extractors[0] {
        case .path:
            let expression = try Self.field(String.self, .path, of: container, in: name, is: "a JSONPath")
            
            extractor = .path(try Self.path(expression, in: name))
        
        case .regex:
            let pattern = try Self.field(String.self, .regex, of: container, in: name, is: "a regular expression")
            
            extractor = .regex(try Self.regex(pattern, in: name))
        
        default:
            extractor = .line(try Self.field(Int.self, .line, of: container, in: name, is: "an integer"))
        }
        
        self.init(
            extractor: extractor,
            type: container.contains(.type)
                ? try Self.field(
                    CoerceType.self,
                    .type,
                    of: container,
                    in: name,
                    is: "one of string, int, float, bool and json"
                )
                : .string,
            default: container.contains(.default)
                ? try container.decode(JSONValue.self, forKey: .default)
                : nil
        )
    }
    
    private static func field<Value: Decodable>(
        _ type: Value.Type,
        _ key: CodingKeys,
        of container: KeyedDecodingContainer<CodingKeys>,
        in name: String,
        is description: String
    ) throws -> Value {
        do {
            return try container.decode(type, forKey: key)
        } catch {
            throw OutputDeclarationError("\(name): `\(key.stringValue)` is \(description)")
        }
    }
    
    private static func path(_ expression: String, in name: String) throws -> JSONPath {
        do {
            return try JSONPath(expression)
        } catch {
            throw OutputDeclarationError("\(name): \(error)")
        }
    }
    
    private static func regex(_ pattern: String, in name: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        } catch {
            throw OutputDeclarationError("\(name): `\(pattern)` is no regular expression")
        }
    }
}
