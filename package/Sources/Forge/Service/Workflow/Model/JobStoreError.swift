//
//  JobStoreError.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum JobStoreError: ForgeError {
    case notConfigured
    case notFound(String)
    case unreadable(String)
    
    var message: String {
        switch self {
        case .notConfigured: "job directory not configured"
        case .notFound(let id): "job not found: \(id)"
        case .unreadable(let id): "job file present but unreadable: \(id)"
        }
    }
}
