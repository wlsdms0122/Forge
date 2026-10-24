//
//  RPCRouter.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct RPCRouter: Sendable {
    typealias StreamingHandler = @Sendable (RPCRequest, any EventSink) async throws -> Void
    
    // MARK: - Property
    let methods: [String: RPCMethod]
    let authority: TokenAuthority
    
    // MARK: - Initializer
    init(methods: [RPCMethod], authority: TokenAuthority) {
        self.methods = Dictionary(uniqueKeysWithValues: methods.map { method in (method.name, method) })
        self.authority = authority
    }
    
    // MARK: - Public
    func dispatch(_ request: RPCRequest) async throws -> JSONValue {
        switch methods[request.method]?.handler {
        case let .open(handle):
            return try await handle(request)
        
        case let .unary(access, handle):
            return try await handle(request, try claims(of: request, access: access))
        
        case .streaming, nil:
            throw UnknownMethod("unknown method: \(request.method)")
        }
    }
    
    func streamingHandler(for method: String) -> StreamingHandler? {
        guard case let .streaming(access, handle) = methods[method]?.handler else { return nil }
        
        return { request, sink in
            try await handle(request, try claims(of: request, access: access), sink)
        }
    }
    
    // MARK: - Private
    private func claims(of request: RPCRequest, access: RPCMethod.Access) throws -> TokenClaims {
        guard let token = request.params["token"]?.stringValue, !token.isEmpty else {
            throw ProtocolError("'token' (string) required — issue one with `forge token issue`")
        }
        
        guard let claims = authority.verify(token) else {
            throw TokenRejected(
                "token verification failed — signature does not match this daemon's seed"
                    + " (reissue required)"
            )
        }
        
        if case .operator = access, claims.principal.hasPrefix("cli:") {
            throw ProtocolError(
                "\(request.method): a workflow subprocess token cannot perform this operator action"
                    + " — use an operator/service token"
            )
        }
        
        return claims
    }
}
