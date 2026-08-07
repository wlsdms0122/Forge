//
//  ConcurrencyPolicy.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum ConcurrencyPolicy: String, Sendable, Codable, Equatable {
    case queue
    case skip
    case replace
}
