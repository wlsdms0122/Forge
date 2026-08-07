//
//  Scheduler.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Spec

actor WorkflowScheduler {
    private struct RunHandle {
        // MARK: - Property
        let task: Task<Void, Never>
        let token: UInt64
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let pendingCloseGraceSeconds: TimeInterval = 60
    
    let workflowStore: SpecCatalog
    let store: ScheduleStore
    let ledger: FireLedger
    let runner: SpecWorkflowRunner
    let tickIntervalSeconds: Int
    
    private var nextFire: [String: Date] = [:]
    private var seenTrigger: [String: Trigger] = [:]
    private var running: [String: RunHandle] = [:]
    private var runCounter: UInt64 = 0
    private var tickerTask: Task<Void, Never>?
    
    // MARK: - Initializer
    init(
        workflowStore: SpecCatalog,
        store: ScheduleStore,
        ledger: FireLedger,
        runner: SpecWorkflowRunner,
        tickIntervalSeconds: Int = 5
    ) {
        self.workflowStore = workflowStore
        self.store = store
        self.ledger = ledger
        self.runner = runner
        self.tickIntervalSeconds = tickIntervalSeconds
    }
    
    // MARK: - Public
    func start() async {
        await stop()
        
        let interval = tickIntervalSeconds
        
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                
                if Task.isCancelled { return }
                
                await self?.tick()
            }
        }
    }
    
    func stop() async {
        tickerTask?.cancel()
        tickerTask = nil
        
        for (_, handle) in running { handle.task.cancel() }
        
        running.removeAll()
    }
    
    func tickOnce() async {
        await tick()
    }
    
    // MARK: - Private
    private func tick() async {
        let snapshot = await store.tickSnapshot()
        let entries = snapshot.entries
        let now = Date()
        let ledgerMap = await ledger.snapshot()
        
        for entry in entries {
            let schedule = entry.schedule
            
            if !schedule.enabled {
                nextFire.removeValue(forKey: schedule.id)
                seenTrigger.removeValue(forKey: schedule.id)
                
                continue
            }
            
            if seenTrigger[schedule.id] != schedule.trigger {
                seenTrigger[schedule.id] = schedule.trigger
                nextFire[schedule.id] = schedule.trigger.nextFire(
                    after: ledgerMap[schedule.id]?.attemptedSlot,
                    now: now
                )
            }
            
            if let record = ledgerMap[schedule.id], nextFire[schedule.id] == nil {
                if record.state == .pending {
                    if now.timeIntervalSince(record.recordedAt) < Self.pendingCloseGraceSeconds {
                        continue
                    }
                    
                    FileHandle.standardError.write(Data(
                        "forge: schedule '\(schedule.id)' attempt (recorded \(ISO8601.string(record.recordedAt))) never closed — a fire path leaked the observability contract; collecting\n".utf8))
                }
                
                if case .closed(.denied) = record.state, schedule.trigger.isOneShot { continue }
                
                if entry.runtime {
                    do {
                        try await store.delete(id: schedule.id)
                        try await ledger.clear(id: schedule.id)
                    } catch {
                        FileHandle.standardError.write(Data(
                            "forge: schedule '\(schedule.id)' spent-once GC failed: \(error)\n".utf8))
                    }
                }
                
                continue
            }
            
            guard let due = nextFire[schedule.id], due <= now else { continue }
            
            let fireAnchor: Date
            let nextSlot: Date?
            
            if var next = schedule.trigger.advance(after: due) {
                var lastConsumed = due
                
                while next <= now, let following = schedule.trigger.advance(after: next) {
                    lastConsumed = next
                    next = following
                }
                
                fireAnchor = lastConsumed
                nextSlot = next
            } else {
                fireAnchor = due
                nextSlot = nil
            }
            
            if let previous = ledgerMap[schedule.id], previous.state == .pending {
                FileHandle.standardError.write(Data(
                    "forge: schedule '\(schedule.id)' previous attempt (recorded \(ISO8601.string(previous.recordedAt))) never closed — a fire path leaked the observability contract\n".utf8))
            }
            
            do {
                try await ledger.recordAttempt(id: schedule.id, slot: fireAnchor)
            } catch {
                FileHandle.standardError.write(Data(
                    "forge: schedule '\(schedule.id)' fire-ledger persist failed, deferring fire: \(error)\n".utf8))
                
                continue
            }
            
            if let nextSlot {
                nextFire[schedule.id] = nextSlot
                
                await fireRecurring(schedule)
            } else {
                nextFire.removeValue(forKey: schedule.id)
                fireOnce(schedule)
            }
        }
        
        guard snapshot.declarationsComplete else { return }
        
        let declared = snapshot.declaredIDs
        nextFire = nextFire.filter { element in declared.contains(element.key) }
        seenTrigger = seenTrigger.filter { element in declared.contains(element.key) }
        
        for id in running.keys where !declared.contains(id) {
            running[id]?.task.cancel()
            running.removeValue(forKey: id)
        }
        
        do {
            try await ledger.prune(liveIDs: declared)
        } catch {
            FileHandle.standardError.write(Data(
                "forge: fire-ledger prune failed: \(error)\n".utf8))
        }
    }
    
    private func fireRecurring(_ schedule: Schedule) async {
        let prior = running[schedule.id]
        
        if prior != nil, schedule.concurrency == .skip {
            await Log.shared.append(
                "schedule.skipped",
                LogPayload([
                    "schedule_id": schedule.id,
                    "workflow":   schedule.workflow,
                    "reason":     "previous still running",
                ]),
                category: "schedule"
            )
            await ledger.close(id: schedule.id, .skipped)
            
            return
        }
        
        let target: FireTarget
        
        switch await resolveFireTarget(
            name: schedule.workflow,
            spec: schedule.spec,
            store: workflowStore
        ) {
        case .resolved(let resolved):
            target = resolved
        
        case .denied(let reason, let detail):
            await denyFireSlot(
                ledger: ledger,
                scheduleID: schedule.id,
                workflow: schedule.workflow,
                reason: reason,
                detail: detail
            )
            
            return
        }
        
        await ledger.close(id: schedule.id, .launched)
        
        if schedule.concurrency == .replace { prior?.task.cancel() }
        
        let priorTask = prior?.task
        let token = nextRunToken()
        let task = Task { [weak self, runner] in
            if let priorTask { _ = await priorTask.value }
            
            await dispatchScheduled(
                target: target,
                inputs: schedule.inputs ?? [:],
                id: schedule.id,
                runner: runner
            )
            await self?.finishRun(id: schedule.id, token: token)
        }
        
        running[schedule.id] = RunHandle(task: task, token: token)
    }
    
    private func finishRun(id: String, token: UInt64) {
        if running[id]?.token == token { running.removeValue(forKey: id) }
    }
    
    private func nextRunToken() -> UInt64 {
        runCounter &+= 1
        
        return runCounter
    }
    
    private func fireOnce(_ schedule: Schedule) {
        let runnerLocal = runner
        let storeLocal = workflowStore
        let ledgerLocal = ledger
        
        Task.detached {
            let target: FireTarget
            
            switch await resolveFireTarget(
                name: schedule.workflow,
                spec: schedule.spec,
                store: storeLocal
            ) {
            case .resolved(let resolved):
                target = resolved
            
            case .denied(let reason, let detail):
                await denyFireSlot(
                    ledger: ledgerLocal,
                    scheduleID: schedule.id,
                    workflow: schedule.workflow,
                    reason: reason,
                    detail: detail
                )
                
                return
            }
            
            await ledgerLocal.close(id: schedule.id, .launched)
            await dispatchScheduled(
                target: target,
                inputs: schedule.inputs ?? [:],
                id: schedule.id,
                runner: runnerLocal
            )
        }
    }
}

