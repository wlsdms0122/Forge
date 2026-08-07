//
//  CommandPatternFixture.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

/// A command pattern that tests write in as literals.
///
/// Because the tokens are literals, a failure means an input typo, not a defect in the
/// subject. Instead of dying with `try!`, raise via `#require` so the report shows which
/// token was the problem.
func commandPattern(
    _ tokens: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CommandPattern {
    try #require(try CommandPattern(tokens: tokens), sourceLocation: sourceLocation)
}
