//
//  WorkflowLogger.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor WorkflowLogger {
    // MARK: - Property
    private let bus: WorkflowEventBus
    
    private var consumeTask: Task<Void, Never>?
    private var token: WorkflowEventBus.Token?
    
    // MARK: - Initializer
    init(bus: WorkflowEventBus) {
        self.bus = bus
    }
    
    // MARK: - Public
    func start() async {
        guard consumeTask == nil else { return }
        
        let (token, stream) = await bus.subscribe()
        self.token = token
        
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.write(event)
            }
        }
    }
    
    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        
        if let token { await bus.unsubscribe(token) }
        
        token = nil
    }
    
    // MARK: - Private
    private func write(_ event: WorkflowEvent) async {
        var payload = event.toJSONObject()
        
        for envelopeOwned in ["event", "ts", "root_id", "node_id", "parent_node_id", "parameters"] {
            payload.removeValue(forKey: envelopeOwned)
        }
        
        for fullValue in ["output", "outputs", "inputs"] {
            payload.removeValue(forKey: fullValue)
        }
        
        let category: String
        
        switch event.kind.rawValue {
        case let kind where kind.hasPrefix("step."):
            category = "workflow.step"
        
        default:
            category = "workflow"
        }
        
        var errorObject: [String: Any]? = nil
        
        if let errorType = event.errorType {
            var error: [String: Any] = ["type": errorType]
            
            if let errorMessage = event.errorMessage { error["message"] = errorMessage }
            
            errorObject = error
        }
        
        await Log.shared.append(
            event.kind.rawValue,
            LogPayload(payload),
            category: category,
            error: errorObject,
            parameters: event.parameters,
            rootID: event.rootID,
            nodeID: event.nodeID,
            parentNodeID: event.parentNodeID,
            at: event.timestamp
        )
    }
}
