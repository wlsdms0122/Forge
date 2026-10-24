//
//  WorkflowPool.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor WorkflowPool {
    enum WorkflowState: String, Sendable {
        case queued
        case running
        case cancelling
    }
    
    struct RunInfo: Sendable {
        // MARK: - Property
        let runID: String
        let workflowName: String
        let rootID: String
        let origin: DispatchOrigin
        let principal: String
        
        var state: WorkflowState
        
        let enqueuedAt: Date
        let enqueuedInstant: ContinuousClock.Instant
        
        var startedAt: Date?
        var heldSlots: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct HealthSnapshot: Sendable {
        struct WaiterWait: Sendable {
            // MARK: - Property
            let runID: String
            let waitedMs: Int
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        struct RunAge: Sendable {
            // MARK: - Property
            let runID: String
            let workflowName: String
            let state: String
            let ageMs: Int
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        struct Tree: Sendable {
            // MARK: - Property
            let rootID: String
            let count: Int
            let names: [String: Int]
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        let slotsMax: Int
        let slotsFree: Int
        let waiters: [WaiterWait]
        let activeRuns: Int
        let runCap: Int
        let refusedRuns: Int
        let oldestRuns: [RunAge]
        let trees: [Tree]
        let dispatchesLast60s: Int
        let refusedLast60s: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    private struct Waiter {
        // MARK: - Property
        let id: UInt64
        let runID: String
        let enqueuedInstant: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, Error>
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    private struct CancelWaiter {
        // MARK: - Property
        let id: UInt64
        let continuation: CheckedContinuation<Void, Never>
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    private struct RunningWaiter {
        // MARK: - Property
        let id: UInt64
        let continuation: CheckedContinuation<Void, Never>
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private static let recentRingCap = 512
    private static let recentWindow: Duration = .seconds(60)
    
    private let maximumConcurrentSteps: Int
    private let maximumActiveRuns: Int
    
    private var shuttingDown = false
    private var availableSlots: Int
    private var refusedRuns: Int = 0
    private var recentRefusals: [ContinuousClock.Instant] = []
    private var recentDispatches: [ContinuousClock.Instant] = []
    private var waiters: [Waiter] = []
    private var stepWaiterSeq: UInt64 = 0
    private var runs: [String: RunInfo] = [:]
    private var cancelled: Set<String> = []
    private var cancelWaiters: [String: [CancelWaiter]] = [:]
    private var cancelWaiterSeq: UInt64 = 0
    private var runningWaiters: [String: [RunningWaiter]] = [:]
    private var runningWaiterSeq: UInt64 = 0
    
    var configuredSlots: Int { maximumConcurrentSteps }
    
    var freeSlots: Int { availableSlots }
    
    var queuedWaiters: Int { waiters.count }
    
    // MARK: - Initializer
    init(maximumConcurrentSteps: Int, maximumActiveRuns: Int = 256) {
        precondition(
            maximumConcurrentSteps > 0,
            "maximumConcurrentSteps must be > 0, got \(maximumConcurrentSteps)"
        )
        precondition(maximumActiveRuns > 0, "maximumActiveRuns must be > 0, got \(maximumActiveRuns)")
        
        self.maximumConcurrentSteps = maximumConcurrentSteps
        self.availableSlots = maximumConcurrentSteps
        self.maximumActiveRuns = maximumActiveRuns
    }
    
    // MARK: - Public
    func beginShutdown() {
        shuttingDown = true
    }
    
    func drain(
        graceSeconds: Double = Subprocess.terminationGraceSeconds + 1
    ) async -> [RunInfo] {
        for info in snapshot() { cancel(runID: info.runID) }
        
        let deadline = ContinuousClock.now + .seconds(graceSeconds)
        
        while ContinuousClock.now < deadline {
            if runs.isEmpty { return [] }
            
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        return snapshot()
    }
    
    func workflowName(of runID: String) -> String? {
        runs[runID]?.workflowName
    }
    
    func register(
        runID: String,
        workflowName: String,
        rootID: String,
        origin: DispatchOrigin,
        principal: String
    ) throws {
        guard !shuttingDown else {
            throw DaemonShuttingDown("register: daemon is draining for shutdown — no new runs")
        }
        
        if runs[runID] != nil { return }
        
        guard runs.count < maximumActiveRuns else {
            refusedRuns += 1
            recentRefusals.append(ContinuousClock.now)
            
            if recentRefusals.count > Self.recentRingCap {
                recentRefusals.removeFirst(recentRefusals.count - Self.recentRingCap)
            }
            
            let trees = topTrees(limit: 3)
                .map { tree in "\(tree.rootID)=\(tree.count)" }
                .joined(separator: ", ")
            
            throw RunCapExceeded(
                "register: active run cap (\(maximumActiveRuns)) reached — "
                    + "top trees by active runs: [\(trees)]"
            )
        }
        
        runs[runID] = RunInfo(
            runID: runID,
            workflowName: workflowName,
            rootID: rootID,
            origin: origin,
            principal: principal,
            state: .queued,
            enqueuedAt: Date(),
            enqueuedInstant: ContinuousClock.now,
            startedAt: nil,
            heldSlots: 0
        )
        
        recentDispatches.append(ContinuousClock.now)
        
        if recentDispatches.count > Self.recentRingCap {
            recentDispatches.removeFirst(recentDispatches.count - Self.recentRingCap)
        }
    }
    
    func unregister(runID: String) {
        runs.removeValue(forKey: runID)
        cancelled.remove(runID)
        
        var remaining: [Waiter] = []
        
        for waiter in waiters {
            if waiter.runID == runID {
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                remaining.append(waiter)
            }
        }
        
        waiters = remaining
        
        for waiter in cancelWaiters.removeValue(forKey: runID) ?? [] {
            waiter.continuation.resume()
        }
        
        for waiter in runningWaiters.removeValue(forKey: runID) ?? [] {
            waiter.continuation.resume()
        }
    }
    
    func acquireStepSlot(runID: String) async throws {
        if Task.isCancelled || cancelled.contains(runID) {
            throw CancellationError()
        }
        
        if availableSlots > 0 && waiters.isEmpty {
            availableSlots -= 1
            markRunning(runID)
            
            return
        }
        
        let id = stepWaiterSeq
        stepWaiterSeq &+= 1
        
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled || cancelled.contains(runID) {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(
                        Waiter(
                            id: id,
                            runID: runID,
                            enqueuedInstant: ContinuousClock.now,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelStepWaiter(id: id) }
        }
        
        markRunning(runID)
    }
    
    func releaseStepSlot(runID: String) {
        if var info = runs[runID] {
            if info.heldSlots > 0 { info.heldSlots -= 1 }
            
            runs[runID] = info
        }
        
        while let next = waiters.first {
            waiters.removeFirst()
            
            if cancelled.contains(next.runID) {
                next.continuation.resume(throwing: CancellationError())
                
                continue
            }
            
            next.continuation.resume(returning: ())
            
            return
        }
        
        availableSlots += 1
    }
    
    func markStarted(runID: String) {
        transitionToRunning(runID)
    }
    
    @discardableResult
    func cancel(runID: String) -> Bool {
        guard var info = runs[runID] else { return false }
        
        cancelled.insert(runID)
        info.state = .cancelling
        runs[runID] = info
        
        var remaining: [Waiter] = []
        
        for waiter in waiters {
            if waiter.runID == runID {
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                remaining.append(waiter)
            }
        }
        
        waiters = remaining
        
        for waiter in cancelWaiters.removeValue(forKey: runID) ?? [] {
            waiter.continuation.resume()
        }
        
        return true
    }
    
    func awaitCancellation(runID: String) async {
        if cancelled.contains(runID) { return }
        
        let id = cancelWaiterSeq
        cancelWaiterSeq &+= 1
        
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if cancelled.contains(runID) {
                    continuation.resume()
                } else {
                    cancelWaiters[runID, default: []].append(
                        CancelWaiter(id: id, continuation: continuation)
                    )
                }
            }
        } onCancel: {
            Task { await self.dropCancelWaiter(runID: runID, id: id) }
        }
    }
    
    func awaitRunning(runID: String) async {
        if runs[runID]?.state == .running { return }
        
        let id = runningWaiterSeq
        runningWaiterSeq &+= 1
        
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if runs[runID]?.state == .running {
                    continuation.resume()
                } else {
                    runningWaiters[runID, default: []].append(
                        RunningWaiter(id: id, continuation: continuation)
                    )
                }
            }
        } onCancel: {
            Task { await self.dropRunningWaiter(runID: runID, id: id) }
        }
    }
    
    func isCancelled(runID: String) -> Bool {
        cancelled.contains(runID)
    }
    
    func health(now: ContinuousClock.Instant = ContinuousClock.now) -> HealthSnapshot {
        func elapsedMs(_ since: ContinuousClock.Instant) -> Int {
            Int((now - since) / .milliseconds(1))
        }
        
        let waiterWaits = waiters.map { waiter in
            HealthSnapshot.WaiterWait(
                runID: waiter.runID,
                waitedMs: elapsedMs(waiter.enqueuedInstant)
            )
        }
        let ages = runs.values
            .sorted { left, right in left.enqueuedInstant < right.enqueuedInstant }
            .prefix(5)
            .map { info in
                HealthSnapshot.RunAge(
                    runID: info.runID,
                    workflowName: info.workflowName,
                    state: info.state.rawValue,
                    ageMs: elapsedMs(info.enqueuedInstant)
                )
            }
        
        var nameCounts: [String: [String: Int]] = [:]
        
        for info in runs.values {
            nameCounts[info.rootID, default: [:]][info.workflowName, default: 0] += 1
        }
        
        let trees = nameCounts
            .map { rootID, names in
                (rootID: rootID, names: names, count: names.values.reduce(0, +))
            }
            .sorted { left, right in left.count > right.count }
            .prefix(5)
            .map { tree in
                HealthSnapshot.Tree(rootID: tree.rootID, count: tree.count, names: tree.names)
            }
        
        let rate = recentDispatches
            .filter { instant in (now - instant) <= Self.recentWindow }
            .count
        let refusedRate = recentRefusals
            .filter { instant in (now - instant) <= Self.recentWindow }
            .count
        
        return HealthSnapshot(
            slotsMax: maximumConcurrentSteps,
            slotsFree: availableSlots,
            waiters: waiterWaits,
            activeRuns: runs.count,
            runCap: maximumActiveRuns,
            refusedRuns: refusedRuns,
            oldestRuns: Array(ages),
            trees: Array(trees),
            dispatchesLast60s: rate,
            refusedLast60s: refusedRate
        )
    }
    
    func snapshot() -> [RunInfo] {
        runs.values.sorted { left, right in left.enqueuedAt < right.enqueuedAt }
    }
    
    // MARK: - Private
    private func topTrees(limit: Int) -> [(rootID: String, count: Int)] {
        var counts: [String: Int] = [:]
        
        for info in runs.values { counts[info.rootID, default: 0] += 1 }
        
        return counts
            .sorted { left, right in left.value > right.value }
            .prefix(limit)
            .map { entry in (rootID: entry.key, count: entry.value) }
    }
    
    private func markRunning(_ runID: String) {
        guard var info = runs[runID] else { return }
        
        info.heldSlots += 1
        runs[runID] = info
        
        transitionToRunning(runID)
    }
    
    private func transitionToRunning(_ runID: String) {
        guard var info = runs[runID], info.state == .queued else { return }
        
        info.state = .running
        info.startedAt = Date()
        runs[runID] = info
        
        for waiter in runningWaiters.removeValue(forKey: runID) ?? [] {
            waiter.continuation.resume()
        }
    }
    
    private func cancelStepWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { waiter in waiter.id == id }) else { return }
        
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
    
    private func dropCancelWaiter(runID: String, id: UInt64) {
        guard
            var pending = cancelWaiters[runID],
            let index = pending.firstIndex(where: { waiter in waiter.id == id })
        else {
            return
        }
        
        let waiter = pending.remove(at: index)
        cancelWaiters[runID] = pending.isEmpty ? nil : pending
        waiter.continuation.resume()
    }
    
    private func dropRunningWaiter(runID: String, id: UInt64) {
        guard
            var pending = runningWaiters[runID],
            let index = pending.firstIndex(where: { waiter in waiter.id == id })
        else {
            return
        }
        
        let waiter = pending.remove(at: index)
        runningWaiters[runID] = pending.isEmpty ? nil : pending
        waiter.continuation.resume()
    }
}
