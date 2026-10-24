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
    let tokenAuthority: TokenAuthority
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(store: JobStore, tokenAuthority: TokenAuthority, workRegistry: WorkRegistry) {
        self.store = store
        self.tokenAuthority = tokenAuthority
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)
        let id = try requireID(request.params, "job.update")
        let by = claims.id

        await recordTouchIfLiveRun(
            claims,
            store: store,
            workRegistry: workRegistry,
            id: id,
            via: "job.update"
        )

        if let note = request.params["note"] as? String, !note.isEmpty {
            try await store.addComment(id: id, by: by, note: note)
        }

        if let brief = request.params["brief"] as? String, !brief.isEmpty {
            try await store.setBrief(id: id, by: by, brief)
        }

        if let ref = request.params["ref"] as? String, !ref.isEmpty {
            let refNote = (request.params["ref_note"] as? String)
                .flatMap { value in value.isEmpty ? nil : value }
            try await store.appendRef(id: id, by: by, ref: ref, note: refNote)
        }

        if let item = intParam(request.params, "item") {
            let status = (request.params["item_status"] as? String)
                .flatMap { value in value.isEmpty ? nil : value } ?? "done"
            let desc = request.params["item_desc"] as? String
            try await store.setPlanItem(id: id, by: by, item: item, desc: desc, status: status)
        }

        if let status = request.params["status"] as? String, !status.isEmpty {
            try await store.setStatus(id: id, by: by, status)
        }

        guard let job = await store.lookup(id) else {
            throw ProtocolError("job not found: \(id)")
        }

        return ["id": id, "status": job.status]
    }

    // MARK: - Private
}
