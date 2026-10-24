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

    // The step a native verb runs for, read from its own trace: where the
    // procedure that sent it is one of these verbs, the statement that sent
    // that verb, and otherwise the innermost statement.
    func step(sentFrom verbs: Set<Name>) -> String {
        var hops = hops

        if case .procedure = hops.last { hops.removeLast() }

        guard
            let frame = hops.lastIndex(where: { hop in Self.isFrame(hop) }),
            case let .procedure(sender) = hops[frame],
            let name = try? Name(sender),
            verbs.contains(name),
            let statement = hops[..<frame].last,
            case let .statement(step) = statement
        else {
            return self.step
        }

        return step
    }

    // A hop that enters a body: a procedure's or a closure's.
    private static func isFrame(_ hop: Hop) -> Bool {
        switch hop {
        case .procedure, .closure:
            true

        case .statement, .round, .piece:
            false
        }
    }
}
