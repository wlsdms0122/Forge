//
//  WorkflowBuilder.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// How a catalog builds its workflows over a vocabulary. The vocabulary is
// compiled once, laid down as a compile against it reads it, with the
// native code it brings; workflows are compiled against it and linked
// beside it, and read by a front end leaning on its library and on their
// texts.
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
    // Workflows compiled against the vocabulary and the workflows already
    // compiled beside it, in the order they are handed: against the
    // vocabulary as it was laid down once, where nothing stands beside it.
    // A refusal is placed in the keys its document writes.
    func compiled(_ modules: [Module], beside standing: [Compiled] = []) async throws -> [Compiled] {
        try await Loader().reading {
            let vocabulary = try await built.value

            guard !standing.isEmpty else {
                return try await Builder().compile(modules, against: vocabulary.laid)
            }

            return try await Builder().compile(
                modules,
                against: vocabulary.compiled + standing,
                supplying: vocabulary.supplying
            )
        }
    }

    // The image of compiled workflows linked beside the vocabulary, a
    // refusal placed in the keys its document writes.
    func linked(_ compiled: [Compiled]) async throws -> Image {
        try await Loader().reading {
            let vocabulary = try await built.value

            return try Builder().link(vocabulary.compiled + compiled, supplying: vocabulary.supplying)
        }
    }

    // The front end leaning on the library and on these texts, which lean on
    // each other. A text that does not parse leans on nothing, and its
    // refusal, as it reads alone, is handed back under its position.
    func frontend(leaningOn texts: [String]) throws -> (frontend: YAMLFrontend, refusals: [Int: any Error]) {
        let frontend = vocabulary.frontend
        var standing = Array(texts.indices)
        var refusals: [Int: any Error] = [:]

        while true {
            do {
                let dependencies = standing.map { index in Dependency.text(texts[index]) }

                return (try SpendingThread().run { try frontend.leaning(on: dependencies) }, refusals)
            } catch let refusal as AuthoringError {
                guard let position = refusal.text else { throw refusal }

                let index = standing.remove(at: position)

                do {
                    let text = texts[index]

                    _ = try SpendingThread().run { try frontend.document(from: text) }
                    refusals[index] = refusal
                } catch {
                    refusals[index] = error
                }
            }
        }
    }

    // MARK: - Private
}
