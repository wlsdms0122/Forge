//
//  ShellActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct ShellActionForm: WarpIR.ConstructForm {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case cwd
        case env
        case stdin
        case outputs
        case timeout
    }

    // MARK: - Property
    static let key = "shell"

    private let arguments: [String: Warp.Expression]

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        try KeyGate().rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "shell"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let command = try container.decode([ExpressionReader].self, forKey: .command)
            .map(\.expression)

        guard !command.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "shell.command is empty"
                )
            )
        }

        var arguments: [String: Warp.Expression] = [:]

        arguments["command"] = .array(command)
        arguments["cwd"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .cwd
        )?
        .expression
        arguments["stdin"] = try container.decodeIfPresent(
            ExpressionReader.self,
            forKey: .stdin
        )?
        .expression
        arguments["env"] = try container.decodeIfPresent(
            [String: ExpressionReader].self,
            forKey: .env
        )
        .map { env in Warp.Expression.record(env.mapValues(\.expression)) }
        arguments["timeout"] = try container.decodeIfPresent(Double.self, forKey: .timeout)
            .map { timeout in Warp.Expression.literal(.double(timeout)) }

        // Output declarations are read here so a malformed one is refused at
        // load, and carried as data so the word takes arguments and nothing
        // else. The notation checks the spelling; the IR holds the value.
        if let outputs = try container.decodeIfPresent(
            [String: OutputSpec].self,
            forKey: .outputs
        ) {
            arguments["outputs"] = .literal(try ValueBridge.value(outputs))
        }

        self.arguments = arguments
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        .dispatch(Dispatch(selector: ForgeSpec.selector(Self.key), arguments: arguments))
    }

    // MARK: - Private
}
