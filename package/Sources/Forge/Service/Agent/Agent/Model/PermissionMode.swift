//
//  PermissionMode.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum PermissionMode: String, Sendable, Equatable, Codable {
    case bypass = "bypass"
    case safe = "safe"
    case restrict = "restrict"
}
