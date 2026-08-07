//
//  KeyCollision.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

func collisionFailures(
    kind: String,
    _ collided: [(key: String, sources: [String])]
) -> [LoadFailure] {
    var failures: [LoadFailure] = []
    
    for collision in collided {
        let reason = "\(kind) '\(collision.key)' collides across: \(collision.sources.joined(separator: ", "))"
        failures += collision.sources.map { source in
            LoadFailure(path: source, reason: reason, mtime: .distantPast)
        }
        
        FileHandle.standardError.write(Data("forge: \(reason)\n".utf8))
    }
    
    return failures
}

func partitionUniqueKeys<Value>(
    _ candidates: [(key: String, source: String, value: Value)]
) -> (live: [String: Value], collided: [(key: String, sources: [String])]) {
    var grouped: [String: [(source: String, value: Value)]] = [:]
    
    for candidate in candidates {
        grouped[candidate.key, default: []]
            .append((source: candidate.source, value: candidate.value))
    }
    
    var live: [String: Value] = [:]
    var collided: [(key: String, sources: [String])] = []
    
    for (key, group) in grouped {
        if group.count == 1 {
            live[key] = group[0].value
        } else {
            collided.append((key: key, sources: group.map(\.source).sorted()))
        }
    }
    
    return (live, collided)
}
