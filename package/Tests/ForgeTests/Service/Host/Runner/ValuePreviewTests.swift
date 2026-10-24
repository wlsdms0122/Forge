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
        #expect(WorkflowRunner.valuePreview(.int(42)) == ("42", 2))
        #expect(WorkflowRunner.valuePreview(.bool(true)) == ("true", 4))
        #expect(WorkflowRunner.valuePreview(.double(1.5)) == ("1.5", 3))
    }
    
    @Test("Null stays absent with no preview")
    func nullStaysAbsent() {
        // Given
        let (p, l) = WorkflowRunner.valuePreview(.null)

        // Then
        #expect(p == nil && l == nil)
    }
    
    @Test("Strings and containers are left untouched")
    func stringAndContainerUnchanged() {
        #expect(WorkflowRunner.valuePreview(.string("hi")) == ("hi", 2))
        let (p, _) = WorkflowRunner.valuePreview(.object(["a": .int(1)]))
        #expect(p == #"{"a":1}"#)
        let long = String(repeating: "x", count: 3000)
        let (tp, tl) = WorkflowRunner.valuePreview(.string(long))
        #expect(tp?.count == 2000 && tl == 3000)
    }
    
    // MARK: - Private
}
