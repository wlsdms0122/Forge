//
//  ExtractQuery.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp

// The values a text holds, read out by named extractors: what a shell step's
// output says, once it is a string.
struct ExtractQuery: Warp.Query {
    enum Parameters: Int, ParameterSet {
        case text
        case outputs

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .text:
                Parameter(name: "text", type: .string)

            case .outputs:
                Parameter(name: "outputs", type: .dictionary(key: .string, value: .any))
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func evaluate(_ question: Warp.Question<Self>) async throws -> Warp.Value {
        let declarations: [String: OutputSpec]

        // A map that is no extractor is the workflow's defect, which no text
        // makes right.
        do {
            declarations = try ValueBridge.decode([String: OutputSpec].self, from: question[.outputs])
        } catch {
            throw WorkflowValidationError("outputs: \(error)")
        }

        return try ValueBridge.value(
            try OutputExtractor.extract(stdout: ValueBridge.text(question[.text]), declarations: declarations)
        )
    }

    // MARK: - Private
}
