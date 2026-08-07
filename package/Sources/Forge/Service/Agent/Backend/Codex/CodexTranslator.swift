//
//  CodexTranslator.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct CodexTranslator: AgentTranslator {
    // MARK: - Property
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    func translate(_ agent: Agent) throws -> AgentTranslation<CodexAgentConfiguration> {
        var diagnostics: [AgentTranslationDiagnostic] = []
        
        let allowedTools: [AgentTool]? = agent.permissionMode == .restrict ? [] : agent.allowed
        
        var permissionArguments: [String] = []
        
        switch agent.permissionMode {
        case nil:
            break
        
        case .safe:
            permissionArguments += ["-c", "sandbox_mode=\"workspace-write\""]
            permissionArguments += ["-c", "approval_policy=\"never\""]
        
        case .restrict:
            permissionArguments += ["-c", "sandbox_mode=\"read-only\""]
            permissionArguments += ["-c", "approval_policy=\"never\""]
            
            diagnostics.append(
                AgentTranslationDiagnostic(
                    field: "permission",
                    message: "codex exec has no interactive approver in Forge; restrict was"
                        + " lowered to a tool-less read-only run"
                )
            )
        
        case .bypass:
            permissionArguments.append("--dangerously-bypass-approvals-and-sandbox")
        }
        
        var configurationArguments: [String] = []
        
        if let allowedTools, !allowedTools.contains(.web) {
            configurationArguments += ["-c", "web_search=\"disabled\""]
        }
        
        if let allowedTools, !allowedTools.contains(.delegate) {
            configurationArguments += ["--disable", "multi_agent"]
        }
        
        let environmentNames = Set(
            ["PATH", "HOME", "TMPDIR", "LANG", "TERM", "FORGE_*"] + agent.environment.keys
        )
        let environmentList = environmentNames
            .sorted()
            .map(Self.tomlString)
            .joined(separator: ",")
        
        configurationArguments += ["-c", "shell_environment_policy.inherit=\"all\""]
        configurationArguments += [
            "-c", "shell_environment_policy.ignore_default_excludes=true"
        ]
        configurationArguments += [
            "-c",
            "shell_environment_policy.include_only=[\(environmentList)]"
        ]
        
        let model = agent.model.specifiedModel
        
        return AgentTranslation(
            CodexAgentConfiguration(
                model: model,
                workingDirectory: agent.workingDirectory,
                environment: agent.environment,
                permissionArguments: permissionArguments,
                configurationArguments: configurationArguments
            ),
            diagnostics: diagnostics
        )
    }
    
    func agentArguments(configuration: CodexAgentConfiguration) -> [String] {
        var arguments: [String] = []
        
        if let model = configuration.model { arguments += ["--model", model] }
        
        arguments += configuration.permissionArguments
        arguments += configuration.configurationArguments
        
        return arguments
    }
    
    // MARK: - Private
    private static func tomlString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
