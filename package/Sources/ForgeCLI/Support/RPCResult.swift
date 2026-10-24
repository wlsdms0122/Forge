//
//  RPCResult.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Forge

enum RPCResult {
    case ok(JSONValue)
    case err(type: String, message: String)
}
