//
//  RPCRequest.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct RPCRequest: @unchecked Sendable {
    // MARK: - Property
    let id: String
    let method: String
    let params: [String: JSONValue]

    // The params as Foundation's JSON objects, for the methods that read
    // them so.
    let rawParams: [String: Any]

    // MARK: - Initializer
    init(id: String, method: String, params: [String: Any]) {
        self.id = id
        self.method = method
        self.params = (try? JSONValue(jsonObject: params))?.objectValue ?? [:]
        self.rawParams = params
    }

    // MARK: - Public
    static func decode(_ data: Data) throws -> RPCRequest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProtocolError("malformed JSON line")
        }

        guard let id = object["id"] as? String, !id.isEmpty else {
            throw ProtocolError("missing or empty 'id'")
        }

        guard let method = object["method"] as? String, !method.isEmpty else {
            throw ProtocolError("missing or empty 'method'")
        }

        let params = object["params"] as? [String: Any] ?? [:]

        return RPCRequest(id: id, method: method, params: params)
    }

    // MARK: - Private
}
