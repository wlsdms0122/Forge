//
//  WorkflowRunResult+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
@testable import Forge

extension WorkflowRunResult {
    // The value the run returned as the wire writes it, which a run that
    // failed has none of.
    var output: JSONValue? {
        guard case let .returned(value) = outcome else { return nil }

        return try? ValueBridge.json(value)
    }

    var failure: RunFailure? {
        guard case let .failed(failure) = outcome else { return nil }

        return failure
    }
}
