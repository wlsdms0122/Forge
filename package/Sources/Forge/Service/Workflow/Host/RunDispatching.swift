//
//  RunDispatching.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

protocol RunDispatching: Sendable {
    func dispatch(
        name: String?,
        inline: Spec.Value?,
        inputs: [String: Spec.Value]
    ) async throws -> Spec.Value
}
