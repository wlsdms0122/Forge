//
//  ServiceHandle.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

actor ServiceHandle {
    // MARK: - Property
    let service: String
    let schema: JSONValue?
    
    private let sink: any EventSink
    
    private var pending: [String: CheckedContinuation<JSONValue, any Error>] = [:]
    
    // MARK: - Initializer
    init(service: String, schema: JSONValue?, sink: any EventSink) {
        self.service = service
        self.schema = schema
        self.sink = sink
    }
    
    // MARK: - Public
    func send(
        envelope: HandlerFrameEnvelope,
        payload: JSONValue,
        isAsync: Bool = false
    ) async throws -> JSONValue {
        let messageID = "m-\(UUID().uuidString.prefix(12))"
        
        var envelopeObject: [String: JSONValue] = [
            "workflow_id": .string(envelope.runID),
            "origin": envelope.origin.jsonValue
        ]
        
        if let rootID = envelope.rootID { envelopeObject["root_id"] = .string(rootID) }
        if let nodeID = envelope.nodeID { envelopeObject["id"] = .string(nodeID) }
        if let correlator = envelope.correlator { envelopeObject["correlator"] = .string(correlator) }
        
        let frame: JSONValue = [
            "kind": "handler.message",
            "service": .string(service),
            "message_id": .string(messageID),
            "envelope": .object(envelopeObject),
            "payload": payload
        ]
        
        if isAsync {
            await sink.emit(frame)
            
            return [
                "service": .string(service),
                "message_id": .string(messageID),
                "status": "dispatched"
            ]
        }
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<JSONValue, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    
                    return
                }
                
                pending[messageID] = continuation
                
                Task { await sink.emit(frame) }
            }
        } onCancel: {
            Task { [self] in await self.cancelPending(messageID: messageID) }
        }
    }
    
    func deliverResult(messageID: String, result: JSONValue) {
        guard let continuation = pending.removeValue(forKey: messageID) else { return }
        
        continuation.resume(returning: result)
    }
    
    func deliverError(messageID: String, message: String) {
        guard let continuation = pending.removeValue(forKey: messageID) else { return }
        
        continuation.resume(throwing: HandlerFailed(message))
    }
    
    func cancelAll() {
        for (_, continuation) in pending {
            continuation.resume(throwing: CancellationError())
        }
        
        pending.removeAll()
    }
    
    // MARK: - Private
    private func cancelPending(messageID: String) {
        guard let continuation = pending.removeValue(forKey: messageID) else { return }
        
        continuation.resume(throwing: CancellationError())
    }
}
