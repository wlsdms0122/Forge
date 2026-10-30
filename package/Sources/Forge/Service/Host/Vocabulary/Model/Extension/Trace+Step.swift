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

    // The step a native verb runs for, read from its own trace: the name of
    // the statement that called its verb.
    func step(sentFrom verbs: Set<Name>) -> String {
        call(sentFrom: verbs).statement.step
    }

    // The call of one of these verbs a native runs for, read from the
    // native's own trace: where the procedure that sent it is one of these
    // verbs, the statement that called that verb, and the verb; otherwise
    // the statement that called the native, and no verb.
    func call(sentFrom verbs: Set<Name>) -> (statement: Trace, verb: Name?) {
        var hops = hops

        if case .procedure = hops.last { hops.removeLast() }

        guard
            let frame = Self.frame(in: hops, ofOneOf: verbs),
            case let .procedure(sender) = hops[frame],
            let verb = try? Name(sender)
        else {
            return (Trace(hops: hops), nil)
        }

        return (Trace(hops: Array(hops[..<frame])), verb)
    }

    // Where the innermost body these hops entered is one of these
    // procedures', the hop that entered it.
    private static func frame(in hops: [Hop], ofOneOf procedures: Set<Name>) -> Int? {
        guard
            let frame = hops.lastIndex(where: { hop in isFrame(hop) }),
            case let .procedure(sender) = hops[frame],
            let name = try? Name(sender),
            procedures.contains(name)
        else {
            return nil
        }

        return frame
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
