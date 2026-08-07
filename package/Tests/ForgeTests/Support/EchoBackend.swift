//
//  EchoBackend.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

@testable import Forge

/// A backend that returns the received prompt prefixed with `echo:`.
///
/// How the prompt was assembled can be read back from the result string, so tests that
/// check resolution and substitution can observe their input without standing up a
/// dedicated backend.
struct EchoBackend: Backend {
    // MARK: - Property
    let prompts = OrderedCollector<String>()

    // MARK: - Initializer
    // MARK: - Public
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        prompts.append(invocation.prompt)

        return BackendResponse(
            text: "echo:\(invocation.prompt)",
            usage: AgentUsage(inputTokens: 1, outputTokens: 1),
            toolEvents: [],
            stdoutLength: invocation.prompt.count + 5,
            durationMs: 1
        )
    }

    // MARK: - Private
}
