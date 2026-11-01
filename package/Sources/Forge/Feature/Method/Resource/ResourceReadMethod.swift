//
//  ResourceReadMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ResourceReadMethod: Sendable {
    // MARK: - Property
    let workingDirectory: WorkingDirectory
    let defaultMaxBytes: Int

    // MARK: - Initializer
    init(
        workingDirectory: WorkingDirectory,
        defaultMaxBytes: Int = 64 * 1024
    ) {
        self.workingDirectory = workingDirectory
        self.defaultMaxBytes = defaultMaxBytes
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let path = request.params["path"]?.stringValue, !path.isEmpty else {
            throw ProtocolError("resource.read: 'path' (string) required")
        }

        let cap: Int

        if let maxBytes = request.params["maximum_bytes"]?.intValue, maxBytes > 0 {
            cap = maxBytes
        } else {
            cap = defaultMaxBytes
        }

        let body = try await workingDirectory.read(path)
        let truncated = body.utf8.count > cap
        let payload = truncated
            ? String(decoding: body.utf8.prefix(cap), as: UTF8.self) + "\n... (truncated)"
            : body

        return [
            "path": .string(path),
            "body": .string(payload),
            "size": .int(body.utf8.count),
            "truncated": .bool(truncated)
        ]
    }

    // MARK: - Private
}
