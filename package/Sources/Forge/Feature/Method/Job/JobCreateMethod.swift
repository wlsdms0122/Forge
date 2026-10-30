//
//  JobCreateMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation



struct JobCreateMethod: Sendable {
    // MARK: - Property
    let store: JobStore

    // MARK: - Initializer
    init(store: JobStore) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let title = request.params["title"]?.stringValue, !title.isEmpty else {
            throw ProtocolError("job.create: 'title' (string) required")
        }

        let now = ISO8601.string(Date())

        let origin = request.params["origin"]?.objectValue
        let brief = request.params["brief"]?.stringValue ?? ""

        var refs: [Job.Ref] = []

        if let rawRefs = request.params["refs"]?.arrayValue {
            refs = try rawRefs.enumerated().map { index, item in
                if let string = item.stringValue { return Job.Ref(ref: string) }

                guard let dictionary = item.objectValue,
                    let ref = dictionary["ref"]?.stringValue, !ref.isEmpty
                else {
                    throw ProtocolError("job.create: refs[\(index)] needs 'ref' (string) — shape: {\"ref\":\"...\",\"note\"?:\"...\"} or a plain string")
                }

                return Job.Ref(ref: ref, note: dictionary["note"]?.stringValue)
            }
        } else if request.params["refs"] != nil {
            throw ProtocolError("job.create: 'refs' must be a JSON array of {ref,note?} objects or strings")
        }

        var planEntries: [Job.Plan.Entry] = []

        if let rawPlan = request.params["plan"]?.arrayValue {
            for (index, item) in rawPlan.enumerated() {
                if let string = item.stringValue {
                    planEntries.append(.auto(desc: string, status: nil))

                    continue
                }

                guard let dictionary = item.objectValue else {
                    throw ProtocolError("job.create: plan[\(index)] must be {\"id\"?:int,\"desc\":\"...\",\"status\"?:\"...\"} or a plain string")
                }

                guard let desc = dictionary["desc"]?.stringValue, !desc.isEmpty else {
                    throw ProtocolError("job.create: plan[\(index)] needs 'desc' (string)")
                }

                var itemID = dictionary["id"]?.intValue

                if itemID == nil, let string = dictionary["id"]?.stringValue { itemID = Int(string) }
                if itemID == nil, dictionary["id"] != nil {
                    throw ProtocolError("job.create: plan[\(index)].id must be an integer — omit it to auto-number")
                }

                let status = dictionary["status"]?.stringValue

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

        let parentJob = request.params["parent_job"]?.stringValue
            .flatMap { value in value.isEmpty ? nil : value }

        if let parentJob, await store.lookup(parentJob) == nil {
            throw ProtocolError("job.create: parent job not found: '\(parentJob)'")
        }

        let status = request.params["status"]?.stringValue
            .flatMap { value in value.isEmpty ? nil : value }

        let id: String

        if let given = request.params["id"]?.stringValue, !given.isEmpty {
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

        var result: [String: JSONValue] = ["job_id": .string(id), "id": .string(id), "title": .string(title)]

        if let status { result["status"] = .string(status) }

        return .object(result)
    }

    // MARK: - Private
}
