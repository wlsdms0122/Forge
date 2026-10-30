//
//  LiveResources.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The live resource seam over the daemon's document root.
struct LiveResources: ResourceReading {
    // MARK: - Property
    let root: DocumentRoot

    // MARK: - Initializer
    init(root: DocumentRoot) {
        self.root = root
    }

    // MARK: - Public
    func read(_ relative: String) async throws -> String {
        try await root.read(relative)
    }

    // A located file must exist: a path is a promise the caller will act on
    // (usually exec), and a dangling one fails here, at the resource seam,
    // not as a confusing spawn error downstream.
    func locate(_ relative: String) async throws -> String {
        let url = try await root.resolve(relative)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ResourceError("resource '\(relative)' does not exist")
        }

        return url.path
    }

    // MARK: - Private
}
