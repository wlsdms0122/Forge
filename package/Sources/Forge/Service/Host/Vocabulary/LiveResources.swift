//
//  LiveResources.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The live resource seam over the daemon's working directory.
struct LiveResources: ResourceReading {
    // MARK: - Property
    let workingDirectory: WorkingDirectory

    // MARK: - Initializer
    init(workingDirectory: WorkingDirectory) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public
    func read(_ path: String) async throws -> String {
        try await workingDirectory.read(path)
    }

    // A located file must exist: a path is a promise the caller will act on
    // (usually exec), and a dangling one fails here, at the resource seam,
    // not as a confusing spawn error downstream.
    func locate(_ path: String) async throws -> String {
        try await workingDirectory.resolve(path).path
    }

    // MARK: - Private
}
