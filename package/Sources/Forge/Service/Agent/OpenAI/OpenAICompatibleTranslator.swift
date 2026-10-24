//
//  OpenAICompatibleTranslator.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct OpenAICompatibleTranslator: AgentTranslator {
    // MARK: - Property
    private static let commandTool = ToolSpec(
        name: "run_command",
        description: "Run one executable directly. The argv must match the agent capability.",
        parametersJSON: #"{"type":"object","properties":{"argv":{"type":"array","items":{"type":"string"},"minItems":1,"description":"Executable followed by its arguments"}},"required":["argv"]}"#
    )

    // MARK: - Initializer
    // MARK: - Public
    func translate(_ agent: Agent) throws -> AgentTranslation<OpenAICompatibleAgentConfiguration> {
        guard let model = agent.model.specifiedModel else {
            throw ProtocolError(
                "openai-compatible provider '\(agent.provider)' requires an explicit model"
            )
        }

        let allowedTools: [AgentTool]?

        if agent.permissionMode == .bypass {
            guard agent.allowed == nil else {
                throw ProtocolError(
                    "openai-compatible loop: 'allowed' is the execution boundary here, so"
                        + " declaring it together with bypass is contradictory (drop 'allowed'"
                        + " or drop bypass)"
                )
            }

            allowedTools = nil
        } else if agent.permissionMode == .restrict {
            allowedTools = []
        } else {
            allowedTools = agent.allowed ?? []
        }

        let commandAuthorization = CommandAuthorizationPolicy(
            allowed: allowedTools.map { tools in tools.compactMap(Self.commandPattern) }
        )

        var diagnostics: [AgentTranslationDiagnostic] = []

        if agent.permissionMode == .restrict {
            diagnostics.append(
                AgentTranslationDiagnostic(
                    field: "permission",
                    message: "openai-compatible loop has no approval channel; restrict was"
                        + " lowered to a tool-less run"
                )
            )
        }

        for tool in (allowedTools ?? []) where Self.commandPattern(tool) == nil {
            diagnostics.append(
                AgentTranslationDiagnostic(
                    field: "tools.allowed",
                    message: "\(tool) is not exposed by the openai-compatible loop and was"
                        + " left unavailable"
                )
            )
        }

        return AgentTranslation(
            OpenAICompatibleAgentConfiguration(
                model: model,
                workingDirectory: agent.workingDirectory,
                environment: agent.environment.isEmpty ? nil : agent.environment,
                commandAuthorization: commandAuthorization,
                tools: commandAuthorization.isEmpty ? [] : [Self.commandTool]
            ),
            diagnostics: diagnostics
        )
    }

    // MARK: - Private
    private static func commandPattern(_ tool: AgentTool) -> CommandPattern? {
        guard case .command(let pattern) = tool else { return nil }

        return pattern
    }
}
