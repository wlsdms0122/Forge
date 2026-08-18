//
//  Executor+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR
@testable import Forge

// The kernel runs images, not modules — a test that hands over a module is
// skipping the link the daemon performs. Spelling the two steps once here keeps
// every test on the same path production takes, without the ceremony.
//
// Forge's convention is one routine per file, named after the file, so a test
// module declares `entry` and starts from it.
let entryName = "entry"

extension Warp.Executor {
    func run(
        _ module: Warp.Module,
        entry: String = entryName,
        beside others: [Warp.Module] = [],
        inputs: [String: Warp.Value] = [:],
        ambient: [String: Warp.Value] = [:]
    ) async throws -> [String: Warp.Value] {
        let world = [module] + others

        // The two modules every link needs, unless the caller already handed
        // them over — a catalog supplies them, so adding them again would be a
        // duplicate symbol rather than a convenience.
        let supplied = Set(world.compactMap(\.name))
        let vocabulary = ForgeSpec.linkables
            .filter { module in !supplied.contains(module.name ?? "") }
        let image = try ForgeSpec.loader().language.link(world + vocabulary, entry: entry)
        let arguments = inputs.merging(ambient) { _, seeded in seeded }
        let answer = try await run(image, arguments: arguments)

        // A run answers one value; `outputs:` lowers to a record, so the fields
        // of that record are what a test asking about named outputs means.
        guard case .object(let outputs) = answer else { return [:] }

        return outputs
    }
}

extension Loader {
    // Most Forge tests are about a forge word, not about the envelope a module
    // is written in, so they write a routine's body and this names it.
    func loadRoutine(_ text: String, named name: String = entryName) throws -> Warp.Module {
        let body = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.isEmpty ? "" : "    \(line)" }
            .joined(separator: "\n")

        return try load("procedures:\n  \(name):\n\(body)")
    }
}
