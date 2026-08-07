//
//  Principal.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum Principal {
    static func matches(pattern: String, principal: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == principal { return true }
        
        if pattern.hasSuffix(":*") {
            let prefix = String(pattern.dropLast(1))
            
            return principal.hasPrefix(prefix)
        }
        
        return false
    }
    
    static func isValidPattern(_ pattern: String) -> Bool {
        guard pattern.contains("*") else { return true }
        
        return pattern == "*"
            || (pattern.hasSuffix(":*") && !pattern.dropLast(2).contains("*"))
    }
}
