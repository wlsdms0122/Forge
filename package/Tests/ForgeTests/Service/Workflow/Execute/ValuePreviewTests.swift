//
//  ValuePreviewTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import Forge

@Suite("ValuePreview Tests")
struct ValuePreviewTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Bare scalars also have a preview")
    func bareScalarsHavePreview() {
        #expect(SpecWorkflowRunner.valuePreview(.int(42)) == ("42", 2))
        #expect(SpecWorkflowRunner.valuePreview(.bool(true)) == ("true", 4))
        #expect(SpecWorkflowRunner.valuePreview(.double(1.5)) == ("1.5", 3))
    }
    
    @Test("Null stays absent with no preview")
    func nullStaysAbsent() {
        // Given
        let (p, l) = SpecWorkflowRunner.valuePreview(.null)

        // Then
        #expect(p == nil && l == nil)
    }
    
    @Test("Strings and containers are left untouched")
    func stringAndContainerUnchanged() {
        #expect(SpecWorkflowRunner.valuePreview(.string("hi")) == ("hi", 2))
        let (p, _) = SpecWorkflowRunner.valuePreview(.object(["a": .int(1)]))
        #expect(p == #"{"a":1}"#)
        let long = String(repeating: "x", count: 3000)
        let (tp, tl) = SpecWorkflowRunner.valuePreview(.string(long))
        #expect(tp?.count == 2000 && tl == 3000)
    }
    
    // MARK: - Private
}
