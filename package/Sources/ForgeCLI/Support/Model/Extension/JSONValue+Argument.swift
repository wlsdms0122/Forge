//
//  JSONValue+Argument.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Forge

extension JSONValue {
    // The JSON object an option's text writes; any other text ends the
    // command.
    init(objectArgument text: String, flag: String) {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = try? JSONValue(jsonObject: object)
        else {
            die("\(flag): expected a JSON object", code: 4)
        }
        
        self = value
    }
}