private struct FireTarget: Sendable {
    // MARK: - Property
    let name: String
    let program: Spec.Program
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

private enum FireResolution {
    case resolved(FireTarget)
    case denied(reason: String, detail: String)
}

private func resolveFireTarget(
    name: String,
    spec: JSONValue?,
    store: SpecCatalog
) async -> FireResolution {
    if let spec {
        do {
            let program = try store.loader.lower(ValueBridge.value(spec))
            
            return .resolved(FireTarget(name: name, program: program))
        } catch {
            return .denied(reason: "spec_decode", detail: String(describing: error))
        }
    }
    
    switch await store.resolve(name) {
    case .found(let program):
        return .resolved(FireTarget(name: name, program: program))
    
    case .invalid(let reason):
        return .denied(reason: "workflow_invalid", detail: reason)
    
    case .unobserved(let reason):
        return .denied(reason: "workflow_unobserved", detail: reason)
    
    case .missing:
        return .denied(reason: "workflow_missing", detail: "unknown workflow '\(name)'")
    }
}

private func denyFireSlot(
    ledger: FireLedger,
    scheduleID: String,
    workflow: String,
    reason: String,
    detail: String
) async {
    await Log.shared.append(
        "schedule.denied",
        LogPayload([
            "schedule_id": scheduleID,
            "workflow":   workflow,
            "stage":      "resolve",
            "reason":     reason,
            "error":      detail,
        ]),
        level: .error,
        category: "schedule"
    )
    await ledger.close(id: scheduleID, .denied(reason: reason))
}

private func dispatchScheduled(
    target: FireTarget,
    inputs: [String: JSONValue],
    id: String,
    runner: SpecWorkflowRunner
) async {
    let principal = "system:schedule:\(id)"
    let runID = SpecWorkflowRunner.newRunID()
    
    await Log.shared.append(
        "schedule.fired",
        LogPayload([
            "schedule_id":  id,
            "workflow":    target.name,
            "workflow_id": runID,
            "principal":   principal,
        ]),
        level: .info,
        category: "schedule"
    )
    
    do {
        _ = try await runner.dispatch(
            program: target.program,
            name: target.name,
            inputs: inputs,
            principal: principal,
            origin: .schedule(id),
            workflowID: runID,
            mode: .awaited
        )
    } catch {
        await Log.shared.append(
            "schedule.denied",
            LogPayload([
                "schedule_id":  id,
                "workflow":    target.name,
                "workflow_id": runID,
                "principal":   principal,
                "stage":       "dispatch",
                "error":       String(describing: error),
            ]),
            level: .error,
            category: "schedule"
        )
    }
}
