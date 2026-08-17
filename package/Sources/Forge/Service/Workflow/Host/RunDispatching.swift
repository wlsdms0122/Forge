//
//  RunDispatching.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

protocol RunDispatching: Sendable {
    func dispatch(
        name: String?,
        inline: Warp.Value?,
        inputs: [String: Warp.Value]
    ) async throws -> Warp.Value
}
