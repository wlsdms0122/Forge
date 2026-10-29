//
//  WorkflowPattern.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum WorkflowPattern {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func matches(pattern: String, name: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == name { return true }
        
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast(1))
            
            return name.hasPrefix(prefix)
        }
        
        return false
    }
    
    static func isValidPattern(_ pattern: String) -> Bool {
        guard pattern.contains("*") else { return true }
        
        return pattern == "*" || (pattern.hasSuffix("*") && !pattern.dropLast(1).contains("*"))
    }
    
    // MARK: - Private
}
