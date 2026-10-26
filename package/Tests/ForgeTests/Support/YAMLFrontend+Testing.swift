//
//  YAMLFrontend+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML
@testable import Forge

extension YAMLFrontend {
    // Most Forge tests are about a verb, not about the file a workflow is
    // written in, so they write one procedure's keys and this names it and
    // loads it the way the catalog does.
    func workflow(_ text: String, named name: String = entryName) throws -> Warp.Module {
        let document = try decoded(from: workflowFile(text, named: name))

        return try Loader().load(document, identity: try Identity.of(document))
    }

    // A text's document, decoded from the bytes the front end spends it to.
    func decoded(from text: String) throws -> Value {
        try BinaryEncoding().value(from: try document(from: text).document)
    }
}
