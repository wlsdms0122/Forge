//
//  OutputExtractor.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum OutputExtractor {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // The values the declarations name, read out of the text. A text that
    // does not hold what they ask fails with `OutputResolutionError`.
    static func extract(
        stdout: String,
        declarations: [String: OutputSpec]
    ) throws -> JSONValue {
        if declarations["_raw"] != nil {
            throw OutputDeclarationError(
                "outputs key `_raw` is reserved (auto-injected with raw stdout)"
            )
        }
        
        let needsJSON = declarations.values.contains { spec in
            if case .path = spec.extractor { return true } else { return false }
        }
        
        let parsedJSON = needsJSON
            ? try? JSONDecoder().decode(JSONValue.self, from: Data(stdout.utf8))
            : nil
        
        var result: [String: JSONValue] = ["_raw": .string(stdout)]
        
        for (key, spec) in declarations.sorted(by: { left, right in left.key < right.key }) {
            result[key] = try evaluate(
                spec: spec,
                key: key,
                stdout: stdout,
                parsedJSON: parsedJSON
            )
        }
        
        return .object(result)
    }
    
    // MARK: - Private
    private static func evaluate(
        spec: OutputSpec,
        key: String,
        stdout: String,
        parsedJSON: JSONValue?
    ) throws -> JSONValue {
        let raw: JSONValue?
        
        switch spec.extractor {
        case .path(let path):
            guard let parsed = parsedJSON else {
                throw OutputResolutionError(
                    "outputs.\(key): path `\(path.expression)` reads JSON, and stdout is not"
                        + " JSON. first 200 chars: \(stdout.prefix(200))"
                )
            }
            
            do {
                raw = try path.evaluate(on: parsed)
            } catch JSONPath.EvalError.notFound(let message) {
                if spec.canOmit {
                    raw = nil
                } else {
                    throw OutputResolutionError("outputs.\(key): \(message)")
                }
            }
        
        case .regex(let regex):
            raw = try matchRegex(regex, in: stdout, key: key, canOmit: spec.canOmit)
        
        case .line(let line):
            raw = matchLine(line, in: stdout)
        }
        
        if raw == nil || raw == .null {
            if let fallback = spec.default {
                return fallback == .null ? .null : try coerce(fallback, to: spec.type, key: key)
            }
            
            throw OutputResolutionError(
                "outputs.\(key): no value (declare a `default` — e.g. `null` — to allow)"
            )
        }
        
        return try coerce(raw!, to: spec.type, key: key)
    }
    
    private static func matchRegex(
        _ regex: NSRegularExpression,
        in stdout: String,
        key: String,
        canOmit: Bool
    ) throws -> JSONValue? {
        let range = NSRange(stdout.startIndex..<stdout.endIndex, in: stdout)
        
        guard let match = regex.firstMatch(in: stdout, options: [], range: range) else {
            if canOmit { return nil }
            
            throw OutputResolutionError("outputs.\(key): regex `\(regex.pattern)` did not match")
        }
        
        let captureIndex = match.numberOfRanges > 1 ? 1 : 0
        let matchedRange = match.range(at: captureIndex)
        
        guard
            matchedRange.location != NSNotFound,
            let swiftRange = Range(matchedRange, in: stdout)
        else {
            if canOmit { return nil }
            
            throw OutputResolutionError(
                "outputs.\(key): regex `\(regex.pattern)` matched but capture group missing"
            )
        }
        
        return .string(String(stdout[swiftRange]))
    }
    
    private static func matchLine(_ line: Int, in stdout: String) -> JSONValue? {
        var body = stdout
        
        if body.last?.isNewline == true { body.removeLast() }
        
        let lines = Lines.split(body).map(String.init)
        let actual = line < 0 ? lines.count + line : line
        
        guard actual >= 0, actual < lines.count else { return nil }
        
        return .string(lines[actual])
    }
    
    private static func coerce(
        _ value: JSONValue,
        to type: OutputSpec.CoerceType,
        key: String
    ) throws -> JSONValue {
        switch type {
        case .json:
            return value
        
        case .string:
            switch value {
            case .string:
                return value
            
            case .int(let integer):
                return .string(String(integer))
            
            case .double(let double):
                return .string(String(double))
            
            case .bool(let bool):
                return .string(bool ? "true" : "false")
            
            case .null:
                return .null
            
            case .array, .object:
                return .string(Self.jsonText(value))
            }
        
        case .int:
            switch value {
            case .int:
                return value
            
            case .double(let double):
                guard let integer = Int(exactly: double) else {
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce \(double) to int"
                            + " (non-integer or out of range)"
                    )
                }
                
                return .int(integer)
            
            case .string(let string):
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let integer = Int(trimmed) else {
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce \"\(trimmed)\" to int"
                    )
                }
                
                return .int(integer)
            
            case .bool(let bool):
                return .int(bool ? 1 : 0)
            
            default:
                throw OutputResolutionError(
                    "outputs.\(key): cannot coerce \(typeName(value)) to int"
                )
            }
        
        case .float:
            switch value {
            case .double:
                return value
            
            case .int(let integer):
                return .double(Double(integer))
            
            case .string(let string):
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let double = Double(trimmed) else {
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce \"\(trimmed)\" to float"
                    )
                }
                
                guard double.isFinite else {
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce \"\(trimmed)\" to float (non-finite)"
                    )
                }
                
                return .double(double)
            
            default:
                throw OutputResolutionError(
                    "outputs.\(key): cannot coerce \(typeName(value)) to float"
                )
            }
        
        case .bool:
            switch value {
            case .bool:
                return value
            
            case .string(let string):
                let lower = string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                
                switch lower {
                case "true", "1", "yes":
                    return .bool(true)
                
                case "false", "0", "no":
                    return .bool(false)
                
                default:
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce \"\(string)\" to bool"
                    )
                }
            
            case .int(let integer):
                switch integer {
                case 0:
                    return .bool(false)
                
                case 1:
                    return .bool(true)
                
                default:
                    throw OutputResolutionError(
                        "outputs.\(key): cannot coerce int \(integer) to bool (must be 0 or 1)"
                    )
                }
            
            default:
                throw OutputResolutionError(
                    "outputs.\(key): cannot coerce \(typeName(value)) to bool"
                )
            }
        }
    }
    
    private static func typeName(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        
        case .bool:
            return "bool"
        
        case .int:
            return "int"
        
        case .double:
            return "float"
        
        case .string:
            return "string"
        
        case .array:
            return "array"
        
        case .object:
            return "object"
        }
    }
}

extension OutputExtractor {
    static func jsonText(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }

        return String(decoding: data, as: UTF8.self)
    }
}
