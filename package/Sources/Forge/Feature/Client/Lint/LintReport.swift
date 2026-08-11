//
//  LintReport.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

extension WorkflowLint {
    package struct Report: Sendable {
        // MARK: - Property
        package let path: String
        package let readError: String?
        package let decodeError: String?
        package let issues: [String]
        
        package var ok: Bool { readError == nil && decodeError == nil && issues.isEmpty }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
}
