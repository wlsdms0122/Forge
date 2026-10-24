//
//  JSONValue+JSONSerialization.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The value as Foundation's JSON objects, which `JSONSerialization` reads
// and writes: a number is read the way `JSONDecoder` reads its text, so a
// whole number is an `int`.
extension JSONValue {
    init(jsonObject: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed])
        
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
    
    var jsonObject: Any {
        switch self {
        case .null:
            NSNull()
        
        case let .bool(bool):
            bool
        
        case let .int(integer):
            integer
        
        case let .double(double):
            double
        
        case let .string(string):
            string
        
        case let .array(array):
            array.map(\.jsonObject)
        
        case let .object(object):
            object.mapValues(\.jsonObject)
        }
    }
}
