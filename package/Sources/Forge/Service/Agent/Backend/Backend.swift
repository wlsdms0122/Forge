//
//  Backend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol Backend: Sendable {
    func invoke(_ invocation: Invocation) async throws -> BackendResponse
    func openSession() -> any BackendSession
}

extension Backend {
    func openSession() -> any BackendSession { NoSession() }
}
