//
//  ResourceActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct ResourceActionForm: WarpIR.ConstructForm {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case content
        case path
        case inputs
    }

    // MARK: - Property
    static let key = "resource"

    private let arguments: [String: Warp.Expression]

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        try KeyGate().rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "resource"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        var arguments: [String: Warp.Expression] = [:]

        switch (container.contains(.content), container.contains(.path)) {
        case (true, false):
            arguments["content"] = try container
                .decode(ExpressionReader.self, forKey: .content)
                .expression
            arguments["inputs"] = try container.decodeIfPresent(
                [String: ExpressionReader].self,
                forKey: .inputs
            )
            .map { inputs in Warp.Expression.record(inputs.mapValues(\.expression)) }

        case (false, true):
            guard !container.contains(.inputs) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "resource `path` answers a location —"
                            + " `inputs` only accompany `content`, which renders"
                    )
                )
            }

            arguments["path"] = try container
                .decode(ExpressionReader.self, forKey: .path)
                .expression

        case (true, true), (false, false):
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "resource asks exactly one of `content`"
                        + " (render the file) or `path` (locate the file)"
                )
            )
        }

        self.arguments = arguments
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        .dispatch(Dispatch(selector: ForgeSpec.selector(Self.key), arguments: arguments))
    }

    // MARK: - Private
}
