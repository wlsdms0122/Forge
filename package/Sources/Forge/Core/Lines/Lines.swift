//
//  Lines.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum Lines {
    static func split(_ text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }
    
    static func nonEmpty(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isNewline)
    }
}
