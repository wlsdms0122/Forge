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
    package func asJSONDict() -> [String: Any] {
        var values: [[String: Any]] = []
        
        for entry in entries {
            values.append([
                "key": entry.key,
                "value": entry.value,
                "source": entry.source.label
            ])
        }
        
        return [
            "toml": tomlPath as Any? ?? NSNull(),
            "values": values
        ]
    }
    
    // MARK: - Private
}
