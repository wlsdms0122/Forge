//
//  DispatchService.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct DispatchService: Sendable {
    typealias Handler = @Sendable (RPCRequest) async throws -> JSONObject
    typealias StreamingHandler = @Sendable (RPCRequest, any EventSink) async throws -> Void
    
    // MARK: - Property
    let handlers: [String: Handler]
    let streamingHandlers: [String: StreamingHandler]
    
    // MARK: - Initializer
    init(
        handlers: [String: Handler] = [:],
        streamingHandlers: [String: StreamingHandler] = [:]
    ) {
        self.handlers = handlers
        self.streamingHandlers = streamingHandlers
    }
    
    // MARK: - Public
    func dispatch(_ request: RPCRequest) async throws -> JSONObject {
        guard let handler = handlers[request.method] else {
            throw UnknownMethod("unknown method: \(request.method)")
        }
        
        return try await handler(request)
    }
    
    func streamingHandler(for method: String) -> StreamingHandler? {
        streamingHandlers[method]
    }
    
    func isStreaming(_ method: String) -> Bool {
        streamingHandlers[method] != nil
    }
    
    // MARK: - Private
}
