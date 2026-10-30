//
//  JobUpdateMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct JobUpdateMethod: Sendable {
    // MARK: - Property
    let store: JobStore
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(store: JobStore, workRegistry: WorkRegistry) {
        self.store = store
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let id = request.params["id"]?.stringValue, !id.isEmpty else {
            throw ProtocolError("job.update: 'id' (string) required")
        }

        let by = claims.id

        await store.recordTouch(
            id: id,
            claims: claims,
            workRegistry: workRegistry,
            via: "job.update"
        )

        if let note = request.params["note"]?.stringValue, !note.isEmpty {
            try await store.addComment(id: id, by: by, note: note)
        }

        if let brief = request.params["brief"]?.stringValue, !brief.isEmpty {
            try await store.setBrief(id: id, by: by, brief)
        }

        if let ref = request.params["ref"]?.stringValue, !ref.isEmpty {
            let refNote = request.params["ref_note"]?.stringValue
                .flatMap { value in value.isEmpty ? nil : value }
            try await store.appendRef(id: id, by: by, ref: ref, note: refNote)
        }

        if let item = request.params["item"]?.intValue {
            let status = request.params["item_status"]?.stringValue
                .flatMap { value in value.isEmpty ? nil : value }
            let desc = request.params["item_desc"]?.stringValue
            try await store.setPlanItem(id: id, by: by, item: item, desc: desc, status: status)
        }

        if let status = request.params["status"]?.stringValue, !status.isEmpty {
            try await store.setStatus(id: id, by: by, status)
        }

        guard let job = await store.lookup(id) else {
            throw ProtocolError("job not found: \(id)")
        }

        var result: [String: JSONValue] = ["id": .string(id)]

        if let status = job.status { result["status"] = .string(status) }

        return .object(result)
    }

    // MARK: - Private
}
