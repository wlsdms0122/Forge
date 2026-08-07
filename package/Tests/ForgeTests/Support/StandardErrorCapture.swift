//
//  StandardErrorCapture.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

/// Temporarily redirects the process's standard error into a pipe and reads what was written in between.
///
/// The source emits failures directly to `FileHandle.standardError` (there is no injectable
/// surface), so seeing "did it surface / was it silent" leaves no option but swapping the
/// process-global fd.
///
/// Two traps:
/// - **Waiting for EOF hangs.** `readDataToEndOfFile()` only returns once every write end is
///   closed, but `STDERR_FILENO` is global, so if another test running in parallel (especially
///   a child process that inherited fd 2) is holding it, EOF never comes. Observed in
///   practice as the runner freezing entirely (`--filter JobStoreTests` waited forever;
///   serial execution took 0.06s). So read non-blocking and treat `EAGAIN` as the end
///   signal — there is no write end to wait for.
/// - **While the window is open, other tests' stderr flows in here too.** There is no way to
///   isolate it, so callers declare `.exclusive(.standardError)` to keep captures from
///   overlapping.
struct StandardErrorCapture {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func capture(performing body: () async throws -> Void) async throws -> String {
        let pipe = Pipe()
        let reading = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(reading, F_SETFL, fcntl(reading, F_GETFL) | O_NONBLOCK)
        let saved = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        do {
            try await body()
        } catch {
            restore(saved: saved)
            throw error
        }

        restore(saved: saved)
        let captured = drain(reading)
        pipe.fileHandleForWriting.closeFile()
        pipe.fileHandleForReading.closeFile()

        return captured
    }

    // MARK: - Private
    private static func restore(saved: Int32) {
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
    }

    private static func drain(_ descriptor: Int32) -> String {
        var captured = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)

        while true {
            let count = read(descriptor, &buffer, buffer.count)

            guard count > 0 else { break }

            captured.append(contentsOf: buffer[0..<count])
        }

        return String(decoding: captured, as: UTF8.self)
    }
}
