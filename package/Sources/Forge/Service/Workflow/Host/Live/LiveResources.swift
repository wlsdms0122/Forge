//
//  LiveResources.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The live resource seam — the same jailed catalog the daemon watches.
struct LiveResources: ResourceReading {
    // MARK: - Property
    let store: ResourceStore

    // MARK: - Initializer
    init(store: ResourceStore) {
        self.store = store
    }

    // MARK: - Public
    func read(_ relative: String) async throws -> String {
        try await store.read(relative)
    }

    // A located file must exist — a path is a promise the caller will act on
    // (usually exec), and a dangling one should fail here, at the resource
    // seam, not as a confusing spawn error downstream.
    func locate(_ relative: String) async throws -> String {
        let url = try await store.resolve(relative)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Warp.ExecutionError("resource '\(relative)' does not exist")
        }

        return url.path
    }

    // MARK: - Private
}
