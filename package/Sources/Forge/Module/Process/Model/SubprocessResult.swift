//
//  SubprocessResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct SubprocessResult: Sendable {
    // MARK: - Property
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let stdoutData: Data

    // MARK: - Initializer
    init(exitCode: Int32, stdoutData: Data, stderr: String) {
        self.exitCode = exitCode
        self.stdoutData = stdoutData
        self.stdout = String(decoding: stdoutData, as: UTF8.self)
        self.stderr = stderr
    }

    // MARK: - Public
    // MARK: - Private
}
