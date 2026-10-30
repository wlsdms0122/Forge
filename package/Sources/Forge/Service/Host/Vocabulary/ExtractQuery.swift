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
    static let signature = Signature(
        of: Self.self,
        returns: .dictionary(key: .string, value: .any),
        failing: .these([OutputResolutionError.type]),
        constness: .const,
        isolation: .isolated
    )

    // MARK: - Initializer
    // MARK: - Public
    func evaluate(_ question: Warp.Question<Self>) async throws -> Warp.Value {
        let declarations: [String: OutputSpec]

        // A dictionary that is no extractor is the workflow's defect, which no text
        // makes right.
        do {
            declarations = try ValueBridge.decode([String: OutputSpec].self, from: question[.outputs])
        } catch let error as OutputDeclarationError {
            throw error
        } catch {
            throw OutputDeclarationError("outputs: \(error)")
        }

        return try ValueBridge.value(
            try OutputExtractor.extract(stdout: ValueBridge.text(question[.text]), declarations: declarations)
        )
    }

    // MARK: - Private
}
