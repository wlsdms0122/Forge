//
//  ProcessRunState.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

final class ProcessRunState: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var resolved = false
    
    // MARK: - Initializer
    // MARK: - Public
    func complete(
        _ result: Result<SubprocessResult, any Error>,
        to continuation: CheckedContinuation<SubprocessResult, any Error>
    ) {
        lock.lock()
        
        defer { lock.unlock() }
        
        guard !resolved else { return }
        
        resolved = true
        continuation.resume(with: result)
    }
    
    // MARK: - Private
}
