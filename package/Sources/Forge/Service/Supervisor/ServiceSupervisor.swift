//
//  ServiceSupervisor.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor ServiceSupervisor {
    private enum State: String {
        case stopped, running, backoff, failed
    }
    
    private final class Instance {
        // MARK: - Property
        var desiredRunning = false
        var state: State = .stopped
        var process: Process?
        var startedAt: Date?
        var consecutiveCrashes = 0
        var lastExitCode: Int32?
        var loop: Task<Void, Never>?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private var specs: [String: ServiceConfig]
    private var instances: [String: Instance] = [:]
    private var shuttingDown = false
    private var booted = false
    
    private let tokenAuthority: TokenAuthority
    private let stateDir: URL
    
    // MARK: - Initializer
    init(services: [ServiceConfig], runtimeDirectory: URL, tokenAuthority: TokenAuthority) {
        self.specs = Dictionary(
            uniqueKeysWithValues: services.map { service in (service.name, service) }
        )
        self.tokenAuthority = tokenAuthority
        self.stateDir = runtimeDirectory.appendingPathComponent("services", isDirectory: true)
    }
    
    // MARK: - Public
    func boot() async {
        guard !booted else { return }
        
        booted = true
        
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        
        await reapStaleOrphans()
        
        for name in specs.keys.sorted() where specs[name]!.autoSpawn {
            await start(name)
        }
    }
    
    func stopAll() async {
        shuttingDown = true
        
        for instance in instances.values {
            instance.desiredRunning = false
            instance.loop?.cancel()
        }
        
        let running = instances.values.compactMap(\.process)
        
        for process in running where process.isRunning {
            Subprocess.signalTree(pid: process.processIdentifier, sig: SIGTERM)
        }
        
        let deadline = ContinuousClock.now + .seconds(5)
        
        while running.contains(where: \.isRunning), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        for process in running where process.isRunning {
            Subprocess.signalTree(pid: process.processIdentifier, sig: SIGKILL)
        }
        
        for instance in instances.values { await instance.loop?.value }
    }
    
    func run(_ name: String) async throws -> ServiceStatusRecord {
        guard specs[name] != nil else {
            throw ProtocolError("service.run: '\(name)' is not in config — add [service.\(name)] to .forge/config.toml, then `forge service reload`")
        }
        
        guard !shuttingDown else {
            throw ProtocolError("service.run: daemon is shutting down")
        }
        
        await start(name)
        await waitFirstTransition(name)
        
        return statusRecord(name)
    }
    
    func shutdown(_ name: String) async throws -> ServiceStatusRecord {
        guard specs[name] != nil || instances[name] != nil else {
            throw ProtocolError("service.shutdown: unknown service '\(name)'")
        }
        
        await stop(name)
        
        return statusRecord(name)
    }
    
    func restart(_ name: String) async throws -> ServiceStatusRecord {
        guard specs[name] != nil else {
            throw ProtocolError("service.restart: '\(name)' is not in config")
        }
        
        guard !shuttingDown else {
            throw ProtocolError("service.restart: daemon is shutting down")
        }
        
        await stop(name)
        await start(name)
        await waitFirstTransition(name)
        
        return statusRecord(name)
    }
    
    func statuses() -> [ServiceStatusRecord] {
        specs.keys.sorted().map { name in statusRecord(name) }
    }
    
    func reload(_ newSpecs: [ServiceConfig]) async -> [String: [String]] {
        let newMap = Dictionary(
            uniqueKeysWithValues: newSpecs.map { service in (service.name, service) }
        )
        let added = newMap.keys.filter { name in specs[name] == nil }.sorted()
        let removed = specs.keys.filter { name in newMap[name] == nil }.sorted()
        let changed = newMap.keys
            .filter { name in specs[name] != nil && specs[name] != newMap[name] }
            .sorted()
        
        specs = newMap
        
        for name in removed {
            await stop(name)
            instances.removeValue(forKey: name)
        }
        
        for name in added where newMap[name]!.autoSpawn {
            await start(name)
        }
        
        return ["added": added, "removed": removed, "changed": changed]
    }
    
    // MARK: - Private
    private func start(_ name: String) async {
        let instance = instance(name)
        
        while true {
            if shuttingDown { return }
            if instance.desiredRunning, instance.loop != nil { return }
            
            guard let old = instance.loop else { break }
            
            await old.value
        }
        
        instance.desiredRunning = true
        instance.consecutiveCrashes = 0
        instance.lastExitCode = nil
        instance.state = .stopped
        instance.loop = Task { await self.superviseLoop(name) }
    }
    
    private func waitFirstTransition(_ name: String) async {
        let deadline = ContinuousClock.now + .seconds(2)
        
        while ContinuousClock.now < deadline {
            guard let instance = instances[name] else { return }
            
            if instance.state != .stopped || !instance.desiredRunning { return }
            
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    
    private func stop(_ name: String) async {
        guard let instance = instances[name] else { return }
        
        let loop = instance.loop
        instance.desiredRunning = false
        loop?.cancel()
        
        if let process = instance.process, process.isRunning {
            Subprocess.signalTree(pid: process.processIdentifier, sig: SIGTERM)
            
            let deadline = ContinuousClock.now + .seconds(5)
            
            while process.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            if process.isRunning {
                Subprocess.signalTree(pid: process.processIdentifier, sig: SIGKILL)
            }
        }
        
        await loop?.value
    }
    
    private func superviseLoop(_ name: String) async {
        guard let instance = instances[name] else { return }
        
        var delay = specs[name]?.restart.backoffInitial ?? .seconds(1)
        
        while instance.desiredRunning, let spec = specs[name] {
            let exitBox = ExitBox()
            let process: Process
            
            do {
                process = try spawn(spec, exitBox: exitBox)
            } catch {
                instance.consecutiveCrashes += 1
                
                await Log.shared.append(
                    "service.spawn_failed",
                    [
                        "service": name,
                        "error": String(describing: error),
                        "crashes": instance.consecutiveCrashes,
                    ],
                    level: .default,
                    category: "service"
                )
                
                if instance.consecutiveCrashes >= spec.restart.crashLoopLimit {
                    instance.state = .failed
                    instance.desiredRunning = false
                    
                    break
                }
                
                instance.state = .backoff
                
                try? await Task.sleep(for: delay)
                
                delay = min(delay * 2, spec.restart.backoffMax)
                
                continue
            }
            
            instance.process = process
            instance.startedAt = Date()
            instance.state = .running
            
            writePidFile(name: name, pid: process.processIdentifier, command: spec.command)
            
            await Log.shared.append(
                "service.spawn",
                ["service": name, "pid": Int(process.processIdentifier)],
                level: .default,
                category: "service"
            )
            
            let code = await exitBox.wait()
            let uptime = Date().timeIntervalSince(instance.startedAt ?? Date())
            instance.process = nil
            instance.startedAt = nil
            instance.lastExitCode = code
            
            removePidFile(name)
            
            if !instance.desiredRunning {
                instance.state = .stopped
                
                await Log.shared.append(
                    "service.stop",
                    ["service": name, "exit_code": Int(code)],
                    level: .default,
                    category: "service"
                )
                
                break
            }
            
            let stableSeconds = TimeInterval(spec.restart.stableUptime.components.seconds)
            
            if uptime >= stableSeconds {
                instance.consecutiveCrashes = 1
                delay = spec.restart.backoffInitial
            } else {
                instance.consecutiveCrashes += 1
            }
            
            await Log.shared.append(
                "service.crash",
                [
                    "service": name,
                    "exit_code": Int(code),
                    "uptime_s": Int(uptime),
                    "crashes": instance.consecutiveCrashes,
                ],
                level: .default,
                category: "service"
            )
            
            if instance.consecutiveCrashes >= spec.restart.crashLoopLimit {
                instance.state = .failed
                instance.desiredRunning = false
                
                await Log.shared.append(
                    "service.crash_loop",
                    ["service": name, "crashes": instance.consecutiveCrashes],
                    level: .default,
                    category: "service"
                )
                
                break
            }
            
            instance.state = .backoff
            
            try? await Task.sleep(for: delay)
            
            delay = min(delay * 2, spec.restart.backoffMax)
        }
        
        if instance.state != .failed { instance.state = .stopped }
        
        instance.loop = nil
    }
    
    private func spawn(_ spec: ServiceConfig, exitBox: ExitBox) throws -> Process {
        let process = Process()
        let executable = spec.command[0]
        let args = Array(spec.command.dropFirst())
        
        if executable.contains("/") {
            if !executable.hasPrefix("/"), let cwd = spec.workingDirectory {
                process.executableURL = cwd.appendingPathComponent(executable).standardizedFileURL
            } else {
                process.executableURL = URL(fileURLWithPath: executable)
            }
            
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args
        }
        
        if let cwd = spec.workingDirectory { process.currentDirectoryURL = cwd }
        
        var environment = ProcessInfo.processInfo.environment
        
        for (key, value) in spec.environment { environment[key] = value }
        
        environment["FORGE_ACCESS_TOKEN"] = tokenAuthority.mint(
            TokenClaims(principal: "service:\(spec.name)")
        )
        
        for (key, value) in SubprocessEnv.forgeBinEnv() { environment[key] = value }
        
        process.environment = environment
        
        let logHandle = try openLogFile(spec)
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { process in
            try? logHandle.close()
            exitBox.complete(process.terminationStatus)
        }
        
        try process.run()
        
        return process
    }
    
    private func openLogFile(_ spec: ServiceConfig) throws -> FileHandle {
        let url = spec.logFile ?? stateDir.appendingPathComponent("\(spec.name).log")
        let fileManager = FileManager.default
        
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        
        return handle
    }
    
    private func pidFileURL(_ name: String) -> URL {
        stateDir.appendingPathComponent("\(name).pid")
    }
    
    private func writePidFile(name: String, pid: Int32, command: [String]) {
        let info: [String: Any] = [
            "service":    name,
            "pid":        Int(pid),
            "command":    command,
            "started_at": ISO8601DateFormatter().string(from: Date()),
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) {
            try? data.write(to: pidFileURL(name))
        }
    }
    
    private func removePidFile(_ name: String) {
        try? FileManager.default.removeItem(at: pidFileURL(name))
    }
    
    private func reapStaleOrphans() async {
        let fileManager = FileManager.default
        
        guard let entries = try? fileManager.contentsOfDirectory(
            at: stateDir,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        
        var alive: [(URL, Int32)] = []
        
        for url in entries where url.pathExtension == "pid" {
            guard let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pid = (object["pid"] as? Int).map(Int32.init)
            else {
                try? fileManager.removeItem(at: url)
                
                continue
            }
            
            guard kill(pid, 0) == 0 else {
                try? fileManager.removeItem(at: url)
                
                continue
            }
            
            let expected = object["command"] as? [String] ?? []
            
            guard pidMatchesCommand(pid, expected: expected) else {
                try? fileManager.removeItem(at: url)
                
                await Log.shared.append(
                    "service.reap_skip",
                    [
                        "pid": Int(pid),
                        "pid_file": url.lastPathComponent,
                        "reason": "pid reused by another process",
                    ],
                    level: .default,
                    category: "service"
                )
                
                continue
            }
            
            Subprocess.signalTree(pid: pid, sig: SIGTERM)
            alive.append((url, pid))
        }
        
        guard !alive.isEmpty else { return }
        
        let deadline = ContinuousClock.now + .seconds(5)
        
        while alive.contains(where: { entry in kill(entry.1, 0) == 0 }),
            ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        for (url, pid) in alive {
            if kill(pid, 0) == 0 { Subprocess.signalTree(pid: pid, sig: SIGKILL) }
            
            if let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let current = object["pid"] as? Int, Int32(current) != pid {
                continue
            }
            
            try? fileManager.removeItem(at: url)
            
            await Log.shared.append(
                "service.reap",
                ["pid": Int(pid), "pid_file": url.lastPathComponent],
                level: .default,
                category: "service"
            )
        }
    }
    
    private func pidMatchesCommand(_ pid: Int32, expected: [String]) -> Bool {
        guard let head = expected.first else { return true }
        guard let line = processCommandLine(pid) else { return true }
        
        let headNeedle = head.contains("/")
            ? head
            : URL(fileURLWithPath: head).lastPathComponent
        
        if line.contains(headNeedle) { return true }
        
        if head.contains("/") {
            let resolved = URL(fileURLWithPath: head).resolvingSymlinksInPath().path
            
            if resolved != head, line.contains(resolved) { return true }
        }
        
        let tail = expected.dropFirst().joined(separator: " ")
        
        if tail.count >= 4, line.contains(tail) { return true }
        
        return false
    }
    
    private func processCommandLine(_ pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "command=", "-p", String(pid)]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            return nil
        }
        
        process.waitUntilExit()
        
        guard let data = try? pipe.fileHandleForReading.readToEnd() else { return nil }
        
        return String(data: data, encoding: .utf8)
    }
    
    private func instance(_ name: String) -> Instance {
        if let existing = instances[name] { return existing }
        
        let created = Instance()
        instances[name] = created
        
        return created
    }
    
    private func statusRecord(_ name: String) -> ServiceStatusRecord {
        let instance = instances[name]
        
        return ServiceStatusRecord(
            name: name,
            state: (instance?.state ?? .stopped).rawValue,
            pid: instance?.process?.processIdentifier,
            startedAt: instance?.startedAt,
            consecutiveCrashes: instance?.consecutiveCrashes ?? 0,
            lastExitCode: instance?.lastExitCode,
            autoSpawn: specs[name]?.autoSpawn ?? false
        )
    }
}

private final class ExitBox: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var code: Int32?
    private var waiter: CheckedContinuation<Int32, Never>?
    
    // MARK: - Initializer
    // MARK: - Public
    func complete(_ exitCode: Int32) {
        lock.lock()
        
        if let waiting = waiter {
            waiter = nil
            lock.unlock()
            waiting.resume(returning: exitCode)
        } else {
            code = exitCode
            lock.unlock()
        }
    }
    
    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            
            if let code {
                lock.unlock()
                continuation.resume(returning: code)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
    
    // MARK: - Private
}
