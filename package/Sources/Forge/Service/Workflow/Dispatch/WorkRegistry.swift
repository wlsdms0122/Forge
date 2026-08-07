//
//  WorkRegistry.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor WorkRegistry {
    // MARK: - Property
    private var byWorkflow: [String: WorkRecord] = [:]
    private var closing: Set<String> = []
    private var inflightTouches: [String: Int] = [:]
    private var drainWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    func register(_ record: WorkRecord) {
        byWorkflow[record.workflowID] = record
    }
    
    func lookup(workflowID: String) -> WorkRecord? {
        byWorkflow[workflowID]
    }
    
    func requireLiveRecord(workflowID: String?, context: String) throws -> WorkRecord? {
        guard let workflowID else { return nil }
        
        guard let record = byWorkflow[workflowID] else {
            throw TokenRejected(
                "\(context): workflow token for finished run '\(workflowID)'"
                    + " — a run-scoped token dies with its run"
            )
        }
        
        return record
    }
    
    func updateSpan(workflowID: String, nodeID: String?) {
        guard let record = byWorkflow[workflowID] else { return }
        
        byWorkflow[workflowID] = record.withNodeID(nodeID)
    }
    
    func beginTouch(workflowID: String) -> Bool {
        guard byWorkflow[workflowID] != nil, !closing.contains(workflowID) else { return false }
        
        inflightTouches[workflowID, default: 0] += 1
        
        return true
    }
    
    func endTouch(workflowID: String) {
        guard let count = inflightTouches[workflowID] else { return }
        
        if count <= 1 {
            inflightTouches.removeValue(forKey: workflowID)
            
            for waiter in drainWaiters.removeValue(forKey: workflowID) ?? [] { waiter.resume() }
        } else {
            inflightTouches[workflowID] = count - 1
        }
    }
    
    func beginClose(workflowID: String) async {
        closing.insert(workflowID)
        
        while inflightTouches[workflowID, default: 0] > 0 {
            await withCheckedContinuation { continuation in
                drainWaiters[workflowID, default: []].append(continuation)
            }
        }
    }
    
    func release(workflowID: String) {
        byWorkflow.removeValue(forKey: workflowID)
        closing.remove(workflowID)
    }
    
    // MARK: - Private
}
