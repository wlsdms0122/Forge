//
//  WorkflowHandlerBusTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowHandlerBus Tests")
struct WorkflowHandlerBusTests {
    private final class AckDuringEmitSink: EventSink, @unchecked Sendable {
        var handle: ServiceHandle?
        func emit(_ frame: JSONValue) async {
            let messageID = frame["message_id"]?.stringValue ?? ""
            await handle?.deliverResult(messageID: messageID, result: ["ok": true])
        }
    }
    
    private final class NoopSink: EventSink, @unchecked Sendable {
        func emit(_ frame: JSONValue) async {}
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A fast ack arriving during emit is not dropped")
    func fastAckDuringEmitNotDropped() async {
        // Given
        let sink = AckDuringEmitSink()
        let bus = WorkflowHandlerBus()
        let handle = await bus.register(service: "svc", schema: nil, sink: sink)
        sink.handle = handle
        let env = HandlerFrameEnvelope(workflowID: "w", origin: .manual,
            rootID: nil, nodeID: nil, correlator: nil)
        let result: JSONValue? = await withTaskGroup(of: JSONValue?.self) { group in
            group.addTask { try? await handle.send(envelope: env, payload: [:]) }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            
            return first
        }

        // Then
        #expect(result != nil, "A fast ack arriving during emit was dropped, hanging send (finding A)")
        #expect(result?["ok"]?.boolValue == true)
    }
    
    @Test("A late unregister does not evict the new owner's handle")
    func lateUnregisterDoesNotEvictTakeoverHandle() async {
        // Given
        let bus = WorkflowHandlerBus()

        // When
        let handleA = await bus.register(service: "svc", schema: nil, sink: NoopSink())
        let handleB = await bus.register(service: "svc", schema: nil, sink: NoopSink())
        await bus.unregister(service: "svc", handle: handleA)
        let current = await bus.handle(service: "svc")

        // Then
        #expect(current != nil, "After takeover, the old EOF removed the live new handle (finding F)")
        #expect(current === handleB, "The current handle should be B")
    }
    
    @Test("A registration is removed by its own unregister")
    func ownUnregisterRemoves() async {
        // Given
        let bus = WorkflowHandlerBus()

        // When
        let handle = await bus.register(service: "svc", schema: nil, sink: NoopSink())
        await bus.unregister(service: "svc", handle: handle)
        let current = await bus.handle(service: "svc")

        // Then
        #expect(current == nil, "A normal unregister should remove it")
    }
    
    // MARK: - Private
}
