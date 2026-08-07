//
//  LoggingHook.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct LoggingHook: PreHook, PostHook, ErrorHook {
    // MARK: - Property
    private static let category = "hook.logging"
    private static let userPreviewLimit = 2000
    
    let name = "logging"
    
    private let log: Log
    
    // MARK: - Initializer
    init(log: Log = .shared) {
        self.log = log
    }
    
    // MARK: - Public
    func before(_ invocation: Invocation) async throws -> Invocation {
        let model = invocation.agent.model
        var payload: [String: Any] = [
            "id": invocation.id,
            "model": model.displayName,
            "model_resolution": Self.modelResolution(model),
            "user_len": invocation.prompt.count,
            "user_preview": String(invocation.prompt.prefix(Self.userPreviewLimit)),
            "cwd": invocation.agent.workingDirectory as Any? ?? NSNull()
        ]
        
        for (key, value) in Self.forgeContext() { payload[key] = value }
        
        await log.append(
            "agent.request",
            LogPayload(payload),
            category: Self.category
        )
        
        return invocation
    }
    
    func after(_ invocation: Invocation, _ response: BackendResponse) async {
        let model = response.modelReference
            ?? invocation.executionContext.modelReference
            ?? invocation.agent.model
        let forge = Self.forgeContext()
        
        var responsePayload: [String: Any] = [
            "id": invocation.id,
            "model": model.displayName,
            "model_resolution": Self.modelResolution(model),
            "duration_ms": response.durationMs,
            "stdout_len": response.stdoutLength,
            "stdout_preview": String(response.text.prefix(2000)),
            "tool_calls": response.toolEvents.count,
            "usage": response.usage?.asDictionary as Any? ?? NSNull()
        ]
        
        for (key, value) in forge { responsePayload[key] = value }
        
        await log.append(
            "agent.response",
            LogPayload(responsePayload),
            level: .default,
            category: Self.category
        )
    }
    
    func onError(_ invocation: Invocation, _ error: any Error) async -> ErrorAction {
        let model = invocation.executionContext.modelReference ?? invocation.agent.model
        let resolvedModel = model.displayName
        let stage: String
        
        switch error {
        case is BackendTimeout:
            stage = "timeout"
        
        case is CancellationError:
            stage = "cancelled"
        
        case let nonzeroExit as BackendNonzeroExit:
            stage = "nonzero_exit"
            
            await log.appendError(
                "agent.nonzero_exit",
                "model=\(resolvedModel) exit=\(nonzeroExit.exitCode)"
                    + "\nSTDERR:\n\(nonzeroExit.stderr)\nSTDOUT:\n\(nonzeroExit.stdout)",
                category: Self.category
            )
        
        default:
            stage = "other"
        }
        
        var payload: [String: Any] = [
            "id": invocation.id,
            "model": resolvedModel,
            "model_resolution": Self.modelResolution(model),
            "stage": stage,
            "error_type": String(describing: type(of: error))
        ]
        
        if let forgeError = error as? ForgeError { payload["message"] = forgeError.message }
        
        for (key, value) in Self.forgeContext() { payload[key] = value }
        
        var errorObject: [String: Any] = [
            "type": String(describing: type(of: error)),
            "stage": stage
        ]
        
        if let forgeError = error as? ForgeError { errorObject["message"] = forgeError.message }
        
        if let nonzeroExit = error as? BackendNonzeroExit {
            payload["exit_code"] = Int(nonzeroExit.exitCode)
            
            let stderrPreview = String(
                nonzeroExit.stderr
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(300)
            )
            payload["stderr_preview"] = stderrPreview
            errorObject["exit_code"] = Int(nonzeroExit.exitCode)
            errorObject["stderr_preview"] = stderrPreview
            
            if stderrPreview.isEmpty {
                let tail = Diagnostics.stdoutTail(nonzeroExit.stdout)
                
                if !tail.isEmpty {
                    payload["stdout_tail"] = tail
                    errorObject["stdout_tail"] = tail
                }
            }
        }
        
        await log.append(
            "agent.error",
            LogPayload(payload),
            level: .error,
            category: Self.category,
            error: errorObject
        )
        
        if error is BackendTimeout {
            await log.appendError(
                "agent.timeout",
                "model=\(resolvedModel)",
                category: Self.category
            )
        }
        
        return .abort
    }
    
    // MARK: - Private
    private static func forgeContext() -> [String: Any] {
        LogContext.workflowContext?.asPayload ?? [:]
    }
    
    private static func modelResolution(_ model: ModelReference) -> String {
        model.isBackendDefault ? "backend_default" : "specific"
    }
}
