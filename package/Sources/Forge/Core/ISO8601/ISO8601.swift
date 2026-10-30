//
//  ISO8601.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum ISO8601 {
    // MARK: - Property
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        return formatter
    }()
    
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return formatter
    }()
    
    // MARK: - Initializer
    // MARK: - Public
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        return plain.date(from: trimmed) ?? fractional.date(from: trimmed)
    }
    
    static func string(_ date: Date) -> String {
        plain.string(from: date)
    }
    
    // MARK: - Private
}
