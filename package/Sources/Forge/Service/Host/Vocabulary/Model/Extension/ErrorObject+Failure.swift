//
//  ErrorObject+Failure.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Warp

extension ErrorObject {
    // A run's or a step's failure. A failure of the language that Forge does
    // not name goes under the name the language gives it, the one a
    // workflow's `catch` reads.
    init(failure error: any Error) {
        guard !(error is any ForgeError), let failure = error as? any Warp.RecoverableFailure else {
            self.init(error)

            return
        }

        self.init(type: failure.type, message: String(describing: error), details: [:])
    }
}
