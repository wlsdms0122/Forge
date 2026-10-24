//
//  KeyCollision.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A key several sources hold. None of them is live.
struct KeyCollision {
    // MARK: - Property
    let key: String
    let sources: [String]
    
    // MARK: - Initializer
    // MARK: - Public
    // The failures the collision makes, one per source; the ledger records the
    // collision when the failures standing before did not hold it.
    func failures(
        kind: String,
        standing: [LoadFailure],
        recording ledger: inout LoadFailureLedger
    ) -> [LoadFailure] {
        let reason = "\(kind) '\(key)' collides across: \(sources.joined(separator: ", "))"
        
        if !standing.contains(where: { failure in failure.reason == reason }) {
            ledger.record(collision: reason)
        }
        
        return sources.map { source in
            LoadFailure(path: source, reason: reason, mtime: .distantPast)
        }
    }
    
    // MARK: - Private
}
