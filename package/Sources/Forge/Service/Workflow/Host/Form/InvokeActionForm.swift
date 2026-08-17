//
//  InvokeActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct InvokeActionForm: WarpIR.ConstructForm {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case body
        case model
        case allowed
        case cwd
        case result
        case envExtra = "env_extra"
        case permissionMode = "permission_mode"
        case shareSession = "share_session"
        case timeout
    }

    // MARK: - Property
    static let key = "invoke"

    private let arguments: [String: Warp.Expression]
    private let block: Warp.BlockDeclaration

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        try KeyGate().rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "invoke"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.block = Warp.BlockDeclaration(
            label: "steps",
            block: Warp.Block(
                body: try container.decode([StatementReader].self, forKey: .body)
                    .map(\.statement),
                result: try container.decodeIfPresent(
                    ExpressionReader.self,
                    forKey: .result
                )?
                .expression
            )
        )

        var arguments: [String: Warp.Expression] = [:]

        arguments["model"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .model
        )?
        .expression
        arguments["allowed"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .allowed
        )?
        .expression
        arguments["cwd"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .cwd
        )?
        .expression
        arguments["permission_mode"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .permissionMode
        )?
        .expression
        arguments["share_session"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .shareSession
        )?
        .expression
        arguments["env_extra"] = try container.decodeIfPresent(
            [String: ExpressionReader].self,
            forKey: .envExtra
        )
        .map { env in Warp.Expression.record(env.mapValues(\.expression)) }
        arguments["timeout"] = try container.decodeIfPresent(Double.self, forKey: .timeout)
            .map { timeout in Warp.Expression.literal(.double(timeout)) }

        self.arguments = arguments
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        .dispatch(
            Dispatch(selector: ForgeSpec.selector(Self.key), arguments: arguments, blocks: [block])
        )
    }

    // MARK: - Private
}
