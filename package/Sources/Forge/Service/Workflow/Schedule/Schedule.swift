//
//  Schedule.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct Schedule: Sendable, Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case workflow
        case concurrency
        case inputs
        case spec
    }
    
    // MARK: - Property
    let id: String
    let workflow: String
    let trigger: Trigger
    let concurrency: ConcurrencyPolicy
    let enabled: Bool
    let inputs: [String: JSONValue]?
    let spec: JSONValue?
    
    // MARK: - Initializer
    init(
        id: String,
        workflow: String,
        trigger: Trigger,
        concurrency: ConcurrencyPolicy = .queue,
        enabled: Bool = true,
        inputs: [String: JSONValue]? = nil,
        spec: JSONValue? = nil
    ) {
        self.id = id
        self.workflow = workflow
        self.trigger = trigger
        self.concurrency = concurrency
        self.enabled = enabled
        self.inputs = inputs
        self.spec = spec
    }
    
    init(from decoder: Decoder) throws {
        try SpecGate.rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            extra: Trigger.CodingKeys.allCases.map(\.stringValue),
            context: "schedule"
        )
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.workflow = try container.decode(String.self, forKey: .workflow)
        self.trigger = try Trigger(from: decoder)
        self.concurrency = try container.decodeIfPresent(
            ConcurrencyPolicy.self,
            forKey: .concurrency
        ) ?? .queue
        self.enabled = false
        self.inputs = try container.decodeIfPresent([String: JSONValue].self, forKey: .inputs)
        
        if let rawSpec = try container.decodeIfPresent(JSONValue.self, forKey: .spec) {
            guard case .object(var object) = rawSpec else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath + [CodingKeys.spec],
                        debugDescription: "inline 'spec' must be a JSON object"
                    )
                )
            }
            
            if let existing = object["name"], existing != .string(WorkflowDispatchMethod.inlineSigil) {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath + [CodingKeys.spec],
                        debugDescription: "inline 'spec' must be anonymous — a 'name' key is"
                            + " not allowed (name is fixed to '\(WorkflowDispatchMethod.inlineSigil)')"
                    )
                )
            }
            
            object["name"] = .string(WorkflowDispatchMethod.inlineSigil)
            self.spec = .object(object)
        } else {
            self.spec = nil
        }
    }
    
    // MARK: - Public
    func withEnabled(_ enabled: Bool) -> Schedule {
        Schedule(
            id: id,
            workflow: workflow,
            trigger: trigger,
            concurrency: concurrency,
            enabled: enabled,
            inputs: inputs,
            spec: spec
        )
    }
    
    func withID(_ newID: String) -> Schedule {
        Schedule(
            id: newID,
            workflow: workflow,
            trigger: trigger,
            concurrency: concurrency,
            enabled: enabled,
            inputs: inputs,
            spec: spec
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(workflow, forKey: .workflow)
        try trigger.encode(to: encoder)
        
        if concurrency != .queue { try container.encode(concurrency, forKey: .concurrency) }
        
        try container.encodeIfPresent(inputs, forKey: .inputs)
        try container.encodeIfPresent(spec, forKey: .spec)
    }
    
    // MARK: - Private
}
