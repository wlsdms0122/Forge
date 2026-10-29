//
//  ServiceNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `service.*` methods and what each caller presents.
struct ServiceNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        supervisor: ServiceSupervisor,
        serviceBus: ServiceBus,
        workRegistry: WorkRegistry,
        configPath: String?,
        instanceHome: URL,
        configSnapshot: ConfigSnapshot
    ) {
        let run = ServiceRunMethod(supervisor: supervisor)
        let shutdown = ServiceShutdownMethod(supervisor: supervisor)
        let restart = ServiceRestartMethod(supervisor: supervisor)
        let status = ServiceStatusMethod(supervisor: supervisor, serviceBus: serviceBus)
        let reload = ServiceReloadMethod(
            supervisor: supervisor,
            configPath: configPath,
            instanceHome: instanceHome,
            configSnapshot: configSnapshot
        )
        let send = ServiceSendMethod(serviceBus: serviceBus, workRegistry: workRegistry)
        let ack = ServiceAckMethod(serviceBus: serviceBus)
        let list = ServiceListMethod(serviceBus: serviceBus)
        let register = ServiceRegisterMethod(serviceBus: serviceBus)

        self.methods = [
            RPCMethod("service.run", .unary(.operator) { request, claims in
                try await run.handle(request, claims: claims)
            }),
            RPCMethod("service.shutdown", .unary(.operator) { request, claims in
                try await shutdown.handle(request, claims: claims)
            }),
            RPCMethod("service.restart", .unary(.operator) { request, claims in
                try await restart.handle(request, claims: claims)
            }),
            RPCMethod("service.status", .unary(.token) { request, _ in
                try await status.handle(request)
            }),
            RPCMethod("service.reload", .unary(.operator) { request, claims in
                try await reload.handle(request, claims: claims)
            }),
            RPCMethod("service.send", .unary(.token) { request, claims in
                try await send.handle(request, claims: claims)
            }),
            RPCMethod("service.ack", .unary(.operator) { request, claims in
                try await ack.handle(request, claims: claims)
            }),
            RPCMethod("service.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("service.register", .streaming(.operator) { request, claims, sink in
                try await register.handle(request, claims: claims, sink: sink)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
