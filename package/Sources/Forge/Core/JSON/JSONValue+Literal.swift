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
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
    
    init(integerLiteral value: Int) {
        self = .int(value)
    }
    
    init(floatLiteral value: Double) {
        self = .double(value)
    }
    
    init(stringLiteral value: String) {
        self = .string(value)
    }
    
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
    
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
