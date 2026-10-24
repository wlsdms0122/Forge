//
//  HandlerNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `handler.*` methods and what each caller presents.
struct HandlerNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        handlerBus: WorkflowHandlerBus,
        workRegistry: WorkRegistry
    ) {
        let send = HandlerSendMethod(handlerBus: handlerBus, workRegistry: workRegistry)
        let ack = HandlerAckMethod(handlerBus: handlerBus)
        let list = HandlerListMethod(handlerBus: handlerBus)
        let register = HandlerRegisterMethod(handlerBus: handlerBus)

        self.methods = [
            RPCMethod("handler.send", .unary(.token) { request, claims in
                try await send.handle(request, claims: claims)
            }),
            RPCMethod("handler.ack", .unary(.operator) { request, claims in
                try await ack.handle(request, claims: claims)
            }),
            RPCMethod("handler.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("handler.register", .streaming(.operator) { request, claims, sink in
                try await register.handle(request, claims: claims, sink: sink)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
