//
//  RPCRequest.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct RPCRequest: Sendable {
    // MARK: - Property
    let id: String
    let method: String
    let params: [String: JSONValue]

    // MARK: - Initializer
    init(id: String, method: String, params: [String: JSONValue]) {
        self.id = id
        self.method = method
        self.params = params
    }

    // MARK: - Public
    static func decode(_ data: Data) throws -> RPCRequest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProtocolError("malformed JSON line")
        }

        let request = try JSONValue(jsonObject: object)

        guard let id = request["id"]?.stringValue, !id.isEmpty else {
            throw ProtocolError("missing or empty 'id'")
        }

        guard let method = request["method"]?.stringValue, !method.isEmpty else {
            throw ProtocolError("missing or empty 'method'")
        }

        let params = request["params"]?.objectValue ?? [:]

        return RPCRequest(id: id, method: method, params: params)
    }

    // MARK: - Private
}
