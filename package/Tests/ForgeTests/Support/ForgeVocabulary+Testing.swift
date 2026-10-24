//
//  ForgeVocabulary+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
@testable import Forge

extension ForgeVocabulary {
    // The vocabulary the binary carries, built once for the suites.
    static let shipped = Result { try ForgeVocabulary() }
}
