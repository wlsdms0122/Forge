//
//  Server.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

package actor Server {
    // MARK: - Property
    let config: ForgeConfig
    let bootedAt: Date
    let catalog: WorkflowCatalog
    let scheduleStore: ScheduleStore
    let fireLedger: FireLedger
    let runtimeScheduleDirectory: URL
    let jobStore: JobStore
    let jobDirectory: URL
    let policyStore: PolicyStore
    let workflowEventBus: WorkflowEventBus
    let workflowLogger: WorkflowLogger
    let workflowPool: WorkflowPool
    let workflowRunner: WorkflowRunner
    let workflowScheduler: WorkflowScheduler
    let serviceBus: ServiceBus
    let workRegistry: WorkRegistry
    let serviceSupervisor: ServiceSupervisor
    let tokenAuthority: TokenAuthority
    let instanceHome: URL
    let socketPath: String
    let instance: String
    
    private let configSnapshot: ConfigSnapshot
    private let socketServer: UnixSocketServer
    private let acceptLoop: AcceptLoop
    private var stopped = false
    
    // MARK: - Initializer
    init(
        config: ForgeConfig,
        configReport: ConfigReport,
        instanceHome: URL,
        instance: String,
        configPath: String? = nil,
        vocabulary: ForgeVocabulary
    ) {
        self.config = config
        self.configSnapshot = ConfigSnapshot(configReport)
        self.instanceHome = instanceHome
        self.socketPath = Instance.socket(in: instanceHome)
        self.instance = instance
        self.bootedAt = Date()
        
        var byProvider: [String: any Backend] = [:]
        
        for provider in config.providers {
            byProvider[provider.name] = BackendFactory.make(provider.backend)
        }
        
        let backends = BackendRegistry(byProvider)
        let jobDirectoryLocal = config.runtimeDirectory.appendingPathComponent("jobs")
        let jobStoreLocal = JobStore(directory: jobDirectoryLocal)
        
        var preHooks: [any PreHook] = []
        var postHooks: [any PostHook] = []
        var errorHooks: [any ErrorHook] = []
        
        let logging = LoggingHook()
        
        if config.hooks.logging { preHooks.append(logging) }
        if config.hooks.logging { postHooks.append(logging) }
        if config.hooks.logging { errorHooks.append(logging) }
        
        let executor = AgentExecutor(
            backends: backends,
            preHooks: preHooks,
            postHooks: postHooks,
            errorHooks: errorHooks
        )
        let catalogLocal = WorkflowCatalog(
            directory: config.workflowDirectory,
            builder: WorkflowBuilder(vocabulary: vocabulary)
        )
        let runtimeScheduleDirectory = config.runtimeDirectory.appendingPathComponent("schedule")
        let scheduleStore = ScheduleStore(
            configDir: config.scheduleDirectory,
            runtimeDirectory: runtimeScheduleDirectory,
            stateFile: config.runtimeDirectory.appendingPathComponent("schedule-enabled.json")
        )
        let fireLedger = FireLedger(
            path: config.runtimeDirectory.appendingPathComponent("fire-ledger.json")
        )
        let resourceStore = ResourceStore(directory: config.resourceDirectory)
        let policyStoreLocal = PolicyStore(directory: config.policyDirectory)
        let bus = WorkflowEventBus()
        let serviceBus = ServiceBus()
        let workRegistryLocal = WorkRegistry()
        let tokenAuthorityLocal = TokenAuthority()
        self.tokenAuthority = tokenAuthorityLocal
        
        let workflowLoggerLocal = WorkflowLogger(bus: bus)
        let pool = WorkflowPool(
            maximumConcurrentSteps: config.pool.maximumConcurrentSteps,
            maximumActiveRuns: config.pool.maximumActiveRuns
        )
        let runnerLocal = WorkflowRunner(
            catalog: catalogLocal,
            eventBus: bus,
            policyStore: policyStoreLocal,
            pool: pool,
            workRegistry: workRegistryLocal,
            tokenAuthority: tokenAuthorityLocal,
            jobStore: jobStoreLocal,
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: executor),
                resources: LiveResources(store: resourceStore)
            )
        )
        let scheduler = WorkflowScheduler(
            catalog: catalogLocal,
            store: scheduleStore,
            ledger: fireLedger,
            runner: runnerLocal
        )
        
        self.catalog = catalogLocal
        self.scheduleStore = scheduleStore
        self.fireLedger = fireLedger
        self.runtimeScheduleDirectory = runtimeScheduleDirectory
        self.jobStore = jobStoreLocal
        self.jobDirectory = jobDirectoryLocal
        self.policyStore = policyStoreLocal
        self.workflowEventBus = bus
        self.workflowLogger = workflowLoggerLocal
        self.workflowPool = pool
        self.workflowRunner = runnerLocal
        self.workflowScheduler = scheduler
        self.serviceBus = serviceBus
        self.workRegistry = workRegistryLocal
        
        let supervisorLocal = ServiceSupervisor(
            services: config.services,
            runtimeDirectory: config.runtimeDirectory,
            tokenAuthority: tokenAuthorityLocal
        )
        self.serviceSupervisor = supervisorLocal
        
        let daemonStatusMethod = DaemonStatusMethod(
            instance: instance,
            socketPath: socketPath,
            runtimeDirectory: config.runtimeDirectory,
            bootedAt: self.bootedAt,
            configSnapshot: configSnapshot,
            catalog: catalogLocal,
            scheduleStore: scheduleStore,
            jobStore: jobStoreLocal,
            supervisor: supervisorLocal,
            serviceBus: serviceBus
        )
        let workflow = WorkflowNamespace(
            runner: runnerLocal,
            catalog: catalogLocal,
            workRegistry: workRegistryLocal,
            pool: pool,
            policyStore: policyStoreLocal,
            eventBus: bus
        )
        let schedule = ScheduleNamespace(
            store: scheduleStore,
            ledger: fireLedger,
            catalog: catalogLocal,
            policyStore: policyStoreLocal
        )
        let job = JobNamespace(store: jobStoreLocal, workRegistry: workRegistryLocal)
        let resource = ResourceNamespace(store: resourceStore)
        let policy = PolicyNamespace(store: policyStoreLocal)
        let token = TokenNamespace(authority: tokenAuthorityLocal)
        let daemon = DaemonNamespace(status: daemonStatusMethod)
        let service = ServiceNamespace(
            supervisor: supervisorLocal,
            serviceBus: serviceBus,
            workRegistry: workRegistryLocal,
            configPath: configPath,
            instanceHome: instanceHome,
            configSnapshot: configSnapshot
        )
        let router = RPCRouter(
            methods: workflow.methods
                + schedule.methods
                + job.methods
                + resource.methods
                + policy.methods
                + token.methods
                + daemon.methods
                + service.methods,
            authority: tokenAuthorityLocal
        )
        
        self.socketServer = UnixSocketServer(path: socketPath)
        self.acceptLoop = AcceptLoop(server: socketServer, router: router)
    }
    
    // MARK: - Public
    func boot() async throws {
        try Instance.checkSocketLength(socketPath)
        
        if UnixSocketServer.isLive(path: socketPath) {
            throw SocketError("daemon already listening at \(socketPath) — "
                + "stop it, or use a different --instance")
        }
        
        setenv("FORGE_SOCKET", socketPath, 1)
        setenv("FORGE_RUNTIME", config.runtimeDirectory.path, 1)
        
        await Log.shared.setSink(config.logJSONL)
        await Log.shared.setErrorSink(config.errorLog)
        await Log.shared.setMaxBytes(config.logMaximumBytes)
        await catalog.reload()
        await scheduleStore.ensureRuntimeDirectory()
        await scheduleStore.reload()
        await jobStore.reload()
        await jobStore.closeOrphans()
        await policyStore.reload()
        await workflowLogger.start()
        await workflowScheduler.start()
        
        try await acceptLoop.start()
        
        emitBootstrapToken()
        
        await serviceSupervisor.boot()
        
        writeRuntimeInfo()
        
        await Log.shared.append(
            "runtime.boot",
            [
                "runtime_directory":          config.runtimeDirectory.path,
                "socket":                     socketPath,
                "workflow_directory":         config.workflowDirectory?.path ?? "",
                "schedule_directory":         config.scheduleDirectory?.path ?? "",
                "runtime_schedule_directory": runtimeScheduleDirectory.path,
                "job_directory":              jobDirectory.path,
                "policy_directory":           config.policyDirectory?.path ?? ""
            ],
            level: .default,
            category: "runtime"
        )
    }
    
    func stop() async {
        guard !stopped else { return }
        
        stopped = true
        
        await Log.shared.append(
            "runtime.stop",
            [:],
            level: .default,
            category: "runtime"
        )
        await workflowPool.beginShutdown()
        await serviceSupervisor.stopAll()
        await workflowScheduler.stop()
        
        let leftover = await workflowPool.drain()
        
        if !leftover.isEmpty {
            FileHandle.standardError.write(Data(
                "forge: shutdown drain grace expired with \(leftover.count) run(s) still live: \(leftover.map(\.runID).joined(separator: ", "))\n".utf8))
        }
        
        await workflowLogger.stop()
        await acceptLoop.stop()
        
        deleteRuntimeInfo()
    }
    
    nonisolated static func bootstrapSink(fdEnv: String?, isTTY: Bool) -> BootstrapSink {
        if let fdEnv, let fd = Int32(fdEnv), fd >= 0 { return .fd(fd) }
        
        return isTTY ? .stdout : .withheld
    }
    
    package static func run(configPath: String?, instance: String?) async throws {
        let absoluteConfigPath = configPath
            .map { path in URL(fileURLWithPath: path).standardizedFileURL.path }
        let home = try Instance.home(instance: instance)
        let (configuration, report) = try ConfigLoader.loadResolved(
            configPath: absoluteConfigPath,
            instanceHome: home
        )
        let server = Server(
            config: configuration,
            configReport: report,
            instanceHome: home,
            instance: Instance.name(instance),
            configPath: absoluteConfigPath,
            vocabulary: try ForgeVocabulary()
        )
        
        try await server.boot()
        
        let stopSignal = AsyncSignalWaiter()
        await stopSignal.wait()
        await server.stop()
    }
    
    // MARK: - Private
    private func emitBootstrapToken() {
        let token = tokenAuthority.mint(TokenClaims(principal: "system:admin"))
        
        switch Self.bootstrapSink(
            fdEnv: ProcessInfo.processInfo.environment["FORGE_BOOTSTRAP_FD"],
            isTTY: isatty(1) != 0
        ) {
        case .fd(let fd):
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            try? handle.write(contentsOf: Data((token + "\n").utf8))
            try? handle.close()
            unsetenv("FORGE_BOOTSTRAP_FD")
        
        case .stdout:
            FileHandle.standardOutput.write(Data("forge: bootstrap-token \(token)\n".utf8))
        
        case .withheld:
            FileHandle.standardError.write(Data(
                ("forge: FORGE_BOOTSTRAP_FD unset and stdout is not a tty — bootstrap token withheld " +
                "(set FORGE_BOOTSTRAP_FD to receive it)\n").utf8))
        }
    }
    
    private func runtimeInfoURL() -> URL {
        Instance.runtimeInfo(in: instanceHome)
    }
    
    private func writeRuntimeInfo() {
        let info: [String: Any] = [
            "socket":                     socketPath,
            "instance":                   instance,
            "version":                    Version.current,
            "pid":                        ProcessInfo.processInfo.processIdentifier,
            "started_at":                 ISO8601DateFormatter().string(from: bootedAt),
            "log_jsonl":                  config.logJSONL.path,
            "error_log":                  config.errorLog.path,
            "workflow_directory":         config.workflowDirectory?.path ?? "",
            "schedule_directory":         config.scheduleDirectory?.path ?? "",
            "runtime_schedule_directory": runtimeScheduleDirectory.path,
            "job_directory":              jobDirectory.path
        ]
        let url = runtimeInfoURL()
        
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        if let data = try? JSONSerialization.data(
            withJSONObject: info,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        ) {
            try? data.write(to: url)
        }
    }
    
    private func deleteRuntimeInfo() {
        try? FileManager.default.removeItem(at: runtimeInfoURL())
    }
}
