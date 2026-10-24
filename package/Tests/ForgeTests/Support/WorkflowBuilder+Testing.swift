//
//  WorkflowBuilder+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
@testable import Forge

extension WorkflowBuilder {
    // A builder over the vocabulary the binary carries, which compiles it
    // once for the suites.
    static let shipped = ForgeVocabulary.shipped.map { vocabulary in WorkflowBuilder(vocabulary: vocabulary) }
}
