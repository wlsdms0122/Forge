//
//  RPCResult.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum RPCResult {
    case ok([String: Any])
    case err(type: String, message: String)
}
