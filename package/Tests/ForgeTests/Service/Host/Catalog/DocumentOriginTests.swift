//
//  DocumentOriginTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/26/26.
//

import Foundation
import Testing
import Warp
import WarpSyntax
import WarpYAML
@testable import Forge

@Suite("DocumentOrigin Tests")
struct DocumentOriginTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a load refusal reads at the line and column the text writes the refused spot at")
    func aLoadRefusalReadsAtItsLine() throws {
        // Given
        let (document, sut) = try Self.spent(workflowFile("""
        body:
          - var: kept
            value: null
        """, named: "loaded"))

        // When
        let error = #expect(throws: (any Error).self) {
            _ = try Loader().load(document, identity: sut.identity)
        }

        // Then
        let described = sut.described(try #require(error))

        #expect(described.hasPrefix("6:9: a document says each thing one way"), "\(described)")
    }

    @Test("a build refusal reads at the line and column of the spot it is placed at")
    func aBuildRefusalReadsAtItsLine() async throws {
        // Given
        let (document, sut) = try Self.spent(workflowFile("""
        returns: Int
        result: hi
        """, named: "built"))
        let module = try Loader().load(document, identity: sut.identity)

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await WorkflowBuilder.shipped.get().compiled([module])
        }

        // Then
        let described = sut.described(try #require(error))

        #expect(described == "5:5: returns String, and its declaration promises Int", "\(described)")
    }

    @Test("a place past what the text wrote reads at the nearest spot it wrote, and says so")
    func aPlacePastTheTextIsTheNearest() throws {
        // Given
        let (_, sut) = try Self.spent(workflowFile("result: 1", named: "short"))
        let refusal = ValidationError(
            "refused",
            at: Place([.key("procedures"), .key("short"), .key("nowhere")], in: Place.Document(identity: sut.identity))
        )

        // When
        let described = sut.described(refusal)

        // Then
        #expect(described == "2:3 (nearest): refused", "\(described)")
    }

    @Test("a refusal of another document says what it says")
    func aRefusalOfAnotherDocumentIsItsOwn() throws {
        // Given
        let (document, _) = try Self.spent(workflowFile("""
        body:
          - var: kept
            value: null
        """, named: "loaded"))
        let (_, sut) = try Self.spent(workflowFile("result: 1", named: "other"))

        // When
        let error = #expect(throws: (any Error).self) {
            _ = try Loader().load(document, identity: try Identity.of(document))
        }

        // Then
        let refusal = try #require(error)

        #expect(sut.described(refusal) == "\(refusal)")
    }

    // MARK: - Public
    // MARK: - Private
    // A text spent by the vocabulary's front end, its document decoded, and
    // the origin the catalog keeps for it.
    private static func spent(_ text: String) throws -> (document: Value, origin: DocumentOrigin) {
        let spent = try ForgeVocabulary.shipped.get().frontend.document(from: text)
        let document = try BinaryEncoding().value(from: spent.document)

        return (document, DocumentOrigin(identity: try Identity.of(document), origin: spent.origin))
    }
}
