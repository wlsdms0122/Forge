//
//  WorkflowEventBus.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

actor WorkflowEventBus {
    typealias Token = UUID
    
    // MARK: - Property
    private var subscribers: [Token: AsyncStream<WorkflowEvent>.Continuation] = [:]
    
    var subscriberCount: Int { subscribers.count }
    
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    func subscribe() -> (Token, AsyncStream<WorkflowEvent>) {
        let token = UUID()
        let stream = AsyncStream<WorkflowEvent> { continuation in
            self.subscribers[token] = continuation
        }
        
        return (token, stream)
    }
    
    func unsubscribe(_ token: Token) {
        if let continuation = subscribers.removeValue(forKey: token) {
            continuation.finish()
        }
    }
    
    func publish(_ event: WorkflowEvent) {
        for (_, continuation) in subscribers {
            continuation.yield(event)
        }
    }
    
    // MARK: - Private
}
