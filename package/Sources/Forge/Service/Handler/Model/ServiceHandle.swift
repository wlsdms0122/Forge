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
    let schema: JSONObject?
    
    private let sink: any EventSink
    
    private var pending: [String: CheckedContinuation<JSONObject, any Error>] = [:]
    
    // MARK: - Initializer
    init(service: String, schema: JSONObject?, sink: any EventSink) {
        self.service = service
        self.schema = schema
        self.sink = sink
    }
    
    // MARK: - Public
    func send(
        envelope: HandlerFrameEnvelope,
        payload: JSONObject,
        isAsync: Bool = false
    ) async throws -> JSONObject {
        let messageID = "m-\(UUID().uuidString.prefix(12))"
        
        var envelopeDict: [String: Any] = [
            "workflow_id": envelope.workflowID,
            "origin": envelope.originDict
        ]
        
        if let rootID = envelope.rootID { envelopeDict["root_id"] = rootID }
        if let nodeID = envelope.nodeID { envelopeDict["id"] = nodeID }
        if let correlator = envelope.correlator { envelopeDict["correlator"] = correlator }
        
        let frame = JSONObject([
            "kind": "session.message",
            "service": service,
            "message_id": messageID,
            "envelope": envelopeDict,
            "payload": payload.dict
        ])
        
        if isAsync {
            await sink.emit(frame)
            
            return JSONObject([
                "service": service,
                "message_id": messageID,
                "status": "dispatched"
            ])
        }
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<JSONObject, any Error>) in
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
    
    func deliverResult(messageID: String, result: JSONObject) {
        guard let continuation = pending.removeValue(forKey: messageID) else { return }
        
        continuation.resume(returning: result)
    }
    
    func deliverError(messageID: String, message: String) {
        guard let continuation = pending.removeValue(forKey: messageID) else { return }
        
        continuation.resume(throwing: ProtocolError(message))
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
