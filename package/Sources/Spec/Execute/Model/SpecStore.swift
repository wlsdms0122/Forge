//
//  SpecStore.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public protocol SpecStore: Sendable {
    func spec(named name: String) async throws -> Program
}
