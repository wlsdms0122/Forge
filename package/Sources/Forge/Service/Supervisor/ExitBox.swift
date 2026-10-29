//
//  ExitBox.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

final class ExitBox: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var code: Int32?
    private var waiter: CheckedContinuation<Int32, Never>?
    
    // MARK: - Initializer
    // MARK: - Public
    func complete(_ exitCode: Int32) {
        lock.lock()
        
        if let waiting = waiter {
            waiter = nil
            lock.unlock()
            waiting.resume(returning: exitCode)
        } else {
            code = exitCode
            lock.unlock()
        }
    }
    
    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            
            if let code {
                lock.unlock()
                continuation.resume(returning: code)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
    
    // MARK: - Private
}
