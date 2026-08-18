//
//  DynamicActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct DynamicActionForm: WarpIR.ConstructForm {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case compose
        case result
    }

    // MARK: - Property
    static let key = "dynamic"

    private let arguments: [String: Warp.Expression]
    private let output: Warp.Expression?

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        try KeyGate().rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "dynamic"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        let compose = try container.decode([ExpressionReader].self, forKey: .compose)
            .map(\.expression)

        guard !compose.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "dynamic.compose is empty"
                )
            )
        }

        var arguments: [String: Warp.Expression] = [:]

        arguments["compose"] = .array(compose)

        self.arguments = arguments
        self.output = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .result
        )?
        .expression
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        // The output is authored against the fragment's step ids, which do not
        // exist until the fragment is lowered — so it is carried as a quoted
        // body that dynamic checks itself, once they do.
        .dispatch(
            Dispatch(
                selector: ForgeSpec.selector(Self.key),
                arguments: arguments,
                blocks: output.map { output in
                    [Warp.BlockDeclaration(
                        label: "output",
                        block: Warp.Block(body: [], result: output),
                        bindings: .deferred
                    )]
                } ?? []
            )
        )
    }

    // MARK: - Private
}
