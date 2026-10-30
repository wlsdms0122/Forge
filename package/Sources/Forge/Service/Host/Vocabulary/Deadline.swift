//
//  Deadline.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Warp

// The time a step's body may take. A body still running at the deadline is
// cancelled and the step fails with DeadlineExceeded; without seconds the
// body runs unbounded.
struct Deadline {
    // MARK: - Property
    let seconds: Double?
    
    // MARK: - Initializer
    // MARK: - Public
    func run<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let seconds else { return try await body() }
        
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await body()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                
                throw DeadlineExceeded(seconds: seconds)
            }
            
            guard let first = try await group.next() else {
                throw ExecutionError("deadline group finished without a result")
            }
            
            group.cancelAll()
            
            return first
        }
    }
    
    // MARK: - Private
}
