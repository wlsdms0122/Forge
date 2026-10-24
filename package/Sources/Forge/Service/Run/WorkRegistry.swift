//
//  WorkRegistry.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor WorkRegistry {
    // MARK: - Property
    private var byRun: [String: WorkRecord] = [:]
    private var closing: Set<String> = []
    private var inflightTouches: [String: Int] = [:]
    private var drainWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    func register(_ record: WorkRecord) {
        byRun[record.runID] = record
    }
    
    func lookup(runID: String) -> WorkRecord? {
        byRun[runID]
    }
    
    func requireLiveRecord(runID: String?, context: String) throws -> WorkRecord? {
        guard let runID else { return nil }
        
        guard let record = byRun[runID] else {
            throw TokenRejected(
                "\(context): workflow token for finished run '\(runID)'"
                    + " — a run-scoped token dies with its run"
            )
        }
        
        return record
    }
    
    func updateSpan(runID: String, nodeID: String?) {
        guard let record = byRun[runID] else { return }
        
        byRun[runID] = record.withNodeID(nodeID)
    }
    
    func beginTouch(runID: String) -> Bool {
        guard byRun[runID] != nil, !closing.contains(runID) else { return false }
        
        inflightTouches[runID, default: 0] += 1
        
        return true
    }
    
    func endTouch(runID: String) {
        guard let count = inflightTouches[runID] else { return }
        
        if count <= 1 {
            inflightTouches.removeValue(forKey: runID)
            
            for waiter in drainWaiters.removeValue(forKey: runID) ?? [] { waiter.resume() }
        } else {
            inflightTouches[runID] = count - 1
        }
    }
    
    func beginClose(runID: String) async {
        closing.insert(runID)
        
        while inflightTouches[runID, default: 0] > 0 {
            await withCheckedContinuation { continuation in
                drainWaiters[runID, default: []].append(continuation)
            }
        }
    }
    
    func release(runID: String) {
        byRun.removeValue(forKey: runID)
        closing.remove(runID)
    }
    
    // MARK: - Private
}
