//
//  ResourceReadMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ResourceReadMethod: Sendable {
    // MARK: - Property
    let store: ResourceStore
    let tokenAuthority: TokenAuthority
    let defaultMaxBytes: Int

    // MARK: - Initializer
    init(
        store: ResourceStore,
        tokenAuthority: TokenAuthority,
        defaultMaxBytes: Int = 64 * 1024
    ) {
        self.store = store
        self.tokenAuthority = tokenAuthority
        self.defaultMaxBytes = defaultMaxBytes
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        guard let path = request.params["path"] as? String, !path.isEmpty else {
            throw ProtocolError("resource.read: 'path' (string) required")
        }

        let cap: Int

        if let maxBytes = request.params["maximum_bytes"] as? Int, maxBytes > 0 {
            cap = maxBytes
        } else {
            cap = defaultMaxBytes
        }

        let body = try await store.read(path)
        let truncated = body.utf8.count > cap
        let payload = truncated
            ? String(decoding: body.utf8.prefix(cap), as: UTF8.self) + "\n... (truncated)"
            : body

        return [
            "path": path,
            "body": payload,
            "size": body.utf8.count,
            "truncated": truncated
        ]
    }

    // MARK: - Private
}
