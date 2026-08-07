//
//  ScheduleIDSpace.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum ScheduleIDSpace {
    // MARK: - Property
    static let runtimePrefix = "rt."
    
    // MARK: - Initializer
    // MARK: - Public
    static func isRuntime(_ id: String) -> Bool { id.hasPrefix(runtimePrefix) }
    
    static func stamp(_ id: String) -> String { isRuntime(id) ? id : runtimePrefix + id }
    
    static func violation(id: String, runtime: Bool) -> String? {
        switch (runtime, isRuntime(id)) {
        case (true, false):
            "runtime schedule id must start with '\(runtimePrefix)' — the runtime id space is reserved so a runtime declaration can never collide with a config one"
        
        case (false, true):
            "'\(runtimePrefix)' is reserved for runtime-created schedules — rename this config declaration"
        
        default:
            nil
        }
    }
    
    // MARK: - Private
}
