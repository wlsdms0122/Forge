//
//  Executor+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
@testable import Forge

let entryName = "entry"

extension Executor {
    // Builds the module beside the others, the Forge module and the standard
    // vocabulary, runs the entry, and returns the fields of the struct or map
    // it returns. An optional parameter the inputs leave out is handed null.
    func run(
        _ module: Warp.Module,
        entry: String = entryName,
        beside others: [Warp.Module] = [],
        inputs: [String: Warp.Value] = [:]
    ) async throws -> [String: Warp.Value] {
        let name = try Name(entry)
        let image = try await Builder().build([module] + others + ForgeVocabulary.shipped.get().linkables)
        var arguments: [Name: Warp.Value] = [:]

        for (key, value) in inputs {
            arguments[try Name(key)] = value
        }

        for parameter in module.procedures[name]?.signature.parameters ?? [] where arguments[parameter.name] == nil {
            guard case .optional = parameter.type else { continue }

            arguments[parameter.name] = .null
        }

        return try ValueBridge.fields(try await run(image, entry: name, arguments: arguments))
    }
}
