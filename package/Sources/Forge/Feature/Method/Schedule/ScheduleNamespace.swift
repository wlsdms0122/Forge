//
//  ScheduleNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `schedule.*` methods and what each caller presents.
struct ScheduleNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        store: ScheduleStore,
        ledger: FireLedger,
        catalog: WorkflowCatalog,
        policyStore: PolicyStore
    ) {
        let list = ScheduleListMethod(store: store, ledger: ledger)
        let setEnabled = ScheduleSetEnabledMethod(store: store, policyStore: policyStore)
        let create = ScheduleCreateMethod(store: store, workflowStore: catalog, policyStore: policyStore)
        let delete = ScheduleDeleteMethod(store: store, policyStore: policyStore)

        self.methods = [
            RPCMethod("schedule.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("schedule.set_enabled", .unary(.token) { request, claims in
                try await setEnabled.handle(request, claims: claims)
            }),
            RPCMethod("schedule.create", .unary(.token) { request, claims in
                try await create.handle(request, claims: claims)
            }),
            RPCMethod("schedule.delete", .unary(.token) { request, claims in
                try await delete.handle(request, claims: claims)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
