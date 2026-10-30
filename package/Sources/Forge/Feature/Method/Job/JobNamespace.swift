//
//  JobNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `job.*` methods and what each caller presents.
struct JobNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        store: JobStore,
        workRegistry: WorkRegistry
    ) {
        let create = JobCreateMethod(store: store)
        let show = JobShowMethod(store: store, workRegistry: workRegistry)
        let list = JobListMethod(store: store)
        let update = JobUpdateMethod(store: store, workRegistry: workRegistry)
        let delete = JobDeleteMethod(store: store)

        self.methods = [
            RPCMethod("job.create", .unary(.token) { request, claims in
                try await create.handle(request, claims: claims)
            }),
            RPCMethod("job.show", .unary(.token) { request, claims in
                try await show.handle(request, claims: claims)
            }),
            RPCMethod("job.list", .unary(.token) { request, claims in
                try await list.handle(request, claims: claims)
            }),
            RPCMethod("job.update", .unary(.token) { request, claims in
                try await update.handle(request, claims: claims)
            }),
            RPCMethod("job.delete", .unary(.token) { request, _ in
                try await delete.handle(request)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
