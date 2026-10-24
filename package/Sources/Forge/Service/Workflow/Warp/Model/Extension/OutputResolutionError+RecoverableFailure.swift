//
//  OutputResolutionError+RecoverableFailure.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp

// A text that does not hold what an extraction asks of it is a failure a
// workflow's rescue may take.
extension OutputResolutionError: Warp.RecoverableFailure {
    static let type = "extract_refused"

    var type: String { Self.type }
}
