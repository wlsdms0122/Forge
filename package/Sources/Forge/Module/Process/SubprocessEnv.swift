//
//  SubprocessEnv.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum SubprocessEnv {
    static func baseline() -> [String: String] {
        var environment: [String: String] = [:]
        
        if let token = WorkflowExecutionState.accessToken {
            environment["FORGE_ACCESS_TOKEN"] = token
        }
        
        for (key, value) in forgeBinEnv() { environment[key] = value }
        
        return environment
    }
    
    static func forgeBinEnv() -> [String: String] {
        let executable = executablePath()
        var environment: [String: String] = ["FORGE_BIN": executable]
        let directory = (executable as NSString).deletingLastPathComponent
        
        if !directory.isEmpty {
            let parent = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
            environment["PATH"] = "\(directory):\(parent)"
        }
        
        return environment
    }
    
    static func executablePath() -> String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }
    
    static func merge(
        baseline: [String: String],
        specOverride: [String: String]?
    ) -> [String: String]? {
        guard let specOverride, !specOverride.isEmpty else {
            return baseline.isEmpty ? nil : baseline
        }
        
        var merged = baseline
        
        for (key, value) in specOverride { merged[key] = value }
        
        return merged.isEmpty ? nil : merged
    }
}
