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
        handlerBus: WorkflowHandlerBus,
        configPath: String?,
        sessionHome: URL,
        configSnapshot: ConfigSnapshot
    ) {
        let run = ServiceRunMethod(supervisor: supervisor)
        let shutdown = ServiceShutdownMethod(supervisor: supervisor)
        let restart = ServiceRestartMethod(supervisor: supervisor)
        let status = ServiceStatusMethod(supervisor: supervisor, handlerBus: handlerBus)
        let reload = ServiceReloadMethod(
            supervisor: supervisor,
            configPath: configPath,
            sessionHome: sessionHome,
            configSnapshot: configSnapshot
        )

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
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
