//
//  RPCResponse.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct RPCResponse: @unchecked Sendable {
    enum Payload: @unchecked Sendable {
        case result([String: Any])
        case error(wireType: String, message: String, extra: [String: Any])
    }

    // MARK: - Property
    let id: String
    let payload: Payload

    // MARK: - Initializer
    init(id: String, result: [String: Any]) {
        self.id = id
        self.payload = .result(result)
    }

    init(id: String, result: JSONObject) {
        self.id = id
        self.payload = .result(result.dict)
    }

    init(id: String, error: any Error) {
        self.id = id

        if let forgeError = error as? ForgeError {
            var extra: [String: Any] = [:]

            if let nonzeroExit = forgeError as? BackendNonzeroExit {
                extra["exit_code"] = Int(nonzeroExit.exitCode)
                extra["stderr"] = nonzeroExit.stderr
                extra["stdout"] = nonzeroExit.stdout
            }

            self.payload = .error(
                wireType: forgeError.wireType,
                message: forgeError.message,
                extra: extra
            )
        } else {
            self.payload = .error(
                wireType: "InternalError",
                message: String(describing: error),
                extra: [:]
            )
        }
    }

    // MARK: - Public
    func encode() throws -> Data {
        var object: [String: Any] = ["id": id]

        switch payload {
        case .result(let result):
            object["result"] = result

        case .error(let wireType, let message, let extra):
            var error: [String: Any] = ["type": wireType, "message": message]

            for (key, value) in extra { error[key] = value }

            object["error"] = error
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        return data + Data([0x0a])
    }

    // MARK: - Private
}
