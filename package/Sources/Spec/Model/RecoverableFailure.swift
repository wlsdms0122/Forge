//
//  RecoverableFailure.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// A failure of the work itself — the data wasn't there, the world didn't cooperate.
// Rescue paths absorb these. Author mistakes (shape misuse, contract violations)
// deliberately do NOT carry this marker so they surface instead of being absorbed.
//
// While a rescue runs, the failure exists as a value: the executor binds
// `payload` under the failed step's id, so rescue steps can read what went
// wrong (`{ ref: <id>.message }`, a shell failure's `<id>.stderr`, ...). Every
// payload carries at least `type` and `message`; each error adds its own
// vocabulary on top — the kernel owns the mechanism, the error owns the fields.
public protocol RecoverableFailure: SpecError {
    var payload: Value { get }
}
