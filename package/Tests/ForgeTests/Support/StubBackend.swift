//
//  StubBackend.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

@testable import Forge

/// A backend that returns the same answer no matter what it is asked.
///
/// Tests where the backend is not the concern (workflow execution, dispatch, scheduling)
/// still need one to stand up an executor, so the same thing kept being rewritten per file
/// under names like `StubBackend` and `NoopBackend`.
struct StubBackend: Backend {
    // MARK: - Property
    private let text: String

    // MARK: - Initializer
    init(_ text: String = "ok") {
        self.text = text
    }

    // MARK: - Public
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        BackendResponse(text: text, usage: nil, toolEvents: [], stdoutLength: 0, durationMs: 1)
    }

    // MARK: - Private
}
