//
//  PackageRootNotFound.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct PackageRootNotFound: Error, CustomStringConvertible {
    let startedAt: String

    var description: String {
        "Package.swift not found — searched upward from \(startedAt)"
    }
}
