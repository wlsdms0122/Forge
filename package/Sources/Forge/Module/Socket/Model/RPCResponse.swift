//
//  RPCResponse.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct RPCResponse: Sendable {
    enum Payload: Sendable {
        case result(JSONValue)
        case error(ErrorObject)
    }

    // MARK: - Property
    let id: String
    let payload: Payload

    // MARK: - Initializer
    init(id: String, result: JSONValue) {
        self.id = id
        self.payload = .result(result)
    }

    init(id: String, error: any Error) {
        self.id = id
        self.payload = .error(ErrorObject(error))
    }

    // MARK: - Public
    func encode() throws -> Data {
        var object: [String: Any] = ["id": id]

        switch payload {
        case let .result(result):
            object["result"] = result.jsonObject

        case let .error(error):
            object["error"] = error.jsonValue.jsonObject
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        return data + Data([0x0a])
    }

    // MARK: - Private
}
