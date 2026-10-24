//
//  DispatchOrigin.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct DispatchOrigin: Sendable {
    // MARK: - Property
    static let manual = DispatchOrigin(kind: "manual")
    static let rpc = DispatchOrigin(kind: "rpc")
    
    let kind: String
    let id: String?
    
    var jsonValue: JSONValue {
        var object: [String: JSONValue] = ["kind": .string(kind)]
        
        if let id { object["id"] = .string(id) }
        
        return .object(object)
    }
    
    // MARK: - Initializer
    init(kind: String, id: String? = nil) {
        self.kind = kind
        self.id = id
    }
    
    // MARK: - Public
    static func schedule(_ id: String) -> DispatchOrigin { .init(kind: "schedule", id: id) }
    
    // MARK: - Private
}
