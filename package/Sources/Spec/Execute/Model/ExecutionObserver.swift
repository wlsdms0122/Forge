//
//  ExecutionObserver.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public protocol ExecutionObserver: Sendable {
    func stepStarted(id: String, action: String) async
    func stepSkipped(id: String) async
    func stepCompleted(id: String, output: Value, rescued: Bool) async
    func stepFailed(id: String, error: any Error) async
}

public extension ExecutionObserver {
    func stepStarted(id: String, action: String) async {
    }

    func stepSkipped(id: String) async {
    }

    func stepCompleted(id: String, output: Value, rescued: Bool) async {
    }

    func stepFailed(id: String, error: any Error) async {
    }
}
