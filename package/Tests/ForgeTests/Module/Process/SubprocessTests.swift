//
//  SubprocessTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("Subprocess Tests")
struct SubprocessTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("child exit means completion — background grandchildren are not waited on")
    func completesAtChildExitDespiteBackgroundGrandchild() async throws {
        // Given
        let startedAt = Date()
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", "sleep 8 & echo done"],
            cwd: nil, envExtra: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        // Then
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("done"), "stdout: \(result.stdout)")
        #expect(elapsed < 4.0, "must complete at child exit — blocked \(elapsed)s by the grandchild's inherited pipe write-end")
    }
    
    @Test("when the child waits, the grandchild's output is captured too")
    func grandchildOutputCapturedWhenChildWaits() async throws {
        // Given
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", "{ sleep 0.3; echo late; } & wait"],
            cwd: nil, envExtra: nil)

        // Then
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("late"), "stdout: \(result.stdout)")
    }
    
    @Test("grandchild output produced after the child exits is dropped")
    func grandchildOutputAfterChildExitIsDropped() async throws {
        // Given
        let startedAt = Date()
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", "{ sleep 2; echo late; } & echo early"],
            cwd: nil, envExtra: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        // Then
        #expect(result.stdout.contains("early"), "stdout: \(result.stdout)")
        #expect(!result.stdout.contains("late"), "post-child grandchild output was captured — a sign the completion anchor regressed to pipe-EOF")
        #expect(elapsed < 1.5)
    }
    
    @Test("a relative executable path resolves against cwd")
    func relativeExecutableResolvesAgainstCwd() async throws {
        // Given
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forge-subproc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let script = temporaryDirectory.appendingPathComponent("hello.sh")
        try "#!/bin/sh\necho relative-ok\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        let result = try await Subprocess.run(
            executable: "./hello.sh", args: [], cwd: temporaryDirectory.path,
            envExtra: nil)

        // Then
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("relative-ok"), "stdout: \(result.stdout)")
    }
    
    @Test("Hangul arguments are passed NFC-normalized")
    func argvIsNFCForKoreanText() async throws {
        // Given
        let nfcSong = "\u{C1A1}"

        // Then
        #expect(nfcSong.utf8.count == 3, "the input itself is not NFC — escape sanity check")
        let result = try await Subprocess.run(
            executable: "/usr/bin/python3",
            args: ["-c",
                "import sys; print(','.join(format(b, '02x') for b in sys.argv[1].encode()))",
                nfcSong],
            cwd: nil, envExtra: nil)
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(output == "ec,86,a1", "expected NFC (ec 86 a1), got: \(output)")
    }
    
    @Test("a large non-ASCII argument passes without argument list too long")
    func largeNonASCIIArgSurvivesWithoutArgumentListTooLong() async throws {
        // Given
        let unit = "A non-ASCII text line — café naïve résumé content with spaces and a newline.\n"
        let big = String(repeating: unit, count: 6000)

        // Then
        #expect(big.utf8.count > 250_000)
        let echoed = try await Subprocess.run(
            executable: "/bin/echo", args: ["-n", big], cwd: nil, envExtra: nil)
        #expect(echoed.exitCode == 0, "stderr: \(echoed.stderr)")
        #expect(echoed.stdout == big, "a large non-ASCII argument must round-trip exactly (no word-splitting/inflation)")
    }
    
    @Test("stray non-UTF-8 bytes do not wipe the whole stream")
    func nonUTF8BytesDoNotWipeTheWholeStream() async throws {
        // Given
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", "printf '€€' | head -c 4"],
            cwd: nil, envExtra: nil)

        // Then
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("€"), "the valid prefix must be preserved: \(result.stdout.debugDescription)")
        #expect(result.stdout.contains("\u{FFFD}"), "broken bytes must surface as U+FFFD: \(result.stdout.debugDescription)")
        #expect(!result.stdout.isEmpty, "the whole stream must not silently vanish")
    }
    
    @Test("an absolute executable path is unaffected by cwd")
    func absoluteExecutableUnaffectedByCwd() async throws {
        // Given
        let result = try await Subprocess.run(
            executable: "/bin/echo", args: ["abs-ok"], cwd: "/tmp",
            envExtra: nil)

        // Then
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("abs-ok"), Comment(rawValue: result.stdout))
    }
    
    @Test("the line callback fires immediately per line, with arrival time")
    func onStdoutLineEmitsPerLineWithArrivalTime() async throws {
        // Given
        let script = "echo line1; sleep 0.2; echo line2; sleep 0.2; echo line3"
        let collector = OrderedCollector<(line: String, at: Date)>()
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", script],
            cwd: nil, envExtra: nil,
            onStdoutLine: { frame, at in
                let line = String(decoding: frame, as: UTF8.self)
                collector.append((line, at))
            }
        )
        try await Task.sleep(for: .milliseconds(50))
        let lines = collector.elements

        // Then
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(lines.map(\.line) == ["line1", "line2", "line3"])
        #expect(lines.count == 3)
        let gap1 = lines[1].at.timeIntervalSince(lines[0].at)
        let gap2 = lines[2].at.timeIntervalSince(lines[1].at)
        #expect(gap1 > 0.1, "line1→2 gap \(gap1)s is too short — line callbacks seem batch-flushed")
        #expect(gap2 > 0.1, "line2→3 gap \(gap2)s is too short — line callbacks seem batch-flushed")
    }
    
    @Test("a trailing fragment without a newline is flushed too")
    func onStdoutLineFlushesTrailingPartialLine() async throws {
        // Given
        let collector = OrderedCollector<String>()
        _ = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", "printf 'no-newline-tail'"],
            cwd: nil, envExtra: nil,
            onStdoutLine: { frame, _ in
                let line = String(decoding: frame, as: UTF8.self)
                collector.append(line)
            }
        )

        // When
        try await Task.sleep(for: .milliseconds(50))

        // Then
        #expect(collector.elements == ["no-newline-tail"])
    }
    
    @Test("the line callback sees every byte of stdout — the premise for deleting raw re-parsing")
    func lineCallbackSeesEveryByteOfStdout() async throws {
        // Given
        let collector = OrderedCollector<Data>()
        let script = "printf 'a\\n\\nbb\\nccc'"
        let result = try await Subprocess.run(
            executable: "/bin/sh", args: ["-c", script],
            cwd: nil, envExtra: nil,
            onStdoutLine: { frame, _ in collector.append(frame) }
        )
        try await Task.sleep(for: .milliseconds(50))
        let fed = collector.elements.reduce(Data()) { joined, frame in joined + frame }
        let stdoutWithoutNewlines = Data(result.stdoutData.filter { byte in byte != UInt8(ascii: "\n") })

        // Then
        #expect(fed == stdoutWithoutNewlines, "the line callback missed part of stdout — this breaks the premise for deleting raw re-parsing")
    }
    
    // MARK: - Private
}
