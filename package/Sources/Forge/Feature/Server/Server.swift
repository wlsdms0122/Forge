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
    let workflowStore: SpecCatalog
    let scheduleStore: ScheduleStore
    let fireLedger: FireLedger
    let runtimeScheduleDirectory: URL
    let jobStore: JobStore
    let jobDirectory: URL
    let policyStore: PolicyStore
    let workflowEventBus: WorkflowEventBus
    let workflowLogger: WorkflowLogger
    let workflowPool: WorkflowPool
    let workflowRunner: SpecWorkflowRunner
    let workflowScheduler: WorkflowScheduler
    let workflowHandlerBus: WorkflowHandlerBus
    let workRegistry: WorkRegistry
    let serviceSupervisor: ServiceSupervisor
    let tokenAuthority: TokenAuthority
    let sessionHome: URL
    let socketPath: String
    let session: String
    
    private let configSnapshot: ConfigSnapshot
    private let socketServer: UnixSocketServer
    private let acceptLoop: AcceptLoop
    private var stopped = false
    
    // MARK: - Initializer
    init(
        config: ForgeConfig,
        configReport: ConfigReport,
        sessionHome: URL,
        session: String,
        configPath: String? = nil
    ) {
        self.config = config
        self.configSnapshot = ConfigSnapshot(configReport)
        self.sessionHome = sessionHome
        self.socketPath = Session.socket(in: sessionHome)
        self.session = session
        self.bootedAt = Date()
        
        var byProvider: [String: any Backend] = [:]
        
        for provider in config.providers {
            if let backend = BackendFactory.make(provider) {
                byProvider[provider.name] = backend
            } else {
                let warning = "forge: provider '\(provider.name)': unknown kind"
                    + " '\(provider.kind)' or missing settings — skipped\n"
                FileHandle.standardError.write(Data(warning.utf8))
            }
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
        
        let executor = Executor(
            backends: backends,
            preHooks: preHooks,
            postHooks: postHooks,
            errorHooks: errorHooks
        )
        let workflowStoreLocal = SpecCatalog(
            directory: config.workflowDirectory,
            loader: ForgeSpec.loader()
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
        let handlerBus = WorkflowHandlerBus()
        let workRegistryLocal = WorkRegistry()
        let tokenAuthorityLocal = TokenAuthority()
        self.tokenAuthority = tokenAuthorityLocal
        
        let workflowLoggerLocal = WorkflowLogger(bus: bus)
        let pool = WorkflowPool(
            maximumConcurrentSteps: config.pool.maximumConcurrentSteps,
            maximumActiveRuns: config.pool.maximumActiveRuns
        )
        let runnerLocal = SpecWorkflowRunner(
            catalog: workflowStoreLocal,
            eventBus: bus,
            policyStore: policyStoreLocal,
            pool: pool,
            workRegistry: workRegistryLocal,
            tokenAuthority: tokenAuthorityLocal,
            jobStore: jobStoreLocal,
            shell: LiveShell(),
            agent: LiveAgent(executor: executor),
            resources: LiveResources(store: resourceStore)
        )
        let scheduler = WorkflowScheduler(
            workflowStore: workflowStoreLocal,
            store: scheduleStore,
            ledger: fireLedger,
            runner: runnerLocal
        )
        
        self.workflowStore = workflowStoreLocal
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
        self.workflowHandlerBus = handlerBus
        self.workRegistry = workRegistryLocal
        
        let workflowDispatchMethod = WorkflowDispatchMethod(
            runner: runnerLocal,
            store: workflowStoreLocal,
            workRegistry: workRegistryLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let workflowDispatchStreamMethod = WorkflowDispatchStreamMethod(
            dispatchMethod: workflowDispatchMethod,
            eventBus: bus
        )
        let workflowListMethod = WorkflowListMethod(
            store: workflowStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let workflowDescribeMethod = WorkflowDescribeMethod(
            store: workflowStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let workflowHealthMethod = WorkflowHealthMethod(
            pool: pool,
            tokenAuthority: tokenAuthorityLocal
        )
        let workflowListActiveMethod = WorkflowListActiveMethod(
            pool: pool,
            tokenAuthority: tokenAuthorityLocal
        )
        let workflowCancelMethod = WorkflowCancelMethod(
            pool: pool,
            policyStore: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let scheduleListMethod = ScheduleListMethod(
            store: scheduleStore,
            ledger: fireLedger,
            tokenAuthority: tokenAuthorityLocal
        )
        let scheduleSetEnabledMethod = ScheduleSetEnabledMethod(
            store: scheduleStore,
            policyStore: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let scheduleCreateMethod = ScheduleCreateMethod(
            store: scheduleStore,
            workflowStore: workflowStoreLocal,
            policyStore: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let scheduleDeleteMethod = ScheduleDeleteMethod(
            store: scheduleStore,
            policyStore: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let jobCreateMethod = JobCreateMethod(
            store: jobStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let jobShowMethod = JobShowMethod(
            store: jobStoreLocal,
            tokenAuthority: tokenAuthorityLocal,
            workRegistry: workRegistryLocal
        )
        let jobListMethod = JobListMethod(
            store: jobStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let jobUpdateMethod = JobUpdateMethod(
            store: jobStoreLocal,
            tokenAuthority: tokenAuthorityLocal,
            workRegistry: workRegistryLocal
        )
        let jobDeleteMethod = JobDeleteMethod(
            store: jobStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let resourceListMethod = ResourceListMethod(
            store: resourceStore,
            tokenAuthority: tokenAuthorityLocal
        )
        let resourceReadMethod = ResourceReadMethod(
            store: resourceStore,
            tokenAuthority: tokenAuthorityLocal
        )
        let policyListMethod = PolicyListMethod(
            store: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let policyCheckMethod = PolicyCheckMethod(
            store: policyStoreLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let sessionSendMethod = SessionSendMethod(
            handlerBus: handlerBus,
            workRegistry: workRegistryLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let sessionHandlerAck = SessionHandlerAckMethod(
            handlerBus: handlerBus,
            tokenAuthority: tokenAuthorityLocal
        )
        let sessionListMethod = SessionListMethod(
            handlerBus: handlerBus,
            tokenAuthority: tokenAuthorityLocal
        )
        let sessionHandlerRegisterMethod = SessionHandlerRegisterMethod(
            handlerBus: handlerBus,
            tokenAuthority: tokenAuthorityLocal
        )
        let supervisorLocal = ServiceSupervisor(
            services: config.services,
            runtimeDirectory: config.runtimeDirectory,
            tokenAuthority: tokenAuthorityLocal
        )
        self.serviceSupervisor = supervisorLocal
        
        let serviceRunMethod = ServiceRunMethod(
            supervisor: supervisorLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let serviceShutdownMethod = ServiceShutdownMethod(
            supervisor: supervisorLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let serviceRestartMethod = ServiceRestartMethod(
            supervisor: supervisorLocal,
            tokenAuthority: tokenAuthorityLocal
        )
        let serviceStatusMethod = ServiceStatusMethod(
            supervisor: supervisorLocal,
            handlerBus: handlerBus,
            tokenAuthority: tokenAuthorityLocal
        )
        let serviceReloadMethod = ServiceReloadMethod(
            supervisor: supervisorLocal,
            tokenAuthority: tokenAuthorityLocal,
            configPath: configPath,
            sessionHome: sessionHome,
            configSnapshot: configSnapshot
        )
        let tokenIssueMethod = TokenIssueMethod(authority: tokenAuthorityLocal)
        let daemonStatusMethod = DaemonStatusMethod(
            session: session,
            socketPath: socketPath,
            runtimeDirectory: config.runtimeDirectory,
            bootedAt: self.bootedAt,
            configSnapshot: configSnapshot,
            workflowStore: workflowStoreLocal,
            scheduleStore: scheduleStore,
            jobStore: jobStoreLocal,
            supervisor: supervisorLocal,
            handlerBus: handlerBus
        )
        
        let handlerMap: [String: DispatchService.Handler] = [
            "workflow.dispatch":      { request in try await workflowDispatchMethod.handle(request) },
            "workflow.list":          { request in try await workflowListMethod.handle(request) },
            "workflow.describe":      { request in try await workflowDescribeMethod.handle(request) },
            "workflow.list_active":   { request in try await workflowListActiveMethod.handle(request) },
            "workflow.health":        { request in try await workflowHealthMethod.handle(request) },
            "workflow.cancel":        { request in try await workflowCancelMethod.handle(request) },
            "schedule.list":          { request in try await scheduleListMethod.handle(request) },
            "schedule.set_enabled":   { request in try await scheduleSetEnabledMethod.handle(request) },
            "schedule.create":        { request in try await scheduleCreateMethod.handle(request) },
            "schedule.delete":        { request in try await scheduleDeleteMethod.handle(request) },
            "job.create":             { request in try await jobCreateMethod.handle(request) },
            "job.show":               { request in try await jobShowMethod.handle(request) },
            "job.list":               { request in try await jobListMethod.handle(request) },
            "job.update":             { request in try await jobUpdateMethod.handle(request) },
            "job.delete":             { request in try await jobDeleteMethod.handle(request) },
            "resource.list":          { request in try await resourceListMethod.handle(request) },
            "resource.read":          { request in try await resourceReadMethod.handle(request) },
            "policy.list":            { request in try await policyListMethod.handle(request) },
            "policy.check":           { request in try await policyCheckMethod.handle(request) },
            "token.issue":            { request in try await tokenIssueMethod.handle(request) },
            "daemon.status":          { request in try await daemonStatusMethod.handle(request) },
            "session.send":           { request in try await sessionSendMethod.handle(request) },
            "session.handler.ack":    { request in try await sessionHandlerAck.handle(request) },
            "session.list":           { request in try await sessionListMethod.handle(request) },
            "service.run":            { request in try await serviceRunMethod.handle(request) },
            "service.shutdown":       { request in try await serviceShutdownMethod.handle(request) },
            "service.restart":        { request in try await serviceRestartMethod.handle(request) },
            "service.status":         { request in try await serviceStatusMethod.handle(request) },
            "service.reload":         { request in try await serviceReloadMethod.handle(request) },
        ]
        
        let dispatch = DispatchService(
            handlers: handlerMap,
            streamingHandlers: [
                "session.handler.register": { request, sink in
                    try await sessionHandlerRegisterMethod.handle(request, sink: sink)
                },
                "workflow.dispatch_stream": { request, sink in
                    try await workflowDispatchStreamMethod.handle(request, sink: sink)
                },
            ]
        )
        
        self.socketServer = UnixSocketServer(path: socketPath)
        self.acceptLoop = AcceptLoop(server: socketServer, dispatch: dispatch)
    }
    
    // MARK: - Public
    func boot() async throws {
        try Session.checkSocketLength(socketPath)
        
        if UnixSocketServer.isLive(path: socketPath) {
            throw ProtocolError("daemon already listening at \(socketPath) — "
                + "stop it, or use a different --session")
        }
        
        setenv("FORGE_SOCKET", socketPath, 1)
        setenv("FORGE_RUNTIME", config.runtimeDirectory.path, 1)
        
        await Log.shared.setSink(config.logJSONL)
        await Log.shared.setErrorSink(config.errorLog)
        await Log.shared.setMaxBytes(config.logMaximumBytes)
        await workflowStore.catalog()
        await scheduleStore.ensureRuntimeDirectory()
        await scheduleStore.catalog()
        await jobStore.reload()
        await jobStore.closeOrphans()
        await policyStore.catalog()
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
                "forge: shutdown drain grace expired with \(leftover.count) run(s) still live: \(leftover.map(\.workflowID).joined(separator: ", "))\n".utf8))
        }
        
        await workflowLogger.stop()
        await acceptLoop.stop()
        
        deleteRuntimeInfo()
    }
    
    nonisolated static func bootstrapSink(fdEnv: String?, isTTY: Bool) -> BootstrapSink {
        if let fdEnv, let fd = Int32(fdEnv), fd >= 0 { return .fd(fd) }
        
        return isTTY ? .stdout : .withheld
    }
    
    package static func run(configPath: String?, session: String?) async throws {
        let absoluteConfigPath = configPath
            .map { path in URL(fileURLWithPath: path).standardizedFileURL.path }
        let home = try Session.home(session: session)
        let (configuration, report) = try ConfigLoader.loadResolved(
            configPath: absoluteConfigPath,
            sessionHome: home
        )
        let server = Server(
            config: configuration,
            configReport: report,
            sessionHome: home,
            session: Session.name(session),
            configPath: absoluteConfigPath
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
        Session.runtimeInfo(in: sessionHome)
    }
    
    private func writeRuntimeInfo() {
        let info: [String: Any] = [
            "socket":                     socketPath,
            "session":                    session,
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
