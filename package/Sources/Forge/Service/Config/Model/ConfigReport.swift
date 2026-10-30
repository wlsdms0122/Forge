//
//  ConfigReport.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

package struct ConfigReport: Sendable {
    package struct Entry: Sendable {
        // MARK: - Property
        package let key: String
        package let value: String
        package let source: ConfigSource
        
        // MARK: - Initializer
        package init(key: String, value: String, source: ConfigSource) {
            self.key = key
            self.value = value
            self.source = source
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    package let tomlPath: String?
    package let entries: [Entry]
    
    // MARK: - Initializer
    package init(tomlPath: String?, entries: [Entry]) {
        self.tomlPath = tomlPath
        self.entries = entries
    }
    
    // MARK: - Public
    package var fields: [String: JSONValue] {
        let values: [JSONValue] = entries.map { entry in
            [
                "key": .string(entry.key),
                "value": .string(entry.value),
                "source": .string(entry.source.label)
            ]
        }
        
        return [
            "toml": tomlPath.map(JSONValue.string) ?? .null,
            "values": .array(values)
        ]
    }
    
    // MARK: - Private
}
