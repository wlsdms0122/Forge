//
//  WorkflowReader+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
@testable import Forge

extension WorkflowReader {
    // A reader of this root, built by the suites' one builder.
    init(directory: URL?) throws {
        self.init(root: DocumentRoot(directory: directory), builder: try WorkflowBuilder.shipped.get())
    }
}
