//
//  DispatchActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct DispatchActionForm: WarpIR.ConstructForm {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case spec
        case inputs
        case timeout
    }

    // MARK: - Property
    static let key = "dispatch"

    private let arguments: [String: Warp.Expression]

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        try KeyGate().rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "dispatch"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(ExpressionReader.self, forKey: .name)?
            .expression
        let inline = try container.decodeIfPresent(ValueReader.self, forKey: .spec)?.value

        switch (name, inline) {
        case (nil, nil), (.some, .some):
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "dispatch must declare exactly one of `name` or `spec`"
                )
            )

        default:
            break
        }

        var arguments: [String: Warp.Expression] = [:]

        arguments["name"] = name
        arguments["spec"] = inline.map(Warp.Expression.literal)
        arguments["inputs"] = try container.decodeIfPresent(
            [String: ExpressionReader].self,
            forKey: .inputs
        )
        .map { inputs in Warp.Expression.record(inputs.mapValues(\.expression)) }
        arguments["timeout"] = try container.decodeIfPresent(Double.self, forKey: .timeout)
            .map { timeout in Warp.Expression.literal(.double(timeout)) }

        self.arguments = arguments

        // The inline body lowers through the loader this form is being decoded
        // with — same registry, same vocabulary, same validation — so a
        // malformed inline target fails the load, not the run.
        if let inline {
            guard let loader = decoder.userInfo[.loader] as? Loader else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "dispatch inline spec requires the configuring"
                            + " loader"
                    )
                )
            }

            do {
                // One procedure's worth of data, not a document — the same
                // shape the RPC door admits, checked at load so a broken
                // inline spec is refused before anything runs.
                _ = try loader.procedure(from: inline)
            } catch {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "\(error)")
                )
            }
        }
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        .dispatch(Dispatch(selector: ForgeSpec.selector(Self.key), arguments: arguments))
    }

    // MARK: - Private
}
