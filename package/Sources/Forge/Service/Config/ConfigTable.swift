//
//  ConfigTable.swift
//  Forge
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import TOMLKit

// One table of config.toml as the loader reads it. A value is read as the
// type its key takes, and a key the loader does not read is refused, so no
// value written in the file is dropped without a word.
struct ConfigTable {
    // MARK: - Property
    let keys: [String]
    
    private let table: TOMLTable
    private let name: String?
    
    // MARK: - Initializer
    init(_ table: TOMLTable, name: String? = nil) {
        self.table = table
        self.name = name
        self.keys = table.keys.sorted()
    }
    
    // MARK: - Public
    func admit(_ known: [String]) throws {
        let unknown = keys.filter { key in !known.contains(key) }
        
        guard unknown.isEmpty else {
            let noun = unknown.count == 1 ? "key" : "keys"
            
            throw ConfigError(
                "config \(place): unknown \(noun) \(unknown.map { key in "'\(key)'" }.joined(separator: ", "))"
                    + "; known keys: \(known.sorted().joined(separator: ", "))"
            )
        }
    }
    
    func string(_ key: String) throws -> String? {
        try value(key, as: .string) { value in value.string }
    }
    
    func int(_ key: String) throws -> Int? {
        try value(key, as: .int) { value in value.int }
    }
    
    func bool(_ key: String) throws -> Bool? {
        try value(key, as: .bool) { value in value.bool }
    }
    
    func strings(_ key: String) throws -> [String]? {
        guard let array = try value(key, as: .array, { value in value.array }) else { return nil }
        
        let strings = array.compactMap { element in element.string }
        
        guard strings.count == array.count else {
            throw ConfigError("config \(place): '\(key)' must be an array of strings")
        }
        
        return strings
    }
    
    func table(_ key: String) throws -> ConfigTable? {
        try value(key, as: .table) { value in value.table }.map { table in
            ConfigTable(table, name: name.map { name in "\(name).\(key)" } ?? key)
        }
    }
    
    // Each entry of a table of named tables, as `[service.<name>]` is.
    func tables() throws -> [(name: String, table: ConfigTable)] {
        try keys.compactMap { key in try table(key).map { table in (key, table) } }
    }
    
    // MARK: - Private
    private var place: String {
        name.map { name in "[\(name)]" } ?? "top level"
    }
    
    private func value<Value>(
        _ key: String,
        as type: TOMLType,
        _ read: (any TOMLValueConvertible) -> Value?
    ) throws -> Value? {
        guard let value = table[key] else { return nil }
        
        guard value.type == type, let read = read(value) else {
            throw ConfigError("config \(place): '\(key)' must be \(type), given \(value.type)")
        }
        
        return read
    }
}
