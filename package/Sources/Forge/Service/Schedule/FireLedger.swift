//
//  FireLedger.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor FireLedger {
    enum Disposition: Sendable, Equatable {
        case launched
        case denied(reason: String)
        case skipped
        
        var label: String {
            switch self {
            case .launched: "launched"
            case .denied: "denied"
            case .skipped: "skipped"
            }
        }
        
        var reason: String? {
            if case .denied(let reason) = self { return reason }
            
            return nil
        }
    }
    
    enum OutcomeState: Sendable, Equatable {
        case pending
        case unknown
        case closed(Disposition)
    }
    
    struct FireRecord: Sendable, Equatable {
        // MARK: - Property
        var attemptedSlot: Date
        var recordedAt: Date
        var state: OutcomeState
        var closedAt: Date?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private let path: URL
    
    private var records: [String: FireRecord]
    
    // MARK: - Initializer
    init(path: URL) {
        self.path = path
        self.records = Self.load(path)
    }
    
    // MARK: - Public
    func snapshot() -> [String: FireRecord] { records }
    
    func lastAttempt(id: String) -> Date? { records[id]?.attemptedSlot }
    
    func recordAttempt(id: String, slot: Date, wall: Date = Date()) throws {
        var next = records
        next[id] = FireRecord(
            attemptedSlot: slot,
            recordedAt: wall,
            state: .pending,
            closedAt: nil
        )
        
        try Self.write(next, to: path)
        
        records = next
    }
    
    func close(id: String, _ disposition: Disposition, at: Date = Date()) {
        guard var record = records[id] else {
            FileHandle.standardError.write(
                Data(
                    ("forge: fire-ledger close('\(id)', \(disposition.label)) without a"
                        + " recorded attempt — ordering bug\n").utf8
                )
            )
            
            return
        }
        
        guard record.state == .pending else {
            FileHandle.standardError.write(
                Data(
                    ("forge: fire-ledger double close('\(id)'): \(record.state) then"
                        + " \(disposition.label) — one slot must close once\n").utf8
                )
            )
            
            return
        }
        
        record.state = .closed(disposition)
        record.closedAt = at
        
        var next = records
        next[id] = record
        
        do {
            try Self.write(next, to: path)
        } catch {
            FileHandle.standardError.write(
                Data(
                    ("forge: fire-ledger outcome persist failed for '\(id)'"
                        + " (attempt anchor intact): \(error)\n").utf8
                )
            )
        }
        
        records = next
    }
    
    func clear(id: String) throws {
        guard records[id] != nil else { return }
        
        var next = records
        next.removeValue(forKey: id)
        
        try Self.write(next, to: path)
        
        records = next
    }
    
    func prune(liveIDs: Set<String>) throws {
        let next = records.filter { id, _ in liveIDs.contains(id) }
        
        guard next.count != records.count else { return }
        
        try Self.write(next, to: path)
        
        records = next
    }
    
    // MARK: - Private
    private static func write(_ records: [String: FireRecord], to path: URL) throws {
        let object = records.mapValues { record -> [String: String] in
            var entry = [
                "attempted_at": ISO8601.string(record.attemptedSlot),
                "recorded_at": ISO8601.string(record.recordedAt)
            ]
            
            switch record.state {
            case .pending:
                entry["outcome"] = "pending"
            
            case .unknown:
                entry["outcome"] = "unknown"
            
            case .closed(let disposition):
                entry["outcome"] = disposition.label
                
                if let reason = disposition.reason { entry["reason"] = reason }
            }
            
            if let closedAt = record.closedAt {
                entry["outcome_at"] = ISO8601.string(closedAt)
            }
            
            return entry
        }
        
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .prettyPrinted]
        )
        
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }
    
    private static func load(_ path: URL) -> [String: FireRecord] {
        let data: Data
        
        do {
            data = try Data(contentsOf: path)
        } catch {
            if !FileManager.default.fileExists(atPath: path.path) { return [:] }
            
            FileHandle.standardError.write(
                Data(
                    ("forge: fire-ledger '\(path.path)' unreadable, treating as empty"
                        + " (once may re-fire): \(error)\n").utf8
                )
            )
            
            return [:]
        }
        
        guard
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            FileHandle.standardError.write(
                Data(
                    ("forge: fire-ledger '\(path.path)' unparseable, treating as empty"
                        + " (once may re-fire)\n").utf8
                )
            )
            
            return [:]
        }
        
        var records: [String: FireRecord] = [:]
        
        for (id, value) in raw {
            if let text = value as? String {
                if let date = ISO8601.parse(text) {
                    records[id] = FireRecord(
                        attemptedSlot: date,
                        recordedAt: date,
                        state: .unknown,
                        closedAt: nil
                    )
                } else {
                    Self.dropEntry(id, detail: "unparseable timestamp '\(text)'")
                }
                
                continue
            }
            
            guard
                let object = value as? [String: String],
                let attempted = object["attempted_at"].flatMap(ISO8601.parse)
            else {
                Self.dropEntry(id, detail: "missing/unparseable attempted_at")
                
                continue
            }
            
            let state: OutcomeState
            
            switch object["outcome"] {
            case "launched":
                state = .closed(.launched)
            
            case "skipped":
                state = .closed(.skipped)
            
            case "denied":
                state = .closed(.denied(reason: object["reason"] ?? "unknown"))
            
            default:
                state = .unknown
            }
            
            records[id] = FireRecord(
                attemptedSlot: attempted,
                recordedAt: object["recorded_at"].flatMap(ISO8601.parse) ?? attempted,
                state: state,
                closedAt: object["outcome_at"].flatMap(ISO8601.parse)
            )
        }
        
        return records
    }
    
    private static func dropEntry(_ id: String, detail: String) {
        FileHandle.standardError.write(
            Data(
                ("forge: fire-ledger entry '\(id)' \(detail), dropping"
                    + " (that once may re-fire)\n").utf8
            )
        )
    }
}
