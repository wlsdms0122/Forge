//
//  WorkflowContract.swift
//  Forge
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import Warp

struct WorkflowContract {
    // MARK: - Property
    // MARK: - Initializer
    init() {
    }

    // MARK: - Public
    // What a caller fills in. An optional parameter is one a caller may leave
    // out, and the wire marks it with a null default.
    func inputs(of signature: Signature) -> [String: Any] {
        Dictionary(
            signature.parameters.map { parameter in
                var described: [String: Any] = ["type": parameter.type.rendered]

                if case .nullable = parameter.type { described["default"] = NSNull() }

                return (parameter.name.spelling, described)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // What a run returns.
    func returns(of signature: Signature) -> String {
        signature.returns.rendered
    }

    // MARK: - Private
}
