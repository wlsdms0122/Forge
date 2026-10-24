//
//  SessionError.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

package enum SessionError: ForgeError, CustomStringConvertible {
    case invalidName(String)
    case socketPathTooLong(path: String, limit: Int)

    package var message: String { description }

    package var description: String {
        switch self {
        case .invalidName(let name):
            return "invalid session name '\(name)' — allowed [A-Za-z0-9._-], not '.' or '..'"

        case .socketPathTooLong(let path, let limit):
            return "socket path too long (\(path.utf8.count) ≥ \(limit) bytes): \(path) "
                + "— use a shorter session name or XDG_CONFIG_HOME"
        }
    }
}
