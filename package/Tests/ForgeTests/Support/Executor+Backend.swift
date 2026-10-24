//
//  Executor+Backend.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

@testable import Forge

extension Executor {
    // An executor with one backend, registered under the provider `claude`.
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
}
