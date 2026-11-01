//
//  ResourceReading.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol ResourceReading: Sendable {
    func read(_ path: String) async throws -> String
    func locate(_ path: String) async throws -> String
}
