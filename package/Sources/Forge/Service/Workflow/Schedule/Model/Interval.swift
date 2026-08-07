//
//  Interval.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct Interval: Sendable, Codable, Equatable {
    // MARK: - Property
    let seconds: Int
    
    // MARK: - Initializer
    init(seconds: Int) {
        self.seconds = seconds
    }
    
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.seconds = try Self.parse(raw, path: decoder.codingPath)
    }
    
    // MARK: - Public
    static func parse(_ raw: String, path: [CodingKey] = []) throws -> Int {
        func unit(_ character: Character) -> Int? {
            switch character {
            case "s": 1
            case "m": 60
            case "h": 3600
            case "d": 86400
            default: nil
            }
        }
        
        func fail(_ message: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: path, debugDescription: message))
        }
        
        let text = raw.replacingOccurrences(of: " ", with: "")
        
        guard !text.isEmpty else { throw fail("empty duration") }
        
        if let seconds = Int(text) {
            guard seconds > 0 else { throw fail("duration must be positive: \(raw)") }
            
            return seconds
        }
        
        var total = 0
        var number = ""
        var sawToken = false
        
        for character in text {
            if character.isNumber {
                number.append(character)
                
                continue
            }
            
            guard let multiplier = unit(character) else {
                throw fail("unsupported duration unit '\(character)' in: \(raw)")
            }
            
            guard let value = Int(number), value > 0 else {
                throw fail("duration must be a positive integer: \(raw)")
            }
            
            let (scaled, scaleOverflow) = value.multipliedReportingOverflow(by: multiplier)
            
            guard !scaleOverflow else { throw fail("duration too large: \(raw)") }
            
            let (sum, sumOverflow) = total.addingReportingOverflow(scaled)
            
            guard !sumOverflow else { throw fail("duration too large: \(raw)") }
            
            total = sum
            number = ""
            sawToken = true
        }
        
        guard number.isEmpty else { throw fail("trailing number without unit in: \(raw)") }
        guard sawToken, total > 0 else { throw fail("invalid duration: \(raw)") }
        
        return total
    }
    
    static func format(_ seconds: Int) -> String {
        if seconds % 86400 == 0 { return "\(seconds / 86400)d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        
        return "\(seconds)s"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        try container.encode(Self.format(seconds))
    }
    
    // MARK: - Private
}
