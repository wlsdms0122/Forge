//
//  ForgeConfig.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct ForgeConfig: Sendable {
    struct HookToggles: Sendable {
        // MARK: - Property
        let logging: Bool
        
        // MARK: - Initializer
        init(logging: Bool = true) {
            self.logging = logging
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    struct PoolConfig: Sendable {
        // MARK: - Property
        let maximumConcurrentSteps: Int
        let maximumActiveRuns: Int
        
        // MARK: - Initializer
        init(maximumConcurrentSteps: Int = 4, maximumActiveRuns: Int = 256) {
            self.maximumConcurrentSteps = maximumConcurrentSteps
            self.maximumActiveRuns = maximumActiveRuns
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let stateDirectory: URL
    let logJSONL: URL
    let errorLog: URL
    let logMaximumBytes: Int
    let providers: [ProviderConfig]
    let rootDirectory: URL?
    let policyDirectory: URL?
    let services: [ServiceConfig]
    let hooks: HookToggles
    let pool: PoolConfig
    
    // MARK: - Initializer
    init(
        stateDirectory: URL,
        logJSONL: URL,
        errorLog: URL,
        logMaximumBytes: Int = 50 * 1024 * 1024,
        providers: [ProviderConfig] = [],
        rootDirectory: URL? = nil,
        policyDirectory: URL? = nil,
        services: [ServiceConfig] = [],
        hooks: HookToggles = HookToggles(),
        pool: PoolConfig = PoolConfig()
    ) {
        self.stateDirectory = stateDirectory
        self.logJSONL = logJSONL
        self.errorLog = errorLog
        self.logMaximumBytes = logMaximumBytes
        self.providers = providers
        self.rootDirectory = rootDirectory
        self.policyDirectory = policyDirectory
        self.services = services
        self.hooks = hooks
        self.pool = pool
    }
    
    // MARK: - Public
    // MARK: - Private
}

extension ForgeConfig {
    static func cwdDefault() -> ForgeConfig {
        let cwd = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        
        return ForgeConfig(
            stateDirectory: cwd,
            logJSONL: cwd.appendingPathComponent("forge.log.jsonl"),
            errorLog: cwd.appendingPathComponent("error.log"),
            providers: [
                ProviderConfig(name: "claude", backend: .claudeCLI(executable: "claude"))
            ]
        )
    }
}
