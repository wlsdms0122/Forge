//
//  ChildRunFailed+RecoverableFailure.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// A dispatched run that failed at its work is a failure the parent's catch
// may take.
extension ChildRunFailed: Warp.RecoverableFailure {
    static let type = "child_run_failed"

    var type: String { Self.type }
}
