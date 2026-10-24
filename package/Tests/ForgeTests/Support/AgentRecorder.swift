//
//  AgentRecorder.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
@testable import Forge

final class AgentRecorder: Backend, @unchecked Sendable {
    // MARK: - Property
    let invocations = OrderedCollector<Forge.Invocation>()

    // MARK: - Initializer
    // MARK: - Public
    func invoke(_ invocation: Forge.Invocation) async throws -> BackendResponse {
        invocations.append(invocation)

        return BackendResponse(
            text: "echo:\(invocation.prompt)",
            usage: nil,
            toolEvents: [],
            stdoutLength: 0,
            durationMs: 1
        )
    }

    // MARK: - Private
}
