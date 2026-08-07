//
//  TestSupport.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

struct TestRecoverableFailure: RecoverableFailure {
    // MARK: - Property
    let message = "the world did not cooperate"

    var payload: Value {
        .object(["type": .string("test"), "message": .string(message)])
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct TestFatalError: SpecError {
    // MARK: - Property
    let message = "author mistake"

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FailAction: Action {
    // MARK: - Property
    static let key = "fail"

    let recoverable: Bool

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        self.recoverable = try decoder.singleValueContainer().decode(Bool.self)
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Value {
        if recoverable { throw TestRecoverableFailure() }

        throw TestFatalError()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(recoverable)
    }

    // MARK: - Private
}

struct MemoryStore: SpecStore {
    // MARK: - Property
    let specs: [String: Program]

    // MARK: - Initializer
    // MARK: - Public
    func spec(named name: String) async throws -> Program {
        guard let spec = specs[name] else {
            throw ExecutionError("unknown spec '\(name)'")
        }

        return spec
    }

    // MARK: - Private
}

func path(_ text: String) -> [PathSegment] {
    try! TemplateParser().parseRefPath(text)
}

extension SpecLoader {
    static let testing = SpecLoader(
        registry: try! ActionRegistry.standard.registering(FailAction.self)
    )
}
