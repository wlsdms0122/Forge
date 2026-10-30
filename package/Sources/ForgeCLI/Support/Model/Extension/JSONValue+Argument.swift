//
//  JSONValue+Argument.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Forge

extension JSONValue {
    // The JSON object or array an option's text writes; any other text ends
    // the command.
    init(objectArgument text: String, flag: String) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
            case .object = value
        else {
            die("\(flag): expected a JSON object", code: 4)
        }
        
        self = value
    }
    
    init(arrayArgument text: String, flag: String) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
            case .array = value
        else {
            die("\(flag): expected a JSON array", code: 4)
        }
        
        self = value
    }
}
