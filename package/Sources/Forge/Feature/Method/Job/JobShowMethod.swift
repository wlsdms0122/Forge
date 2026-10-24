//
//  JobShowMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

private func jobToAny(_ job: Job) -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    guard let data = try? encoder.encode(job),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return ["id": job.id]
    }

    return object
}

func requireID(_ params: [String: Any], _ context: String) throws -> String {
    guard let id = params["id"] as? String, !id.isEmpty else {
        throw ProtocolError("\(context): 'id' (string) required")
    }

    return id
}

func recordTouchIfLiveRun(
    _ claims: TokenClaims,
    store: JobStore,
    workRegistry: WorkRegistry,
    id: String,
    via: String
) async {
    guard let workflowID = claims.workflowID,
        await workRegistry.beginTouch(workflowID: workflowID)
    else {
        return
    }

    await store.recordTouch(id: id, run: claims.id, via: via)
    await workRegistry.endTouch(workflowID: workflowID)
}

struct JobShowMethod: Sendable {
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
        let id = try requireID(request.params, "job.show")

        guard let job = await store.lookup(id) else {
            throw ProtocolError("job not found: \(id)")
        }

        await recordTouchIfLiveRun(
            claims,
            store: store,
            workRegistry: workRegistry,
            id: id,
            via: "job.show"
        )

        var dictionary = jobToAny(job)
        dictionary["open"] = job.isOpen(excluding: claims.id)

        if !job.children.isEmpty {
            var detail: [[String: Any]] = []

            for childID in job.children {
                if let child = await store.lookup(childID) {
                    detail.append(["id": child.id, "title": child.title, "status": child.status])
                } else {
                    detail.append(["id": childID, "status": "missing"])
                }
            }

            dictionary["children_detail"] = detail
        }

        return ["job": dictionary]
    }

    // MARK: - Private
}
