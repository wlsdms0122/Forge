//
//  WorkflowNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `workflow.*` methods and what each caller presents.
struct WorkflowNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        runner: WorkflowRunner,
        catalog: WorkflowCatalog,
        workRegistry: WorkRegistry,
        pool: WorkflowPool,
        policyStore: PolicyStore,
        eventBus: WorkflowEventBus
    ) {
        let dispatch = WorkflowDispatchMethod(runner: runner, store: catalog, workRegistry: workRegistry)
        let dispatchStream = WorkflowDispatchStreamMethod(dispatchMethod: dispatch, eventBus: eventBus)
        let list = WorkflowListMethod(store: catalog)
        let describe = WorkflowDescribeMethod(store: catalog)
        let listActive = WorkflowListActiveMethod(pool: pool)
        let health = WorkflowHealthMethod(pool: pool)
        let cancel = WorkflowCancelMethod(pool: pool, policyStore: policyStore)

        self.methods = [
            RPCMethod("workflow.dispatch", .unary(.token) { request, claims in
                try await dispatch.handle(request, claims: claims)
            }),
            RPCMethod("workflow.dispatch_stream", .streaming(.token) { request, claims, sink in
                try await dispatchStream.handle(request, claims: claims, sink: sink)
            }),
            RPCMethod("workflow.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("workflow.describe", .unary(.token) { request, _ in
                try await describe.handle(request)
            }),
            RPCMethod("workflow.list_active", .unary(.token) { request, _ in
                try await listActive.handle(request)
            }),
            RPCMethod("workflow.health", .unary(.token) { request, _ in
                try await health.handle(request)
            }),
            RPCMethod("workflow.cancel", .unary(.token) { request, claims in
                try await cancel.handle(request, claims: claims)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
