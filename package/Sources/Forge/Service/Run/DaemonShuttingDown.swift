//
//  DaemonShuttingDown.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The daemon is draining for shutdown and starts no new run or service.
struct DaemonShuttingDown: ForgeError {
    // MARK: - Property
    let message: String
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
