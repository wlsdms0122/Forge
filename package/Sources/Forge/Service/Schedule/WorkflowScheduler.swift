//
//  WorkflowScheduler.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

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
    
    let workflows: WorkflowReader
    let store: ScheduleStore
    let ledger: FireLedger
    let runner: WorkflowRunner
    let tickIntervalSeconds: Int
    
    private var nextFire: [String: Date] = [:]
    private var seenTrigger: [String: Trigger] = [:]
    private var running: [String: RunHandle] = [:]
    private var runCounter: UInt64 = 0
    private var tickerTask: Task<Void, Never>?
    
    // MARK: - Initializer
    init(
        workflows: WorkflowReader,
        store: ScheduleStore,
        ledger: FireLedger,
        runner: WorkflowRunner,
        tickIntervalSeconds: Int = 5
    ) {
        self.workflows = workflows
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
                
                do {
                    try await store.delete(id: schedule.id)
                    try await ledger.clear(id: schedule.id)
                } catch {
                    FileHandle.standardError.write(Data(
                        "forge: schedule '\(schedule.id)' spent-once GC failed: \(error)\n".utf8))
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
        
        let target: Workflow
        
        switch await Self.resolveFireTarget(
            schedule,
            workflows: workflows,
            policyStore: runner.policyStore
        ) {
        case .resolved(let resolved):
            target = resolved
        
        case .denied(let reason, let detail):
            await Self.denyFireSlot(
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
            
            await Self.dispatchScheduled(
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
        let workflowsLocal = workflows
        let ledgerLocal = ledger
        
        Task.detached {
            let target: Workflow
            
            switch await Self.resolveFireTarget(
                schedule,
                workflows: workflowsLocal,
                policyStore: runnerLocal.policyStore
            ) {
            case .resolved(let resolved):
                target = resolved
            
            case .denied(let reason, let detail):
                await Self.denyFireSlot(
                    ledger: ledgerLocal,
                    scheduleID: schedule.id,
                    workflow: schedule.workflow,
                    reason: reason,
                    detail: detail
                )
                
                return
            }
            
            await ledgerLocal.close(id: schedule.id, .launched)
            await Self.dispatchScheduled(
                target: target,
                inputs: schedule.inputs ?? [:],
                id: schedule.id,
                runner: runnerLocal
            )
        }
    }
    
    // A fire is denied here when its slot can be known not to start a run: the
    // target does not resolve, or the policy refuses the fire's principal. The
    // dispatch door enforces the policy again when the run is admitted, which
    // under `queue` comes after this slot has closed.
    private static func resolveFireTarget(
        _ schedule: Schedule,
        workflows: WorkflowReader,
        policyStore: PolicyStore
    ) async -> FireResolution {
        let target: Workflow
        
        if let spec = schedule.spec {
            do {
                target = try await workflows.inline(spec)
            } catch {
                return .denied(reason: "spec_decode", detail: String(describing: error))
            }
        } else {
            do {
                target = try await workflows.workflow(at: schedule.workflow)
            } catch let missing as WorkflowNotFound {
                return .denied(reason: "workflow_missing", detail: missing.message)
            } catch {
                return .denied(reason: "workflow_invalid", detail: String(describing: error))
            }
        }
        
        do {
            try await DispatchAuthorization.requireDispatch(
                principal: firePrincipal(schedule.id),
                workflow: target.path,
                policyStore: policyStore,
                context: "schedule"
            )
        } catch {
            return .denied(reason: "policy_denied", detail: String(describing: error))
        }
        
        return .resolved(target)
    }
    
    private static func firePrincipal(_ scheduleID: String) -> String {
        "system:schedule:\(scheduleID)"
    }
    
    private static func denyFireSlot(
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
    
    private static func dispatchScheduled(
        target: Workflow,
        inputs: [String: JSONValue],
        id: String,
        runner: WorkflowRunner
    ) async {
        let principal = firePrincipal(id)
        let runID = WorkflowRunner.newRunID()
    
        await Log.shared.append(
            "schedule.fired",
            LogPayload([
                "schedule_id":  id,
                "workflow":    target.path,
                "run_id": runID,
                "principal":   principal,
            ]),
            level: .info,
            category: "schedule"
        )
    
        do {
            _ = try await runner.dispatch(
                target,
                inputs: try inputs.mapValues(ValueBridge.value),
                principal: principal,
                origin: .schedule(id),
                runID: runID,
                mode: .awaited
            )
        } catch {
            await Log.shared.append(
                "schedule.denied",
                LogPayload([
                    "schedule_id":  id,
                    "workflow":    target.path,
                    "run_id": runID,
                    "principal":   principal,
                    "stage":       "dispatch",
                    "error":       String(describing: error),
                ]),
                level: .error,
                category: "schedule"
            )
        }
    }
}
