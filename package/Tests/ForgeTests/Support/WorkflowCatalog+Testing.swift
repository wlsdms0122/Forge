//
//  WorkflowCatalog+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
@testable import Forge

extension WorkflowCatalog {
    // A catalog of this directory, built by the suites' one builder.
    init(directory: URL?) throws {
        self.init(directory: directory, builder: try WorkflowBuilder.shipped.get())
    }
}
