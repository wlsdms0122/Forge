//
//  WorkflowHandlerBus.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor WorkflowHandlerBus {
    // MARK: - Property
    private var handles: [String: ServiceHandle] = [:]
    
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    func register(
        service: String,
        schema: JSONObject?,
        sink: any EventSink
    ) async -> ServiceHandle {
        if let existing = handles[service] {
            await existing.cancelAll()
        }
        
        let handle = ServiceHandle(service: service, schema: schema, sink: sink)
        handles[service] = handle
        
        return handle
    }
    
    func unregister(service: String, handle: ServiceHandle) async {
        guard handles[service] === handle else { return }
        
        handles.removeValue(forKey: service)
        
        await handle.cancelAll()
    }
    
    func handle(service: String) -> ServiceHandle? {
        handles[service]
    }
    
    func listing() -> [(String, JSONObject?)] {
        var listing: [(String, JSONObject?)] = []
        
        for (name, handle) in handles {
            listing.append((name, handle.schema))
        }
        
        return listing.sorted { left, right in left.0 < right.0 }
    }
    
    func deliverResult(service: String, messageID: String, result: JSONObject) async {
        guard let handle = handles[service] else { return }
        
        await handle.deliverResult(messageID: messageID, result: result)
    }
    
    func deliverError(service: String, messageID: String, message: String) async {
        guard let handle = handles[service] else { return }
        
        await handle.deliverError(messageID: messageID, message: message)
    }
    
    // MARK: - Private
}
