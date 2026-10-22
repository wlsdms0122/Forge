//
//  BackendNonzeroExit+RecoverableFailure.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// A command that exited nonzero is a failure a workflow's rescue may take.
extension BackendNonzeroExit: Warp.RecoverableFailure {
    static let type = "nonzero_exit"

    var type: String { Self.type }

    var details: Value.Dictionary {
        Value.Dictionary([
            "exit_code": .int(Int(exitCode)),
            "stderr": .string(stderr),
            "stdout": .string(stdout)
        ])
    }
}
