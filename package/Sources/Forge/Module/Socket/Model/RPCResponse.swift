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
        case error(ErrorObject)
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
        self.payload = .error(ErrorObject(error))
    }

    // MARK: - Public
    func encode() throws -> Data {
        var object: [String: Any] = ["id": id]

        switch payload {
        case .result(let result):
            object["result"] = result

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
