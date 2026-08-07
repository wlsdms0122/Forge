//
//  PreHook.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol PreHook: Sendable {
    var name: String { get }

    func before(_ invocation: Invocation) async throws -> Invocation
}
