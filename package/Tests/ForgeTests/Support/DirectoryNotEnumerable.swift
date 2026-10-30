//
//  DirectoryNotEnumerable.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct DirectoryNotEnumerable: Error, CustomStringConvertible {
    let directory: URL

    var description: String {
        "cannot enumerate directory: \(directory.path)"
    }
}
