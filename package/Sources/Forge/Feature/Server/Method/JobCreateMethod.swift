//
//  JobCreateMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

func intParam(_ params: [String: Any], _ key: String) -> Int? {
    if let integer = params[key] as? Int { return integer }
    if let number = params[key] as? NSNumber { return number.intValue }

    return nil
}

struct JobCreateMethod: Sendable {
    // MARK: - Property
    let store: JobStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: JobStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)

        guard let title = request.params["title"] as? String, !title.isEmpty else {
            throw ProtocolError("job.create: 'title' (string) required")
        }

        let now = ISO8601.string(Date())

        var origin: [String: JSONValue]?

        if let rawOrigin = request.params["origin"] as? [String: Any] {
            origin = try decodeJSONValueDict(rawOrigin)
        }

        let brief = (request.params["brief"] as? String) ?? ""

        var refs: [Job.Ref] = []

        if let rawRefs = request.params["refs"] as? [Any] {
            refs = try rawRefs.enumerated().map { index, item in
                if let string = item as? String { return Job.Ref(ref: string) }

                guard let dictionary = item as? [String: Any],
                    let ref = dictionary["ref"] as? String, !ref.isEmpty
                else {
                    throw ProtocolError("job.create: refs[\(index)] needs 'ref' (string) — shape: {\"ref\":\"...\",\"note\"?:\"...\"} or a plain string")
                }

                return Job.Ref(ref: ref, note: dictionary["note"] as? String)
            }
        } else if request.params["refs"] != nil {
            throw ProtocolError("job.create: 'refs' must be a JSON array of {ref,note?} objects or strings")
        }

        var planEntries: [Job.Plan.Entry] = []

        if let rawPlan = request.params["plan"] as? [Any] {
            for (index, item) in rawPlan.enumerated() {
                if let string = item as? String {
                    planEntries.append(.auto(desc: string, status: "todo"))

                    continue
                }

                guard let dictionary = item as? [String: Any] else {
                    throw ProtocolError("job.create: plan[\(index)] must be {\"id\"?:int,\"desc\":\"...\",\"status\"?:\"...\"} or a plain string")
                }

                guard let desc = dictionary["desc"] as? String, !desc.isEmpty else {
                    throw ProtocolError("job.create: plan[\(index)] needs 'desc' (string)")
                }

                var itemID = intParam(dictionary, "id")

                if itemID == nil, let string = dictionary["id"] as? String { itemID = Int(string) }
                if itemID == nil, dictionary["id"] != nil {
                    throw ProtocolError("job.create: plan[\(index)].id must be an integer — omit it to auto-number")
                }

                let status = (dictionary["status"] as? String) ?? "todo"

                if let itemID {
                    planEntries.append(
                        .explicit(Job.PlanItem(id: itemID, desc: desc, status: status))
                    )
                } else {
                    planEntries.append(.auto(desc: desc, status: status))
                }
            }
        } else if request.params["plan"] != nil {
            throw ProtocolError("job.create: 'plan' must be a JSON array of {id?,desc,status?} objects or strings")
        }

        let plan: Job.Plan

        do {
            plan = try Job.Plan(entries: planEntries)
        } catch let error as Job.Plan.DuplicateID {
            throw ProtocolError("job.create: \(error.message)")
        }

        let parentJob = (request.params["parent_job"] as? String)
            .flatMap { value in value.isEmpty ? nil : value }

        if let parentJob, await store.lookup(parentJob) == nil {
            throw ProtocolError("job.create: parent job not found: '\(parentJob)'")
        }

        let status = (request.params["status"] as? String)
            .flatMap { value in value.isEmpty ? nil : value } ?? "open"

        let id: String

        if let given = request.params["id"] as? String, !given.isEmpty {
            id = given
        } else {
            id = "j-" + UUID().uuidString.prefix(8).lowercased()
        }

        let job = Job(
            id: id,
            title: title,
            status: status,
            origin: origin,
            parentJob: parentJob,
            brief: brief,
            refs: refs,
            plan: plan,
            createdBy: claims.id,
            updatedBy: claims.id,
            createdAt: now,
            updatedAt: now
        )

        try await store.create(job)

        if let parentJob {
            await store.addChild(
                parentID: parentJob,
                childID: id,
                by: claims.id,
                note: "spawned \(id): \(title)"
            )
        }

        return ["job_id": id, "id": id, "title": title, "status": status]
    }

    // MARK: - Private
}
