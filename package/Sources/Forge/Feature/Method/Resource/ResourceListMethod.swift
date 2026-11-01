//
//  ResourceListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ResourceListMethod: Sendable {
    // MARK: - Property
    let workingDirectory: WorkingDirectory

    // MARK: - Initializer
    init(workingDirectory: WorkingDirectory) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let entries = await workingDirectory.all()
        let rows: [JSONValue] = entries.map { entry in
            [
                "path": .string(entry.path),
                "size": .int(entry.size),
                "mtime": .string(ISO8601.string(entry.mtime))
            ]
        }
        
        return ["resources": .array(rows)]
    }

    // MARK: - Private
}
