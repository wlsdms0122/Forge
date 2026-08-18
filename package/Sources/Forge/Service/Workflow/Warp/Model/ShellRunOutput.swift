//
//  ShellRunOutput.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ShellRunOutput: Sendable {
    // MARK: - Property
    let exitCode: Int32
    let stdout: String
    let stderr: String

    // MARK: - Initializer
    init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    // MARK: - Public
    // MARK: - Private
}
