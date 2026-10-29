//
//  CapabilitySet.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation

// What the host lends the verbs that reach outside the program: a shell to
// run commands in, an agent to speak to, and the resources a workflow reads.
struct CapabilitySet: Sendable {
    // MARK: - Property
    let shell: any ShellExecuting
    let agent: any AgentServing
    let resources: any ResourceReading

    // MARK: - Initializer
    init(shell: any ShellExecuting, agent: any AgentServing, resources: any ResourceReading) {
        self.shell = shell
        self.agent = agent
        self.resources = resources
    }

    // MARK: - Public
    // MARK: - Private
}
