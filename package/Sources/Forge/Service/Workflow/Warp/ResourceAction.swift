//
//  ResourceAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpIR

// Asks the resource root one of two questions, named by what the step gets
// back. `content` reads the file and renders it as a template over the given
// inputs. `path` resolves the file's absolute location without ever reading
// it — the form for handing a script to `shell`, where rendering would be
// wrong twice over: a script's own `$` syntax is not template dialect, and an
// executable wants to be run, not inlined.
struct ResourceAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)

        if let file = try invocation.string("path") {
            return .string(try await environment.resources.locate(file))
        }

        guard let file = try invocation.string("content") else {
            throw ExecutionError(
                "resource asks exactly one of `content` or `path`"
            )
        }

        var inputs: [String: Warp.Value] = [:]

        if case .object(let written) = try invocation.resolve("inputs") {
            inputs = written
        }

        return .string(
            try await Self.render(
                relative: file,
                inputs: inputs,
                resources: environment.resources
            )
        )
    }

    // MARK: - Private
    private static func render(
        relative: String,
        inputs: [String: Warp.Value],
        resources: any ResourceReading
    ) async throws -> String {
        let body = try await resources.read(relative)

        // The resource body is a template over the given inputs — the kernel
        // parses it and renders it against a scope holding nothing but those
        // inputs, the same closed surface `{ format: }` uses.
        let segments = try TemplateParser().parse(body)

        return try Warp.TemplateRenderer().render(segments, over: inputs)
    }
}
