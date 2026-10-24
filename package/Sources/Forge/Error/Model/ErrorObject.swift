//
//  ErrorObject.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A failure as a client meets it: its type, its message and the fields it
// carries beside them. An error that is not a `ForgeError` is carried as an
// `InternalError` with the error's text.
struct ErrorObject: Sendable {
    // MARK: - Property
    let type: String
    let message: String
    let details: [String: any Sendable]

    // The object the wire carries under `error`.
    var dict: [String: Any] {
        var object: [String: Any] = ["type": type, "message": message]

        for (key, value) in details { object[key] = value }

        return object
    }

    // MARK: - Initializer
    init(_ error: any Error) {
        if let forgeError = error as? any ForgeError {
            self.type = forgeError.wireType
            self.message = forgeError.message
            self.details = forgeError.wireDetails
        } else {
            self.type = "InternalError"
            self.message = String(describing: error)
            self.details = [:]
        }
    }

    // MARK: - Public
    // MARK: - Private
}
