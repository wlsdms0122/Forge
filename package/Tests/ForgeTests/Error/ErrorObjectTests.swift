//
//  ErrorObjectTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ErrorObject Tests")
struct ErrorObjectTests {
    struct Unnamed: Error {
        let reason: String
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A Forge error carries its type, its message and its details")
    func forgeErrorCarriesItsFields() {
        // Given
        let error = BackendNonzeroExit("exited 2", exitCode: 2, stderr: "err", stdout: "out")

        // When
        let sut = ErrorObject(error).jsonValue

        // Then
        #expect(
            sut == [
                "type": "BackendNonzeroExit",
                "message": "exited 2",
                "exit_code": 2,
                "stderr": "err",
                "stdout": "out"
            ]
        )
    }

    @Test("An error that is not Forge's is an InternalError with its text")
    func otherErrorIsInternal() {
        // Given
        let error = Unnamed(reason: "boom")

        // When
        let sut = ErrorObject(error)

        // Then
        #expect(sut.type == "InternalError")
        #expect(sut.message == #"Unnamed(reason: "boom")"#)
        #expect(sut.details.isEmpty)
    }

    // MARK: - Public
    // MARK: - Private
}
