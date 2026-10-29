//
//  InstanceError.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum InstanceError: ForgeError {
    case invalidName(String)
    case socketPathTooLong(path: String, limit: Int)

    var message: String {
        switch self {
        case .invalidName(let name):
            return "invalid instance name '\(name)': allowed [A-Za-z0-9._-], not '.' or '..'"

        case .socketPathTooLong(let path, let limit):
            return "socket path too long (\(path.utf8.count) ≥ \(limit) bytes): \(path); "
                + "use a shorter instance name or XDG_CONFIG_HOME"
        }
    }
}
