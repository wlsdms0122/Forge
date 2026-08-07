//
//  Executor.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct Executor: Sendable {
    // MARK: - Property
    let backends: BackendRegistry
    let preHooks: [any PreHook]
    let postHooks: [any PostHook]
    let errorHooks: [any ErrorHook]
    
    // MARK: - Initializer
    init(
        backends: BackendRegistry,
        preHooks: [any PreHook] = [],
        postHooks: [any PostHook] = [],
        errorHooks: [any ErrorHook] = []
    ) {
        self.backends = backends
        self.preHooks = preHooks
        self.postHooks = postHooks
        self.errorHooks = errorHooks
    }
    
    init(
        backend: any Backend,
        preHooks: [any PreHook] = [],
        postHooks: [any PostHook] = [],
        errorHooks: [any ErrorHook] = []
    ) {
        self.init(
            backends: BackendRegistry(["claude": backend]),
            preHooks: preHooks,
            postHooks: postHooks,
            errorHooks: errorHooks
        )
    }
    
    // MARK: - Public
    func openSession(provider: String?) throws -> any BackendSession {
        let backend = try backends.resolve(provider: provider)
        
        return backend.openSession()
    }
    
    func run(_ original: Invocation) async throws -> InvocationResult {
        let started = ContinuousClock.now
        var invocation = original
        
        do {
            for hook in preHooks {
                invocation = try await hook.before(invocation)
            }
            
            let backend = try backends.resolve(provider: invocation.agent.provider)
            let response = try await backend.invoke(invocation)
            
            for hook in postHooks {
                await hook.after(invocation, response)
            }
            
            let durationMs = (ContinuousClock.now - started).milliseconds
            
            return InvocationResult(
                text: response.text,
                usage: response.usage,
                toolEvents: response.toolEvents,
                durationMs: durationMs
            )
        } catch {
            for hook in errorHooks {
                let action = await hook.onError(invocation, error)
                
                switch action {
                case .abort:
                    continue
                
                case .substitute(let response):
                    for postHook in postHooks {
                        await postHook.after(invocation, response)
                    }
                    
                    let durationMs = (ContinuousClock.now - started).milliseconds
                    
                    return InvocationResult(
                        text: response.text,
                        usage: response.usage,
                        toolEvents: response.toolEvents,
                        durationMs: durationMs
                    )
                }
            }
            
            throw error
        }
    }
    
    // MARK: - Private
}
