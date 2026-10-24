//
//  JSONValue+Literal.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

extension JSONValue:
    ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    package init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
    
    package init(integerLiteral value: Int) {
        self = .int(value)
    }
    
    package init(floatLiteral value: Double) {
        self = .double(value)
    }
    
    package init(stringLiteral value: String) {
        self = .string(value)
    }
    
    package init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
    
    package init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
