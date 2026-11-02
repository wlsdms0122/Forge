//
//  PackageVersionToolError.swift
//  PackageVersionTool
//
//  Created by JSilver on 11/1/26.
//

import Foundation

// A manifest whose `[package] version` cannot be written into the binary.
enum PackageVersionToolError: Error, CustomStringConvertible {
    case undeclaredVersion
    case unreadableVersion(String)

    // MARK: - Property
    var description: String {
        switch self {
        case .undeclaredVersion:
            "[package] version is missing"

        case let .unreadableVersion(version):
            "[package] version '\(version)' is not major.minor.patch"
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
