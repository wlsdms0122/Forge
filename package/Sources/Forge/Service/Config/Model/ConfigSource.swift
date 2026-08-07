//
//  ConfigSource.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

package enum ConfigSource: Sendable {
    case toml
    case environment(String)
    case builtin
    case none

    package var label: String {
        switch self {
        case .toml:
            return "toml"

        case .environment(let name):
            return "environment (\(name))"

        case .builtin:
            return "default"

        case .none:
            return "—"
        }
    }
}
