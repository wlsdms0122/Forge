//
//  ResourceReading.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol ResourceReading: Sendable {
    func read(_ relative: String) async throws -> String
    func locate(_ relative: String) async throws -> String
}
