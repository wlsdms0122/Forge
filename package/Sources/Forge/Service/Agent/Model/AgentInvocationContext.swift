//
//  AgentInvocationContext.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

final class AgentInvocationContext: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var recordedModelReference: ModelReference?
    
    var modelReference: ModelReference? {
        lock.lock()
        
        defer { lock.unlock() }
        
        return recordedModelReference
    }
    
    // MARK: - Initializer
    // MARK: - Public
    func record(modelReference: ModelReference) {
        lock.lock()
        
        defer { lock.unlock() }
        
        recordedModelReference = modelReference
    }
    
    // MARK: - Private
}
