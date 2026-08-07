//
//  Job.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct Job: Sendable, Codable {
    struct Plan: Sendable, Codable {
        struct DuplicateID: ForgeError {
            // MARK: - Property
            let id: Int
            
            var message: String {
                "plan item id \(id) is already used — ids must be unique (omit id to auto-number)"
            }
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        enum Entry: Sendable {
            case explicit(PlanItem)
            case auto(desc: String, status: String)
        }
        
        // MARK: - Property
        private(set) var items: [PlanItem]
        
        var nextID: Int { Self.nextID(over: items.map(\.id)) }
        
        // MARK: - Initializer
        init() {
            self.items = []
        }
        
        init(entries: [Entry]) throws {
            self.items = []
            
            for case .explicit(let item) in entries {
                try add(item)
            }
            
            var assigned: [Int] = items.map(\.id)
            var result: [PlanItem] = []
            
            for entry in entries {
                switch entry {
                case .explicit(let item):
                    result.append(items.first { existing in existing.id == item.id }!)
                
                case .auto(let desc, let status):
                    let id = Self.nextID(over: assigned)
                    assigned.append(id)
                    result.append(PlanItem(id: id, desc: desc, status: status))
                }
            }
            
            self.items = result
        }
        
        init(from decoder: Decoder) throws {
            let raw = try [PlanItem](from: decoder)
            
            var seen = Set<Int>()
            var reserved = Set(raw.map(\.id))
            var normalized: [PlanItem] = []
            
            for item in raw {
                if seen.insert(item.id).inserted {
                    normalized.append(item)
                    
                    continue
                }
                
                var candidate = Self.nextID(over: Array(reserved))
                
                while reserved.contains(candidate) { candidate += 1 }
                
                reserved.insert(candidate)
                seen.insert(candidate)
                normalized.append(PlanItem(id: candidate, desc: item.desc, status: item.status))
            }
            
            self.items = normalized
        }
        
        // MARK: - Public
        mutating func add(_ item: PlanItem) throws {
            guard !items.contains(where: { existing in existing.id == item.id }) else {
                throw DuplicateID(id: item.id)
            }
            
            items.append(item)
        }
        
        mutating func append(desc: String, status: String = "todo") {
            items.append(PlanItem(id: nextID, desc: desc, status: status))
        }
        
        mutating func upsert(id: Int, desc: String?, status: String) {
            if let index = items.firstIndex(where: { item in item.id == id }) {
                items[index].status = status
                
                if let desc { items[index].desc = desc }
            } else {
                items.append(PlanItem(id: id, desc: desc ?? "", status: status))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            try items.encode(to: encoder)
        }
        
        // MARK: - Private
        private static func nextID(over ids: [Int]) -> Int {
            let maxID = ids.max() ?? 0
            
            if maxID < Int.max { return maxID + 1 }
            
            let used = Set(ids)
            var candidate = 1
            
            while used.contains(candidate) { candidate += 1 }
            
            return candidate
        }
    }
    
    struct PlanItem: Sendable, Codable {
        private enum CodingKeys: String, CodingKey {
            case id
            case desc
            case status
        }
        
        // MARK: - Property
        var id: Int
        var desc: String
        var status: String
        
        // MARK: - Initializer
        init(id: Int, desc: String, status: String = "todo") {
            self.id = id
            self.desc = desc
            self.status = status
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            id = try container.decode(Int.self, forKey: .id)
            desc = try container.decode(String.self, forKey: .desc)
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? "todo"
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Ref: Sendable, Codable {
        // MARK: - Property
        var ref: String
        var note: String?
        
        // MARK: - Initializer
        init(ref: String, note: String? = nil) {
            self.ref = ref
            self.note = note
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Comment: Sendable, Codable {
        // MARK: - Property
        var ts: String
        var by: String?
        var note: String
        
        // MARK: - Initializer
        init(ts: String, by: String? = nil, note: String) {
            self.ts = ts
            self.by = by
            self.note = note
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Event: Sendable, Codable {
        enum Kind: String, Sendable, Codable {
            case runAttached = "run_attached"
            case runCompleted = "run_completed"
            case runFailed = "run_failed"
            case runOrphaned = "run_orphaned"
            
            var opensPair: Bool {
                switch self {
                case .runAttached: true
                case .runCompleted, .runFailed, .runOrphaned: false
                }
            }
            
            var closesPair: Bool {
                switch self {
                case .runCompleted, .runFailed, .runOrphaned: true
                case .runAttached: false
                }
            }
        }
        
        // MARK: - Property
        var ts: String
        var kind: Kind
        var run: String?
        var detail: String?
        
        // MARK: - Initializer
        init(ts: String, kind: Kind, run: String? = nil, detail: String? = nil) {
            self.ts = ts
            self.kind = kind
            self.run = run
            self.detail = detail
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case origin
        case parentJob = "parent_job"
        case brief
        case refs
        case plan
        case comments
        case events
        case children
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Property
    var id: String
    var title: String
    var status: String
    var origin: [String: JSONValue]?
    var parentJob: String?
    var brief: String
    var refs: [Ref]
    var plan: Plan
    var comments: [Comment]
    var events: [Event]
    var children: [String]
    var createdBy: String?
    var updatedBy: String?
    var createdAt: String
    var updatedAt: String
    
    var openRuns: [String] {
        var open: [String] = []
        
        for event in events {
            let key = event.run ?? ""
            
            if event.kind.opensPair {
                open.append(key)
            } else if event.kind.closesPair, let index = open.lastIndex(of: key) {
                open.remove(at: index)
            }
        }
        
        return open
    }
    
    // MARK: - Initializer
    init(
        id: String,
        title: String,
        status: String = "open",
        origin: [String: JSONValue]? = nil,
        parentJob: String? = nil,
        brief: String = "",
        refs: [Ref] = [],
        plan: Plan = Plan(),
        comments: [Comment] = [],
        events: [Event] = [],
        children: [String] = [],
        createdBy: String? = nil,
        updatedBy: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.origin = origin
        self.parentJob = parentJob
        self.brief = brief
        self.refs = refs
        self.plan = plan
        self.comments = comments
        self.events = events
        self.children = children
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(String.self, forKey: .status)
        origin = try container.decodeIfPresent([String: JSONValue].self, forKey: .origin)
        parentJob = try container.decodeIfPresent(String.self, forKey: .parentJob)
        brief = try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        refs = try container.decodeIfPresent([Ref].self, forKey: .refs) ?? []
        plan = try container.decodeIfPresent(Plan.self, forKey: .plan) ?? Plan()
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        events = try container.decodeIfPresent([Event].self, forKey: .events) ?? []
        children = try container.decodeIfPresent([String].self, forKey: .children) ?? []
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
    
    // MARK: - Public
    func isOpen(excluding run: String? = nil) -> Bool {
        openRuns.contains { openRun in openRun != run }
    }
    
    // MARK: - Private
}
