//
//  WorkflowBuilder.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp

// How a catalog builds its workflows over a vocabulary. The vocabulary is
// compiled once, laid down as a compile against it reads it, with the
// native code it brings; a workflow is compiled against it and linked
// beside it.
struct WorkflowBuilder: Sendable {
    // MARK: - Property
    let vocabulary: ForgeVocabulary

    private let built: Task<(compiled: [Compiled], laid: Laid, supplying: Supplying), any Error>

    // MARK: - Initializer
    init(vocabulary: ForgeVocabulary) {
        self.vocabulary = vocabulary
        self.built = Task {
            let modules = vocabulary.linkables
            let supplying = try Supplying(modules)
            let compiled = try await Builder().compile(modules, against: [], supplying: supplying)

            return (compiled: compiled, laid: try Builder().lay(compiled, supplying: supplying), supplying: supplying)
        }
    }

    // MARK: - Public
    // The image a workflow runs: its module compiled against the vocabulary
    // as it was laid down once, and linked beside it.
    func image(of module: Module) async throws -> Image {
        let vocabulary = try await built.value
        let compiled = try await Builder().compile([module], against: vocabulary.laid)

        return try Builder().link(vocabulary.compiled + compiled, supplying: vocabulary.supplying)
    }

    // MARK: - Private
}
