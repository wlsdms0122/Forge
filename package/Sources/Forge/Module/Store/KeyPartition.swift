//
//  KeyPartition.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// Candidates split by key: a key one source holds is live, a key several
// sources hold is a collision.
struct KeyPartition<Value> {
    // MARK: - Property
    let live: [String: Value]
    let collisions: [KeyCollision]
    
    // MARK: - Initializer
    init(_ candidates: [(key: String, source: String, value: Value)]) {
        var grouped: [String: [(source: String, value: Value)]] = [:]
        
        for candidate in candidates {
            grouped[candidate.key, default: []]
                .append((source: candidate.source, value: candidate.value))
        }
        
        var live: [String: Value] = [:]
        var collisions: [KeyCollision] = []
        
        for (key, group) in grouped {
            if group.count == 1 {
                live[key] = group[0].value
            } else {
                collisions.append(KeyCollision(key: key, sources: group.map(\.source).sorted()))
            }
        }
        
        self.live = live
        self.collisions = collisions
    }
    
    // MARK: - Public
    // MARK: - Private
}
