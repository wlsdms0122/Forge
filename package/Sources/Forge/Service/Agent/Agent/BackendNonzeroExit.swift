//
//  BackendNonzeroExit.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct BackendNonzeroExit: BackendError, WorkFailure {
    // MARK: - Property
    let message: String
    let exitCode: Int32
    let stderr: String
    let stdout: String

    var wireDetails: [String: Any] {
        [
            "exit_code": Int(exitCode),
            "stderr": stderr,
            "stdout": stdout
        ]
    }

    // MARK: - Initializer
    init(_ message: String, exitCode: Int32, stderr: String = "", stdout: String = "") {
        self.message = message
        self.exitCode = exitCode
        self.stderr = stderr
        self.stdout = stdout
    }

    // MARK: - Public
    // MARK: - Private
}
