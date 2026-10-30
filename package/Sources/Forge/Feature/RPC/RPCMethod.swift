//
//  RPCMethod.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A row of an RPC table: a method's name, what its caller presents, and the
// handler that answers it.
struct RPCMethod: Sendable {
    // What a caller presents to call a method that is not open.
    enum Access: Sendable {
        // A token this daemon minted.
        case token
        // A token this daemon minted for anyone but a run.
        case `operator`
    }

    enum Handler: Sendable {
        case open(@Sendable (RPCRequest) async throws -> JSONValue)
        case unary(Access, @Sendable (RPCRequest, TokenClaims) async throws -> JSONValue)
        case streaming(
            Access,
            @Sendable (RPCRequest, TokenClaims, any EventSink) async throws -> Void
        )
    }

    // MARK: - Property
    let name: String
    let handler: Handler

    // MARK: - Initializer
    init(_ name: String, _ handler: Handler) {
        self.name = name
        self.handler = handler
    }

    // MARK: - Public
    // MARK: - Private
}
