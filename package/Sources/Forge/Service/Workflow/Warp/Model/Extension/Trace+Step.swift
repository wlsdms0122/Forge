//
//  Trace+Step.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

extension Trace {
    // The innermost statement the run is in, which is the step a ledger names.
    var step: String {
        for hop in hops.reversed() {
            if case let .statement(name) = hop { return name }
        }

        return ""
    }
}
