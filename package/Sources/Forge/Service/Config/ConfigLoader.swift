//
//  ConfigLoader.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import TOMLKit

enum ConfigLoader {
    struct PartialConfig {
        // MARK: - Property
        var providers: [ProviderConfig]?
        var services: [PartialService]?
        var workflowDirectory: String?
        var scheduleDirectory: String?
        var resourceDirectory: String?
        var policyDirectory: String?
        var logJSONL: String?
        var errorLog: String?
        var logMaximumBytes: Int?
        var hooks: PartialHooks = PartialHooks()
        var pool: PartialPool = PartialPool()
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct PartialHooks {
        // MARK: - Property
        var logging: Bool?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct PartialService {
        // MARK: - Property
        var name: String
        var command: [String] = []
        var workingDirectory: String?
        var environment: [String: String] = [:]
        var autoSpawn: Bool?
        var logFile: String?
        var backoffInitialMilliseconds: Int?
        var backoffMaximumMilliseconds: Int?
        var crashLoopLimit: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct PartialPool {
        // MARK: - Property
        var maximumConcurrentSteps: Int?
        var maximumActiveRuns: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func resolveConfigPath(_ explicit: String?, sessionHome: URL) -> URL? {
        if let explicit {
            let url = URL(fileURLWithPath: explicit)
            
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        
        let candidate = sessionHome.appendingPathComponent("config.toml")
        
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
    
    static func load(configPath: String? = nil, sessionHome: URL) throws -> ForgeConfig {
        let environment = ProcessInfo.processInfo.environment
        let tomlURL = resolveConfigPath(configPath, sessionHome: sessionHome)
        let fromFile = try tomlURL.map { url in try parse(url) } ?? PartialConfig()
        
        return build(
            file: fromFile,
            tomlDirectory: tomlURL?.deletingLastPathComponent(),
            sessionHome: sessionHome,
            environment: environment
        )
    }
    
    static func loadWithSources(
        configPath: String? = nil,
        sessionHome: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ConfigReport {
        try loadResolved(configPath: configPath, sessionHome: sessionHome, environment: environment).report
    }
    
    static func loadResolved(
        configPath: String? = nil,
        sessionHome: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (config: ForgeConfig, report: ConfigReport) {
        let tomlURL = resolveConfigPath(configPath, sessionHome: sessionHome)
        let fromFile = try tomlURL.map { url in try parse(url) } ?? PartialConfig()
        let config = build(
            file: fromFile,
            tomlDirectory: tomlURL?.deletingLastPathComponent(),
            sessionHome: sessionHome,
            environment: environment
        )
        
        func source(toml: String?, environmentName: String) -> ConfigSource {
            channelSource(toml: toml, environment: environment, environmentName: environmentName)
        }
        
        var entries: [ConfigReport.Entry] = []
        
        entries.append(
            .init(
                key: "workflow_directory",
                value: config.workflowDirectory?.path ?? "(unset)",
                source: source(toml: fromFile.workflowDirectory, environmentName: "FORGE_WORKFLOW_DIRECTORY")
            )
        )
        entries.append(
            .init(
                key: "schedule_directory",
                value: config.scheduleDirectory?.path ?? "(unset)",
                source: source(toml: fromFile.scheduleDirectory, environmentName: "FORGE_SCHEDULE_DIRECTORY")
            )
        )
        entries.append(
            .init(
                key: "resource_directory",
                value: config.resourceDirectory?.path ?? "(unset)",
                source: source(toml: fromFile.resourceDirectory, environmentName: "FORGE_RESOURCE_DIRECTORY")
            )
        )
        entries.append(
            .init(
                key: "policy_directory",
                value: config.policyDirectory?.path ?? "(unset)",
                source: source(toml: fromFile.policyDirectory, environmentName: "FORGE_POLICY_DIRECTORY")
            )
        )
        entries.append(
            .init(
                key: "log_jsonl",
                value: config.logJSONL.path,
                source: source(toml: fromFile.logJSONL, environmentName: "FORGE_LOG_JSONL")
            )
        )
        entries.append(
            .init(
                key: "error_log",
                value: config.errorLog.path,
                source: source(toml: fromFile.errorLog, environmentName: "FORGE_ERROR_LOG")
            )
        )
        
        let logMaxSource = resolveInt(
            toml: fromFile.logMaximumBytes,
            environmentName: "FORGE_LOG_MAXIMUM_BYTES",
            environment: environment,
            valid: { _ in true },
            builtin: 50 * 1024 * 1024
        ).source
        
        entries.append(
            .init(
                key: "log_maximum_bytes",
                value: String(config.logMaximumBytes),
                source: logMaxSource
            )
        )
        
        let providersSource: ConfigSource = (fromFile.providers?.isEmpty == false)
            ? .toml
            : .builtin
        
        for provider in config.providers {
            let description = provider.settings
                .filter { key, _ in key != "api_key" }
                .sorted { left, right in left.key < right.key }
                .map { key, value in "\(key)=\(value)" }
                .joined(separator: " ")
            let keyState = provider.settings["api_key"] == nil ? "" : "  api_key=(set)"
            
            entries.append(
                .init(
                    key: "provider.\(provider.name)",
                    value: "kind=\(provider.kind)  \(description)\(keyState)",
                    source: providersSource
                )
            )
        }
        
        let servicesSource: ConfigSource = (fromFile.services?.isEmpty == false) ? .toml : .none
        
        for service in config.services {
            let command = service.command.joined(separator: " ")
            let workingDirectoryDescription = service.workingDirectory.map { workingDirectory in "  working_directory=\(workingDirectory.path)" } ?? ""
            
            entries.append(
                .init(
                    key: "service.\(service.name)",
                    value: "command=\(command)\(workingDirectoryDescription)"
                        + "  auto_spawn=\(service.autoSpawn)",
                    source: servicesSource
                )
            )
        }
        
        entries.append(
            .init(
                key: "hooks.logging",
                value: String(config.hooks.logging),
                source: fromFile.hooks.logging != nil ? .toml : .builtin
            )
        )
        
        let poolSource = resolveInt(
            toml: fromFile.pool.maximumConcurrentSteps,
            environmentName: "FORGE_POOL_MAXIMUM_CONCURRENT_STEPS",
            environment: environment,
            valid: { value in value > 0 },
            builtin: ForgeConfig.PoolConfig().maximumConcurrentSteps
        ).source
        
        entries.append(
            .init(
                key: "pool.maximum_concurrent_steps",
                value: String(config.pool.maximumConcurrentSteps),
                source: poolSource
            )
        )
        
        let runCapSource = resolveInt(
            toml: fromFile.pool.maximumActiveRuns,
            environmentName: "FORGE_POOL_MAXIMUM_ACTIVE_RUNS",
            environment: environment,
            valid: { value in value > 0 },
            builtin: ForgeConfig.PoolConfig().maximumActiveRuns
        ).source
        
        entries.append(
            .init(
                key: "pool.maximum_active_runs",
                value: String(config.pool.maximumActiveRuns),
                source: runCapSource
            )
        )
        
        return (config, ConfigReport(tomlPath: tomlURL?.path, entries: entries))
    }
    
    static func parse(_ url: URL) throws -> PartialConfig {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let table = try TOMLTable(string: raw)
        var partial = PartialConfig()
        
        if let directory = table["directory"]?.table {
            if let value = directory["workflow"]?.string { partial.workflowDirectory = value }
            if let value = directory["schedule"]?.string { partial.scheduleDirectory = value }
            if let value = directory["resource"]?.string { partial.resourceDirectory = value }
            if let value = directory["policy"]?.string { partial.policyDirectory = value }
        }
        
        if let log = table["log"]?.table {
            if let value = log["jsonl"]?.string { partial.logJSONL = value }
            if let value = log["error"]?.string { partial.errorLog = value }
            if let value = log["maximum_bytes"]?.int { partial.logMaximumBytes = value }
        }
        
        if let hooks = table["hooks"]?.table {
            if let value = hooks["logging"]?.bool { partial.hooks.logging = value }
        }
        
        if let pool = table["pool"]?.table {
            if let value = pool["maximum_concurrent_steps"]?.int {
                partial.pool.maximumConcurrentSteps = value
            }
            
            if let value = pool["maximum_active_runs"]?.int { partial.pool.maximumActiveRuns = value }
        }
        
        if let providers = table["provider"]?.table {
            var list: [ProviderConfig] = []
            
            for name in providers.keys {
                guard let block = providers[name]?.table else { continue }
                
                var kind = ""
                var settings: [String: String] = [:]
                
                for key in block.keys {
                    guard let value = block[key]?.string else { continue }
                    
                    if key == "kind" { kind = value } else { settings[key] = value }
                }
                
                list.append(ProviderConfig(name: name, kind: kind, settings: settings))
            }
            
            partial.providers = list.sorted { left, right in left.name < right.name }
        }
        
        if let services = table["service"]?.table {
            var list: [PartialService] = []
            
            for name in services.keys {
                guard let block = services[name]?.table else { continue }
                
                var service = PartialService(name: name)
                
                if let array = block["command"]?.array {
                    let strings = array.compactMap { element in element.string }
                    service.command = strings.count == array.count ? strings : []
                }
                
                if let value = block["working_directory"]?.string { service.workingDirectory = value }
                if let value = block["auto_spawn"]?.bool { service.autoSpawn = value }
                if let value = block["log_file"]?.string { service.logFile = value }
                
                if let value = block["restart_backoff_initial_milliseconds"]?.int {
                    service.backoffInitialMilliseconds = value
                }
                
                if let value = block["restart_backoff_maximum_milliseconds"]?.int {
                    service.backoffMaximumMilliseconds = value
                }
                
                if let value = block["restart_crash_loop_limit"]?.int {
                    service.crashLoopLimit = value
                }
                
                if let environmentTable = block["environment"]?.table {
                    for key in environmentTable.keys {
                        if let value = environmentTable[key]?.string { service.environment[key] = value }
                    }
                }
                
                list.append(service)
            }
            
            partial.services = list.sorted { left, right in left.name < right.name }
        }
        
        return partial
    }
    
    static func build(
        file: PartialConfig,
        tomlDirectory: URL?,
        sessionHome: URL,
        environment: [String: String]
    ) -> ForgeConfig {
        let providers = resolveProviders(file.providers, environment: environment)
        let anchor = tomlDirectory ?? sessionHome
        let runtimeDirectory = Session.runtimeDirectory(in: sessionHome)
        let logDir = sessionHome.appendingPathComponent("log")
        let logJSONL = resolveURLWithDefault(
            cli: nil,
            environmentName: "FORGE_LOG_JSONL",
            environment: environment,
            toml: file.logJSONL,
            anchor: anchor,
            fallback: logDir.appendingPathComponent("forge.log.jsonl")
        )
        let errorLog = resolveURLWithDefault(
            cli: nil,
            environmentName: "FORGE_ERROR_LOG",
            environment: environment,
            toml: file.errorLog,
            anchor: anchor,
            fallback: logDir.appendingPathComponent("error.log")
        )
        let logMaximumBytes = resolveInt(
            toml: file.logMaximumBytes,
            environmentName: "FORGE_LOG_MAXIMUM_BYTES",
            environment: environment,
            valid: { _ in true },
            builtin: 50 * 1024 * 1024
        ).value
        
        func catalogDir(_ environmentName: String, _ toml: String?, _ name: String) -> URL {
            resolveURLWithDefault(
                cli: nil,
                environmentName: environmentName,
                environment: environment,
                toml: toml,
                anchor: anchor,
                fallback: sessionHome.appendingPathComponent(name)
            )
        }
        
        let workflowDirectory = catalogDir("FORGE_WORKFLOW_DIRECTORY", file.workflowDirectory, "workflow")
        let scheduleDirectory = catalogDir("FORGE_SCHEDULE_DIRECTORY", file.scheduleDirectory, "schedule")
        let resourceDirectory = catalogDir("FORGE_RESOURCE_DIRECTORY", file.resourceDirectory, "resource")
        let policyDirectory = catalogDir("FORGE_POLICY_DIRECTORY", file.policyDirectory, "policy")
        
        let defaultHooks = ForgeConfig.HookToggles()
        let hooks = ForgeConfig.HookToggles(
            logging: file.hooks.logging ?? defaultHooks.logging
        )
        
        let defaultPool = ForgeConfig.PoolConfig()
        let poolMax = resolveInt(
            toml: file.pool.maximumConcurrentSteps,
            environmentName: "FORGE_POOL_MAXIMUM_CONCURRENT_STEPS",
            environment: environment,
            valid: { value in value > 0 },
            builtin: defaultPool.maximumConcurrentSteps
        ).value
        let runCap = resolveInt(
            toml: file.pool.maximumActiveRuns,
            environmentName: "FORGE_POOL_MAXIMUM_ACTIVE_RUNS",
            environment: environment,
            valid: { value in value > 0 },
            builtin: defaultPool.maximumActiveRuns
        ).value
        let pool = ForgeConfig.PoolConfig(maximumConcurrentSteps: poolMax, maximumActiveRuns: runCap)
        
        let services: [ServiceConfig] = (file.services ?? []).compactMap { service in
            guard !service.command.isEmpty else {
                FileHandle.standardError.write(
                    Data(
                        ("forge: [service.\(service.name)]: 'command' (non-empty string array)"
                            + " required — skipped\n").utf8
                    )
                )
                
                return nil
            }
            
            let defaultRestart = ServiceConfig.RestartPolicy()
            let restart = ServiceConfig.RestartPolicy(
                backoffInitial: service.backoffInitialMilliseconds.map { milliseconds in
                    .milliseconds(milliseconds)
                } ?? defaultRestart.backoffInitial,
                backoffMax: service.backoffMaximumMilliseconds.map { milliseconds in
                    .milliseconds(milliseconds)
                } ?? defaultRestart.backoffMax,
                crashLoopLimit: service.crashLoopLimit ?? defaultRestart.crashLoopLimit
            )
            
            var command = service.command
            
            if command[0].contains("/"), !command[0].hasPrefix("/") {
                command[0] = resolveURL(command[0], anchor: anchor).path
            }
            
            return ServiceConfig(
                name: service.name,
                command: command,
                workingDirectory: service.workingDirectory.map { workingDirectory in resolveURL(workingDirectory, anchor: anchor) },
                environment: service.environment,
                autoSpawn: service.autoSpawn ?? true,
                logFile: service.logFile.map { logFile in resolveURL(logFile, anchor: anchor) },
                restart: restart
            )
        }
        
        return ForgeConfig(
            runtimeDirectory: runtimeDirectory,
            logJSONL: logJSONL,
            errorLog: errorLog,
            logMaximumBytes: logMaximumBytes,
            providers: providers,
            workflowDirectory: workflowDirectory,
            scheduleDirectory: scheduleDirectory,
            resourceDirectory: resourceDirectory,
            policyDirectory: policyDirectory,
            services: services,
            hooks: hooks,
            pool: pool
        )
    }
    
    // MARK: - Private
    private static func resolveProviders(
        _ fromToml: [ProviderConfig]?,
        environment: [String: String]
    ) -> [ProviderConfig] {
        let base = fromToml ?? [
            ProviderConfig(name: "claude", kind: "claude-cli", settings: ["executable": "claude"])
        ]
        
        return base.map { provider in
            let envVar = "FORGE_PROVIDER_\(provider.name.uppercased())_API_KEY"
            
            guard let key = environment[envVar], !key.isEmpty else { return provider }
            
            var settings = provider.settings
            settings["api_key"] = key
            
            return ProviderConfig(
                name: provider.name,
                kind: provider.kind,
                settings: settings
            )
        }
    }
    
    private static func resolveInt(
        toml: Int?,
        environmentName: String,
        environment: [String: String],
        valid: (Int) -> Bool,
        builtin: Int
    ) -> (value: Int, source: ConfigSource) {
        if let toml, valid(toml) { return (toml, .toml) }
        
        if let raw = environment[environmentName], let value = Int(raw), valid(value) {
            return (value, .environment(environmentName))
        }
        
        return (builtin, .builtin)
    }
    
    private static func channelSource(
        toml: String?,
        environment: [String: String],
        environmentName: String
    ) -> ConfigSource {
        if let toml, !toml.isEmpty { return .toml }
        if let value = environment[environmentName], !value.isEmpty { return .environment(environmentName) }
        
        return .builtin
    }
    
    private static func resolveURLWithDefault(
        cli: String?,
        environmentName: String,
        environment: [String: String],
        toml: String?,
        anchor: URL,
        fallback: URL
    ) -> URL {
        if let cli, !cli.isEmpty { return resolveURL(cli, anchor: anchor) }
        
        switch channelSource(toml: toml, environment: environment, environmentName: environmentName) {
        case .toml:
            return resolveURL(toml!, anchor: anchor)
        
        case .environment:
            return resolveURL(environment[environmentName]!, anchor: anchor)
        
        default:
            return fallback
        }
    }
    
    private static func resolveURL(_ raw: String, anchor: URL) -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        
        return URL(fileURLWithPath: expanded, relativeTo: anchor).standardizedFileURL
    }
}
