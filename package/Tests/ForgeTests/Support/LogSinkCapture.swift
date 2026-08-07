//
//  LogSinkCapture.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import Forge

/// Redirects the `Log.shared` sink to a temporary file and reads the records collected in between.
///
/// The global sink is not isolated — while installed, **logs emitted by other tests** flow
/// into the same file. The `.exclusive(.logSink)` lock only guards tests that *swap* the
/// sink, not tests that *emit* logs. So the read surface defaults to the filtering side
/// (`records(kind:)` / `records(workflowID:)`) rather than everything.
///
/// Checks that need not go through the sink at all (behavior of `Log` itself, like rotation
/// and thresholds) use a `Log()` instance instead of the global — contamination is
/// impossible there by construction.
struct LogSinkCapture {
    // MARK: - Property
    let url: URL

    private let directory: TemporaryDirectory

    // MARK: - Initializer
    // MARK: - Public
    /// Redirects the global sink to a temporary file, runs `body`, and restores it whether it exits by success or failure.
    static func capture<T>(
        _ name: String,
        performing body: (LogSinkCapture) async throws -> T
    ) async throws -> T {
        let capture = try LogSinkCapture(name)
        await Log.shared.setSink(capture.url)
        await Log.shared.setMaxBytes(0)

        do {
            let result = try await body(capture)
            await Log.shared.setSink(nil)

            return result
        } catch {
            await Log.shared.setSink(nil)
            throw error
        }
    }

    /// All records collected in the file. Logs from other tests may be mixed in.
    func records() -> [LogRecord] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()

        return raw.split(separator: "\n").compactMap { line in
            try? decoder.decode(LogRecord.self, from: Data(line.utf8))
        }
    }

    func records(kind: String) -> [LogRecord] {
        records().filter { record in record.kind == kind }
    }

    func records(workflowID: String) -> [LogRecord] {
        records().filter { record in record.workflowID == workflowID }
    }

    // MARK: - Private
    private init(_ name: String) throws {
        directory = TemporaryDirectory(name)
        url = try directory.file("forge.log.jsonl")
    }
}
