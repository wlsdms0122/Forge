//
//  SpecDirectoryTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SpecDirectory Tests")
struct SpecDirectoryTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("specdirectory")

    // MARK: - Initializer
    // MARK: - Test
    @Test("An unchanged file keeps what it decoded to, and a refusal stays recorded without a new line")
    func anUnchangedFileIsNotDecodedAgain() throws {
        // Given
        let directory = try temporary.make()
        try temporary.write("good", to: "good.yaml")
        try temporary.write("bad", to: "bad.yaml")
        var sut = SpecDirectory<String>(directory: directory, kind: "thing")
        var decodes = 0
        let decode: (ObservedFile, Data) throws -> String = { _, data in
            decodes += 1

            let text = String(decoding: data, as: UTF8.self)

            guard text == "good" else { throw LoadRefusal(message: "not good", line: "thing refused") }

            return text
        }
        var first = LoadFailureLedger(prior: [:])
        _ = sut.read(recording: &first, decode: decode)

        // When
        var second = LoadFailureLedger(prior: first.fresh)
        let reading = sut.read(recording: &second, decode: decode)

        // Then
        #expect(decodes == 2)
        #expect(reading.loaded.map(\.value) == ["good"])
        #expect(first.announcement == "forge: thing refused\n")
        #expect(second.fresh["bad.yaml"]?.reason == "not good")
        #expect(second.announcement.isEmpty)
    }

    @Test("A decode's error is recorded under the store's load failed line")
    func aDecodeErrorIsAnnouncedByKind() throws {
        // Given
        let directory = try temporary.make()
        try temporary.write("x", to: "broken.yaml")
        var sut = SpecDirectory<String>(directory: directory, kind: "thing")
        var ledger = LoadFailureLedger(prior: [:])

        // When
        let reading = sut.read(recording: &ledger) { _, _ in throw ProtocolError("unreadable") }

        // Then
        #expect(reading.loaded.isEmpty)
        #expect(reading.observed.map(\.file.source) == ["broken.yaml"])
        #expect(ledger.announcement.hasPrefix("forge: thing load failed (broken.yaml): "))
    }

    @Test("A directory that does not exist holds no file and hides none")
    func aMissingDirectoryIsEmpty() throws {
        // Given
        var sut = SpecDirectory<String>(directory: try temporary.file("absent"), kind: "thing")
        var ledger = LoadFailureLedger(prior: [:])

        // When
        let reading = sut.read(recording: &ledger) { _, data in String(decoding: data, as: UTF8.self) }

        // Then
        #expect(reading.observed.isEmpty)
        #expect(reading.obstructions.isEmpty)
    }

    // MARK: - Public
    // MARK: - Private
}
