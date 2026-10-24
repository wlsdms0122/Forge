//
//  SessionNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `session.*` methods and what each caller presents.
struct SessionNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        handlerBus: WorkflowHandlerBus,
        workRegistry: WorkRegistry
    ) {
        let send = SessionSendMethod(handlerBus: handlerBus, workRegistry: workRegistry)
        let ack = SessionHandlerAckMethod(handlerBus: handlerBus)
        let list = SessionListMethod(handlerBus: handlerBus)
        let register = SessionHandlerRegisterMethod(handlerBus: handlerBus)

        self.methods = [
            RPCMethod("session.send", .unary(.token) { request, claims in
                JSONObject(try await send.handle(request, claims: claims))
            }),
            RPCMethod("session.handler.ack", .unary(.operator) { request, claims in
                JSONObject(try await ack.handle(request, claims: claims))
            }),
            RPCMethod("session.list", .unary(.token) { request, _ in
                JSONObject(try await list.handle(request))
            }),
            RPCMethod("session.handler.register", .streaming(.operator) { request, claims, sink in
                try await register.handle(request, claims: claims, sink: sink)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
