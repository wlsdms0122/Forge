//
//  LogContext.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum LogContext {
    // MARK: - Property
    @TaskLocal static var rootID: String?
    @TaskLocal static var nodeID: String?
    @TaskLocal static var parentNodeID: String?
    @TaskLocal static var parentRunID: String?
    @TaskLocal static var asyncDispatch: Bool?
    @TaskLocal static var parameters: [String: JSONValue]?
    @TaskLocal static var workflowContext: WorkflowExecutionContext?
    
    // MARK: - Initializer
    // MARK: - Public
    static func startRoot<T>(
        body: sending () async throws -> T
    ) async rethrows -> T {
        let root = newRootID()
        
        return try await $rootID.withValue(root) {
            try await $nodeID.withValue(root) {
                try await $parentNodeID.withValue(nil) {
                    try await body()
                }
            }
        }
    }
    
    static func adoptRoot<T>(
        rootID: String?,
        parentNodeID parent: String?,
        body: sending () async throws -> T
    ) async rethrows -> T {
        guard let rootID else {
            return try await startRoot(body: body)
        }
        
        let ownNode = newNodeID()
        
        return try await $rootID.withValue(rootID) {
            try await $nodeID.withValue(ownNode) {
                try await $parentNodeID.withValue(parent) {
                    try await body()
                }
            }
        }
    }
    
    static func adoptRun<T>(
        runID: String,
        parentRootID: String?,
        parentNodeID parent: String?,
        parentRunID parentRun: String? = nil,
        body: sending () async throws -> T
    ) async rethrows -> T {
        let rootID = parentRootID ?? runID
        
        return try await $rootID.withValue(rootID) {
            try await $nodeID.withValue(runID) {
                try await $parentNodeID.withValue(parentRootID == nil ? nil : parent) {
                    try await $parentRunID.withValue(parentRootID == nil ? nil : parentRun) {
                        try await body()
                    }
                }
            }
        }
    }
    
    static func childNode<T>(
        body: sending () async throws -> T
    ) async rethrows -> T {
        let new = newNodeID()
        let parent = nodeID
        
        return try await $nodeID.withValue(new) {
            try await $parentNodeID.withValue(parent) {
                try await body()
            }
        }
    }
    
    static func newRootID() -> String {
        "t-\(randomHex(12))"
    }
    
    static func newNodeID() -> String {
        "s-\(randomHex(10))"
    }
    
    // MARK: - Private
    private static func randomHex(_ count: Int) -> String {
        let bytes = (0..<count / 2).map { _ in UInt8.random(in: 0...255) }
        
        return bytes.map { byte in String(format: "%02x", byte) }.joined()
    }
}
