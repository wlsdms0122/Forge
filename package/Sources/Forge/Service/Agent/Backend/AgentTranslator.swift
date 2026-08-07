//
//  AgentTranslator.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol AgentTranslator: Sendable {
    associatedtype NativeAgent: Sendable

    func translate(_ agent: Agent) throws -> AgentTranslation<NativeAgent>
}
