//
//  JobStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("JobStore Tests", .exclusive(.standardError))
struct JobStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("jobstore")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - basic CRUD
    @Test("Create does not clobber a broken ticket file")
    func createDoesNotClobberBrokenTicket() async throws {
        // Given
        let directory = try temporary.make("clobber")
        defer { try? FileManager.default.removeItem(at: directory) }
        let brokenJSON = "{ corrupt"
        let file = directory.appendingPathComponent("wounded.json")
        try brokenJSON.write(to: file, atomically: true, encoding: .utf8)
        let store = JobStore(directory: directory)
        do {

        // When
            try await store.create(makeJob("wounded"))

        // Then
            Issue.record("create with the same id as a broken ticket file must throw")
        } catch {  }
        #expect(try String(contentsOf: file, encoding: .utf8) == brokenJSON, "the broken ticket file must not be clobbered by create")
        try await store.create(makeJob("healthy"))
        let healthy = await store.lookup("healthy")
        #expect(healthy != nil)
    }
    
    @Test("Create works on a fresh session whose job directory does not exist yet")
    func createWorksOnFreshDirectory() async throws {
        let parent = try temporary.make("fresh")
        defer { try? FileManager.default.removeItem(at: parent) }
        // A missing directory is a definitively empty store, not an unobservable
        // one — the very first ticket of a session must be creatable.
        let directory = parent.appendingPathComponent("jobs")
        let store = JobStore(directory: directory)
        try await store.create(makeJob("first"))
        let job = await store.lookup("first")
        #expect(job?.id == "first")
    }

    @Test("Create writes a file and lookup finds it")
    func createWritesFileAndLookup() async throws {
        let directory = try temporary.make("create")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("j1"))
        #expect(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("j1.json").path))
        let job = await store.lookup("j1")
        #expect(job?.id == "j1")
        #expect(job?.brief == "")
        #expect(job?.refs.count == 0)
    }
    
    @Test("Duplicate and malformed ids are rejected")
    func createRejectsDuplicateAndBadId() async throws {
        let directory = try temporary.make("dup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("dup"))
        do { try await store.create(makeJob("dup")); Issue.record("duplicate id must throw") } catch {}
        do { try await store.create(makeJob("../escape")); Issue.record("traversal id throw") } catch {}
    }
    
    // MARK: - Codable (brief/refs round-trip)
    @Test("brief and refs keep their shape across a round-trip")
    func briefRefsRoundTrip() throws {
        let now = ISO8601.string(Date())
        let job = Job(id: "j-rt", title: "round trip", status: "running",
            brief: "Goal: ship X. Constraints: no downtime.",
            refs: [Job.Ref(ref: "some-brain-note", note: "design"),
                Job.Ref(ref: "sandbox/backend/x")],
            createdAt: now, updatedAt: now)
        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(Job.self, from: data)
        #expect(decoded.brief == "Goal: ship X. Constraints: no downtime.")
        #expect(decoded.refs.count == 2)
        #expect(decoded.refs.first?.ref == "some-brain-note")
        #expect(decoded.refs.first?.note == "design")
        #expect(decoded.refs.last?.note == nil)
        let str = String(data: data, encoding: .utf8) ?? ""
        #expect(str.contains("\"created_at\""))
        #expect(str.contains("\"brief\""))
        #expect(str.contains("\"refs\""))
    }
    
    @Test("Decodes with only the minimal fields")
    func decodeWithMinimalFields() throws {
        let minimal = """
        {"id":"j-min","title":"minimal","status":"open",
         "created_at":"2026-05-29T00:00:00Z","updated_at":"2026-05-29T00:00:00Z"}
        """
        let job = try JSONDecoder().decode(Job.self, from: Data(minimal.utf8))
        #expect(job.id == "j-min")
        #expect(job.brief == "")
        #expect(job.refs.count == 0)
        #expect(job.comments.count == 0)
        #expect(job.createdBy == nil)
    }
    
    // MARK: - context-layer mutation
    @Test("brief is replaced")
    func setBrief() async throws {
        let directory = try temporary.make("brief")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jb"))
        try await store.setBrief(id: "jb", by: "actor-1", "filled in later")
        let job = await store.lookup("jb")
        #expect(job?.brief == "filled in later")
        #expect(job?.updatedBy == "actor-1", "a mutation is stamped with the accessor id")
    }
    
    @Test("Re-appending the same ref updates the note instead of duplicating")
    func appendRefDedupUpdatesNote() async throws {
        let directory = try temporary.make("refs")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jr"))
        try await store.appendRef(id: "jr", by: nil, ref: "note-a", note: "first")
        try await store.appendRef(id: "jr", by: nil, ref: "note-b", note: nil)
        try await store.appendRef(id: "jr", by: nil, ref: "note-a", note: "updated")
        let job = await store.lookup("jr")
        #expect(job?.refs.count == 2)
        #expect(job?.refs.first(where: { ref in ref.ref == "note-a" })?.note == "updated")
        #expect(job?.refs.first(where: { ref in ref.ref == "note-b" })?.note == nil)
    }
    
    // MARK: - progress mutation
    @Test("Updates status, plan, and comments")
    func updateStatusPlanAndComment() async throws {
        let directory = try temporary.make("cp")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jc"))
        try await store.setPlanItem(id: "jc", by: "a1", item: 1, desc: "step one", status: "todo")
        try await store.setPlanItem(id: "jc", by: "a1", item: 1, desc: nil, status: "done")
        try await store.addComment(id: "jc", by: "a1", note: "did step one")
        try await store.setStatus(id: "jc", by: "a2", "blocked")
        let job = await store.lookup("jc")
        #expect(job?.plan.items.count == 1)
        #expect(job?.plan.items.first?.desc == "step one")
        #expect(job?.plan.items.first?.status == "done")
        #expect(job?.comments.count == 1)
        #expect(job?.comments.first?.by == "a1", "a comment carries the accessor id that left it")
        #expect(job?.status == "blocked")
        #expect(job?.updatedBy == "a2", "updated_by is the accessor of the last mutation")
    }
    
    @Test("A plan item without status also decodes")
    func planItemDecodesWithoutStatus() throws {
        let data = Data(#"[{"id":1,"desc":"a"},{"id":2,"desc":"b","status":"doing"}]"#.utf8)
        let items = try JSONDecoder().decode([Job.PlanItem].self, from: data)
        #expect(items.first?.status == "todo")
        #expect(items.last?.status == "doing")
        let decoded = try JSONDecoder().decode([Job.PlanItem].self,
            from: try JSONEncoder().encode(items))
        #expect(decoded.first?.status == "todo")
    }
    
    @Test("Records a failure event without touching the ticket status")
    func appendEventRecordsFailureWithoutTouchingStatus() async throws {
        let directory = try temporary.make("fail")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jf"))
        await store.appendEvent(id: "jf", kind: .runFailed, run: "run-1", detail: "boom")
        let job = await store.lookup("jf")
        #expect(job?.status == "running", "forge does not write status (creation value kept)")
        #expect(job?.events.last?.kind == .runFailed)
        #expect(job?.events.last?.detail?.contains("boom") ?? false)
        #expect(job?.events.last?.run == "run-1", "a failure event also carries the run identity")
        #expect(job?.comments.isEmpty ?? false, "system utterances must not leak into comments")
    }
    
    @Test("Adding a child creates the reverse link too")
    func addChildReverseLink() async throws {
        let directory = try temporary.make("child")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("parent"))
        await store.addChild(parentID: "parent", childID: "kid", by: nil, note: "spawned kid")
        let job = await store.lookup("parent")
        #expect(job?.children == ["kid"])
        await store.addChild(parentID: "parent", childID: "kid", by: nil, note: nil)
        let after = await store.lookup("parent")
        #expect(after?.children.count == 1)
    }
    
    @Test("Create pointing at a nonexistent parent is rejected")
    func createRejectsNonexistentParent() async throws {
        let directory = try temporary.make("parent-gate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let store = JobStore(directory: directory)
        let method = JobCreateMethod(store: store, tokenAuthority: authority)
        let token = authority.mint(TokenClaims(principal: "cli:response"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "c1", method: "job.create",
                    params: ["token": token, "title": "child", "parent_job": "ghost"]))
            Issue.record("create against a missing parent must be refused")
        } catch {
            #expect(String(describing: error).contains("parent job not found"), "the refusal reason must be the missing parent: \(error)")
        }
        
        let all = await store.all()
        #expect(all.isEmpty, "a refused create must leave no child file behind")
        try await store.create(makeJob("par"))
        let result = try await method.handle(RPCRequest(
                id: "c2", method: "job.create",
                params: ["token": token, "title": "child", "parent_job": "par"]))
        let childID = try #require(result.dict["id"] as? String)
        let child = await store.lookup(childID)
        #expect(child?.parentJob == "par")
        let parent = await store.lookup("par")
        #expect(parent?.children == [childID], "the parent's reverse link must be recorded alongside")
    }
    
    @Test("Delete unlinks from the parent")
    func deleteUnlinksFromParent() async throws {
        let directory = try temporary.make("del-unlink")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("parent"))
        let now = ISO8601.string(Date())
        try await store.create(Job(id: "kid", title: "k", status: "open",
                parentJob: "parent", createdAt: now, updatedAt: now))
        await store.addChild(parentID: "parent", childID: "kid", by: nil, note: nil)
        try await store.delete(id: "kid")
        let parent = await store.lookup("parent")
        #expect(parent?.children.isEmpty == true, "the deleted child's reverse link must be cleaned up")
    }
    
    @Test("Deleting the parent clears the children's parent reference")
    func deleteParentClearsChildrenParentJob() async throws {
        let directory = try temporary.make("del-parent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        let now = ISO8601.string(Date())
        try await store.create(makeJob("epic"))
        try await store.create(Job(id: "c1", title: "a", status: "open",
                parentJob: "epic", createdAt: now, updatedAt: now))
        try await store.create(Job(id: "c2", title: "b", status: "open",
                parentJob: "epic", createdAt: now, updatedAt: now))
        await store.addChild(parentID: "epic", childID: "c1", by: nil, note: nil)
        await store.addChild(parentID: "epic", childID: "c2", by: nil, note: nil)
        try await store.delete(id: "epic")
        let firstChild = await store.lookup("c1")
        let secondChild = await store.lookup("c2")
        #expect(firstChild?.parentJob == nil, "the deleted parent's parent_job must be cleared")
        #expect(secondChild?.parentJob == nil, "the deleted parent's parent_job must be cleared")
    }
    
    @Test("Concurrently appended comments do not overwrite each other")
    func concurrentCommentAppendsAllSurvive() async throws {
        let directory = try temporary.make("concurrent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jcc"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await store.addComment(id: "jcc", by: "actor-\(i)", note: "n\(i)")
                }
            }
            try await group.waitForAll()
        }
        
        let job = await store.lookup("jcc")
        #expect(job?.comments.count == 20, "no concurrent append may be lost")
    }
    
    @Test("Updating a missing ticket throws a typed notFound")
    func updateThrowsTypedNotFound() async throws {
        let directory = try temporary.make("typed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        do {
            try await store.setStatus(id: "ghost", by: nil, "pending")
            Issue.record("a missing job must throw")
        } catch let storeError as JobStoreError {
            #expect(storeError.message == "job not found: ghost")
            #expect(storeError.wireType == "JobStoreError")
        }
    }
    
    @Test("A file that exists but cannot be read is not mistaken for deleted and swallowed")
    func recordRunFailureUnreadableFileSurfacesNotSwallowed() async throws {
        let directory = try temporary.make("unreadable")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jc"))
        try "}{ not json".write(to: directory.appendingPathComponent("jc.json"),
            atomically: true, encoding: .utf8)
        let error = try await StandardErrorCapture.capture {
            await store.appendEvent(id: "jc", kind: .runFailed, detail: "boom")
        }
        #expect(error.contains("persist failed"), "an existing but unreadable file must not be mistaken for deleted and swallowed (surface it)")
    }
    
    @Test("Event persist IO failure surfaces — record loss is not silently passed over", .enabled(if: getuid() != 0, "root ignores directory permissions, so the write would not fail"))
    func appendEventPersistIOFailureSurfaces() async throws {
        let directory = try temporary.make("io-surface")
        let fileManager = FileManager.default
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? fileManager.removeItem(at: directory)
        }
        
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jx"))
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let error = try await StandardErrorCapture.capture {
            await store.appendEvent(id: "jx", kind: .runFailed, detail: "boom")
        }
        #expect(error.contains("persist failed"), "an IO failure must surface (the buggy version is silent)")
        #expect(error.contains("lifecycle fact"), "the consequence (record loss) must be in the message, not a weak signal")
    }
    
    @Test("Reverse-link persist IO failure surfaces too", .enabled(if: getuid() != 0, "root ignores directory permissions"))
    func addChildPersistIOFailureSurfaces() async throws {
        let directory = try temporary.make("child-io")
        let fileManager = FileManager.default
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? fileManager.removeItem(at: directory)
        }
        
        let store = JobStore(directory: directory)
        try await store.create(makeJob("par"))
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let error = try await StandardErrorCapture.capture {
            await store.addChild(parentID: "par", childID: "kid", by: nil, note: nil)
        }
        #expect(error.contains("persist failed") && error.contains("back-link"), "addChild persist IO failure must surface too")
    }
    
    @Test("Updating an unreadable file throws unreadable, not notFound")
    func updateOnUnreadableFileThrowsUnreadable() async throws {
        let directory = try temporary.make("unread")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("ju"))
        try "}{ not json".write(to: directory.appendingPathComponent("ju.json"),
            atomically: true, encoding: .utf8)
        do {
            try await store.setStatus(id: "ju", by: nil, "done")
            Issue.record("a corrupt file must throw")
        } catch let storeError as JobStoreError {
            guard case .unreadable = storeError else {
                Issue.record("must be .unreadable, not notFound: \(storeError)")
                
                return
            }
        }
    }
    
    @Test("A best-effort update whose target is gone is a silent no-op")
    func bestEffortSwallowsNotFoundSilently() async throws {
        let directory = try temporary.make("noop")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        let error = try await StandardErrorCapture.capture {
            await store.appendEvent(id: "absent", kind: .runFailed, detail: "x")
            await store.recordTouch(id: "absent", run: "r1", via: "job.update")
            await store.addChild(parentID: "absent", childID: "kid", by: nil, note: nil)
        }
        #expect(!error.contains("persist failed"), "a missing (deleted) target must be a silent no-op")
    }
    
    // MARK: - Private
    
    private func makeJob(_ id: String, title: String = "t") -> Job {
        let now = ISO8601.string(Date())
        
        return Job(id: id, title: title, status: "running", createdAt: now, updatedAt: now)
    }
    
}
