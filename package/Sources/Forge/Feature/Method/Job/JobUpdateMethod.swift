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
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONObject {
        let id = try requireID(request.rawParams, "job.update")
        let by = claims.id

        await recordTouchIfLiveRun(
            claims,
            store: store,
            workRegistry: workRegistry,
            id: id,
            via: "job.update"
        )

        if let note = request.rawParams["note"] as? String, !note.isEmpty {
            try await store.addComment(id: id, by: by, note: note)
        }

        if let brief = request.rawParams["brief"] as? String, !brief.isEmpty {
            try await store.setBrief(id: id, by: by, brief)
        }

        if let ref = request.rawParams["ref"] as? String, !ref.isEmpty {
            let refNote = (request.rawParams["ref_note"] as? String)
                .flatMap { value in value.isEmpty ? nil : value }
            try await store.appendRef(id: id, by: by, ref: ref, note: refNote)
        }

        if let item = intParam(request.rawParams, "item") {
            let status = (request.rawParams["item_status"] as? String)
                .flatMap { value in value.isEmpty ? nil : value } ?? "done"
            let desc = request.rawParams["item_desc"] as? String
            try await store.setPlanItem(id: id, by: by, item: item, desc: desc, status: status)
        }

        if let status = request.rawParams["status"] as? String, !status.isEmpty {
            try await store.setStatus(id: id, by: by, status)
        }

        guard let job = await store.lookup(id) else {
            throw ProtocolError("job not found: \(id)")
        }

        return ["id": id, "status": job.status]
    }

    // MARK: - Private
}
