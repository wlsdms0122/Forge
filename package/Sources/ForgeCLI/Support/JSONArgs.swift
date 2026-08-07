//
//  JSONArgs.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation

func parseJSONObjectArg(_ text: String, flag: String) -> [String: Any] {
    guard
        let data = text.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any]
    else {
        die("\(flag): expected a JSON object", code: 4)
    }
    
    return dictionary
}
