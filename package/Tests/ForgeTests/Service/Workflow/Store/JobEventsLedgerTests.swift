//
//  JobEventsLedgerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("JobEventsLedger Tests")
struct JobEventsLedgerTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("jobevents")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - Codable
    @Test("Legacy shape decodes, and rewriting keeps the shape")
    func legacyDecodeAndRoundTrip() throws {
        // Given
        let legacy = """
        {"id":"j-old","title":"old","status":"open","activity":[{"ts":"2026-07-01T00:00:00Z","tools":[]}],
         "created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z"}
        """

        // When
        let old = try JSONDecoder().decode(Job.self, from: Data(legacy.utf8))

        // Then
        #expect(old.events.count == 0)
        #expect(!old.isOpen())
        var job = makeJob("j-rt")
        job.events = [
            Job.Event(ts: "2026-07-22T00:00:00Z", kind: .runAttached, run: "tok-1", detail: "job.update"),
            Job.Event(ts: "2026-07-22T00:00:01Z", kind: .runCompleted, run: "tok-1"),
        ]
        let data = try JSONEncoder().encode(job)
        let str = String(data: data, encoding: .utf8) ?? ""
        #expect(str.contains("\"run_attached\"") && str.contains("\"run_completed\""), "kind serializes as a fixed snake_case vocabulary: \(str)")
        let decoded = try JSONDecoder().decode(Job.self, from: data)
        #expect(decoded.events.map(\.kind) == [.runAttached, .runCompleted])
    }
    
    // MARK: - open derivation
    @Test("Open pairs are derived from events — never stored separately")
    func openPairsDerivation() {
        // Given
        var job = makeJob("j-open")
        func event(_ kind: Job.Event.Kind, run: String? = nil) -> Job.Event {
            Job.Event(ts: ISO8601.string(Date()), kind: kind, run: run)
        }
        job.events = [event(.runAttached, run: "tok-1"), event(.runAttached, run: "tok-1"),
            event(.runCompleted, run: "tok-1")]

        // Then
        #expect(job.openRuns == ["tok-1"], "2 opens - 1 close = 1 open")
        #expect(job.isOpen())
        job.events.append(event(.runFailed, run: "tok-1"))
        #expect(!job.isOpen())
        job.events = [event(.runCompleted, run: "tok-2"), event(.runAttached, run: "tok-2")]
        #expect(job.openRuns == ["tok-2"], "a preceding close is ignored — the later open stays alive")
        job.events = [event(.runAttached, run: "tok-3"), event(.runCompleted, run: "tok-3"),
            event(.runAttached, run: "tok-3")]
        #expect(job.openRuns == ["tok-3"], "re-open after close = 1 open — no duplicate reporting")
    }
    
    // MARK: - recordTouch (observation-based attachment)
    @Test("touch is recorded once per open attachment")
    func recordTouchIdempotentPerOpenAttachment() async throws {
        // Given
        let directory = try temporary.make("touch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)

        // When
        try await store.create(makeJob("jt"))
        await store.recordTouch(id: "jt", run: "tok-1", via: "job.show")
        await store.recordTouch(id: "jt", run: "tok-1", via: "job.update")
        var job = await store.lookup("jt")

        // Then
        #expect(job?.events.map(\.kind) == [.runAttached], "no-op when an open attachment exists")
        #expect(job?.events.first?.detail == "job.show", "the first observation's evidence remains")
        await store.recordTouch(id: "jt", run: "tok-2", via: "job.update")
        job = await store.lookup("jt")
        #expect(job?.openRuns.sorted() == ["tok-1", "tok-2"])
        await store.closeRun(run: "tok-1", failure: nil)
        await store.recordTouch(id: "jt", run: "tok-1", via: "job.update")
        job = await store.lookup("jt")
        #expect(job?.events.filter { event in event.run == "tok-1" }.map(\.kind) == [.runAttached, .runCompleted, .runAttached], "a touch after close re-attaches")
    }
    
    @Test("System events keep the agent stamp and truncate the detail")
    func systemEventsKeepAgentStampAndTruncateDetail() async throws {
        // Given
        let directory = try temporary.make("stamp")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("js"))
        try await store.addComment(id: "js", by: "agent-1", note: "picked up")
        await store.recordTouch(id: "js", run: "tok-1", via: "job.update")
        await store.appendEvent(id: "js", kind: .runFailed, run: "tok-1",
            detail: String(repeating: "x", count: 500))

        // When
        let job = await store.lookup("js")

        // Then
        #expect(job?.updatedBy == "agent-1", "system utterances must not overwrite updated_by")
        #expect(job?.events.last?.detail?.count == 300)
    }
    
    @Test("System events do not touch updatedAt")
    func systemEventsDoNotBumpUpdatedAt() async throws {
        // Given
        let directory = try temporary.make("stamp-at")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        let before = "2026-07-01T00:00:00Z"
        try await store.create(Job(id: "ju", title: "t", status: "backlog",
                createdAt: before, updatedAt: before))

        // When
        await store.recordTouch(id: "ju", run: "tok-1", via: "job.show")
        await store.closeRun(run: "tok-1", failure: nil)
        let after = await store.lookup("ju")

        // Then
        #expect(after?.updatedAt == before, "system-layer utterances do not bump updatedAt")
        #expect(after?.events.count == 2, "the events themselves are recorded")
        try await store.addComment(id: "ju", by: "a1", note: "edit")
        let edited = await store.lookup("ju")
        #expect(edited?.updatedAt != before, "explicit-layer edits do bump it")
    }
    
    // MARK: - closeRun (closing at run end)
    @Test("When a run ends, every ticket that run touched is closed")
    func closeRunClosesAllTouchedTickets() async throws {
        // Given
        let directory = try temporary.make("close")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)

        // When
        try await store.create(makeJob("j1"))
        try await store.create(makeJob("j2"))
        try await store.create(makeJob("j3"))
        await store.recordTouch(id: "j1", run: "tok-a", via: "job.update")
        await store.recordTouch(id: "j2", run: "tok-a", via: "job.show")
        await store.recordTouch(id: "j3", run: "tok-b", via: "job.update")
        await store.closeRun(run: "tok-a", failure: nil)
        let first = await store.lookup("j1"), j2 = await store.lookup("j2"), j3 = await store.lookup("j3")

        // Then
        #expect(first?.events.map(\.kind) == [.runAttached, .runCompleted])
        #expect(j2?.events.map(\.kind) == [.runAttached, .runCompleted])
        #expect(j3?.events.map(\.kind) == [.runAttached], "another run's attachment is left as-is")
        #expect(j3?.isOpen() == true)
        #expect(first?.status == "backlog", "forge still does not write status")
    }
    
    @Test("Closing as a failure stamps the reason")
    func closeRunFailureStampsReason() async throws {
        // Given
        let directory = try temporary.make("close-fail")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)

        // When
        try await store.create(makeJob("jf"))
        await store.recordTouch(id: "jf", run: "tok-a", via: "job.update")
        await store.closeRun(run: "tok-a", failure: "StepError: boom")
        let job = await store.lookup("jf")

        // Then
        #expect(job?.events.map(\.kind) == [.runAttached, .runFailed])
        #expect(job?.events.last?.detail == "StepError: boom")
        #expect(!(job?.isOpen() ?? true))
    }
    
    @Test("Closing with no touched tickets is a no-op")
    func closeRunWithoutTouchIsNoop() async throws {
        // Given
        let directory = try temporary.make("close-noop")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)

        // When
        try await store.create(makeJob("jn"))
        await store.closeRun(run: "tok-ghost", failure: nil)
        let job = await store.lookup("jn")

        // Then
        #expect(job?.events.count == 0)
    }
    
    // MARK: - closeOrphans (daemon startup scan)
    @Test("Orphan closing closes only dangling attachments and repeated calls are the same")
    func closeOrphansClosesOnlyDanglingAndIsIdempotent() async throws {
        // Given
        let directory = try temporary.make("orphan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)

        // When
        try await store.create(makeJob("jo"))
        await store.recordTouch(id: "jo", run: "tok-a", via: "job.update")
        try await store.create(makeJob("jc"))
        await store.recordTouch(id: "jc", run: "tok-b", via: "job.update")
        await store.closeRun(run: "tok-b", failure: nil)
        await store.closeOrphans()
        await store.closeOrphans()
        let dangling = await store.lookup("jo")

        // Then
        #expect(dangling?.events.map(\.kind) == [.runAttached, .runOrphaned], "idempotent — two scans still close once")
        #expect(dangling?.events.last?.detail == "unclosed at daemon start")
        #expect(!(dangling?.isOpen() ?? true))
        let closed = await store.lookup("jc")
        #expect(closed?.events.count == 2, "nothing is added to an already-closed attachment")
    }
    
    // MARK: - RPC observation boundary (JobShow/UpdateMethod)
    @Test("Attachment is recorded only for run tokens")
    func showAndUpdateRecordTouchOnlyForRunTokens() async throws {
        // Given
        let directory = try temporary.make("rpc")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobStore(directory: directory)
        try await store.create(makeJob("jr"))
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let show = JobShowMethod(store: store, tokenAuthority: authority, workRegistry: registry)
        let update = JobUpdateMethod(store: store, tokenAuthority: authority, workRegistry: registry)
        func liveRecord(_ id: String) -> WorkRecord {
            WorkRecord(workflowID: id, workflowName: "t", principal: "cli:worker",
                origin: .rpc, rootID: nil, nodeID: nil, correlator: nil, parameters: nil)
        }
        await registry.register(liveRecord("wf-1"))
        await registry.register(liveRecord("wf-2"))
        let opToken = authority.mint(TokenClaims(principal: "system:admin"))
        _ = try await show.handle(RPCRequest(id: "r1", method: "job.show",
                params: ["token": opToken, "id": "jr"]))

        // When
        var job = await store.lookup("jr")

        // Then
        #expect(job?.events.count == 0, "an operator's read is not an observation target")
        let runToken = authority.mint(TokenClaims(principal: "cli:worker", workflowID: "wf-1", id: "tok-r"))
        let shown = try await show.handle(RPCRequest(id: "r2", method: "job.show",
                params: ["token": runToken, "id": "jr"]))
        job = await store.lookup("jr")
        #expect(job?.events.map(\.kind) == [.runAttached])
        #expect(job?.events.first?.run == "tok-r", "attachment key = accessor id (same as comment.by)")
        #expect(job?.events.first?.detail == "job.show")
        let dict = shown.dict["job"] as? [String: Any]
        #expect((dict?["events"] as? [[String: Any]])?.count ?? 0 == 0)
        #expect(dict?["open"] as? Bool == false, "show's open is false for a ticket with only one's own attachment")
        _ = try await update.handle(RPCRequest(id: "r3", method: "job.update",
                params: ["token": runToken, "id": "jr",
                    "note": "working"]))
        job = await store.lookup("jr")
        #expect(job?.events.map(\.kind) == [.runAttached], "re-touch over an open attachment is a no-op")
        #expect(job?.comments.count == 1)
        #expect(job?.comments.first?.by == "tok-r")
        let otherToken = authority.mint(TokenClaims(principal: "cli:worker", workflowID: "wf-2", id: "tok-o"))
        _ = try await update.handle(RPCRequest(id: "r4", method: "job.update",
                params: ["token": otherToken, "id": "jr",
                    "note": "also here"]))
        let shown2 = try await show.handle(RPCRequest(id: "r5", method: "job.show",
                params: ["token": runToken, "id": "jr"]))
        #expect((shown2.dict["job"] as? [String: Any])?["open"] as? Bool == true, "someone else's open attachment shows as open")
        let deadToken = authority.mint(TokenClaims(principal: "cli:worker", workflowID: "wf-dead", id: "tok-d"))
        _ = try await update.handle(RPCRequest(id: "r6", method: "job.update",
                params: ["token": deadToken, "id": "jr",
                    "note": "late from orphan"]))
        job = await store.lookup("jr")
        #expect(!(job?.events.contains { event in event.run == "tok-d" } ?? true), "a dead run token's touch does not open an attachment")
        #expect(job?.comments.last?.note == "late from orphan", "the canvas edit itself is processed normally")
    }
    
    // MARK: - Private
    
    private func makeJob(_ id: String) -> Job {
        let now = ISO8601.string(Date())
        
        return Job(id: id, title: "t", status: "backlog", createdAt: now, updatedAt: now)
    }
}
