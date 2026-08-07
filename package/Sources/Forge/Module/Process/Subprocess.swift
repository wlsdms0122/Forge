//
//  Subprocess.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum Subprocess {
    typealias StdoutLineHandler = @Sendable (_ line: Data, _ at: Date) -> Void
    
    // MARK: - Property
    static let terminationGraceSeconds: Double = 5
    
    // MARK: - Initializer
    // MARK: - Public
    static func run(
        executable: String,
        args: [String],
        cwd: String?,
        envExtra: [String: String]?,
        stdin: String? = nil,
        onStdoutLine: StdoutLineHandler? = nil
    ) async throws -> SubprocessResult {
        let process = Process()
        let outSplitter: LineSplitter? = onStdoutLine.map { handler in
            LineSplitter(handler: handler)
        }
        let outReader = try PipeReader { data in outSplitter?.feed(data, at: Date()) }
        let errReader = try PipeReader()
        process.standardOutput = outReader.writingHandle
        process.standardError = errReader.writingHandle
        
        let inPipe: Pipe? = (stdin != nil) ? Pipe() : nil
        
        if let inPipe { process.standardInput = inPipe }
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONPATH")
        
        if let envExtra {
            for (key, value) in envExtra { environment[key] = value }
        }
        
        process.environment = environment
        
        let needsShellRoute = !executable.allSatisfy(\.isASCII)
            || args.contains(where: { argument in !argument.allSatisfy(\.isASCII) })
        
        if needsShellRoute {
            var prelude: [String] = []
            var words: [String] = []
            
            for (index, raw) in ([executable] + args).enumerated() {
                let (statement, word) = Self.shellEscapeForExec(raw, varName: "w\(index)")
                
                if let statement { prelude.append(statement) }
                
                words.append(word)
            }
            
            let script = (prelude + ["exec " + words.joined(separator: " ")])
                .joined(separator: "; ")
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
        } else if executable.contains("/") {
            if !executable.hasPrefix("/"), let cwd {
                process.executableURL = URL(fileURLWithPath: cwd, isDirectory: true)
                    .appendingPathComponent(executable)
                    .standardizedFileURL
            } else {
                process.executableURL = URL(fileURLWithPath: executable)
            }
            
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args
        }
        
        let spawnGuard = SpawnGuard()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<SubprocessResult, any Error>) in
                let state = ProcessRunState()
                
                process.terminationHandler = { process in
                    let stdoutData = outReader.finish()
                    outSplitter?.flushRemainder(at: Date())
                    
                    let stderrData = errReader.finish()

                    state.complete(
                        .success(
                            SubprocessResult(
                                exitCode: process.terminationStatus,
                                stdoutData: stdoutData,
                                stderr: String(decoding: stderrData, as: UTF8.self)
                            )
                        ),
                        to: continuation
                    )
                }
                
                if Task.isCancelled {
                    outReader.finish()
                    errReader.finish()
                    state.complete(.failure(CancellationError()), to: continuation)
                    
                    return
                }
                
                do {
                    try process.run()
                } catch {
                    outReader.finish()
                    errReader.finish()
                    state.complete(.failure(error), to: continuation)
                    
                    return
                }
                
                // The parent's copy can only close after the child inherited it — closing is what brings EOF.
                outReader.closeWriteEnd()
                errReader.closeWriteEnd()
                
                if spawnGuard.markStarted() {
                    Self.escalateTerminate(process)
                }
                
                if let inPipe, let bytes = stdin?.data(using: .utf8) {
                    Thread.detachNewThread {
                        let handle = inPipe.fileHandleForWriting
                        
                        do {
                            try handle.write(contentsOf: bytes)
                        } catch {
                            // A child that exits without reading stdin gives EPIPE here. That is a
                            // normal race, and the child's own exit code and stderr already tell
                            // the story — there is nothing this thread could add.
                        }
                        
                        try? handle.close()
                    }
                }
            }
        } onCancel: {
            if spawnGuard.markCancelled() {
                Self.escalateTerminate(process)
            }
        }
    }
    
    // MARK: - Private
}

extension Subprocess {
    static func escalateTerminate(_ process: Process) {
        guard process.isRunning else { return }
        
        let pid = process.processIdentifier
        Self.signalTree(pid: pid, sig: SIGTERM)
        
        Task {
            try? await Task.sleep(for: .seconds(terminationGraceSeconds))
            
            if process.isRunning { Self.signalTree(pid: pid, sig: SIGKILL) }
        }
    }
    
    static func signalTree(pid: pid_t, sig: Int32) {
        guard pid > 1 else { return }
        
        let childPgid = getpgid(pid)
        
        if childPgid > 1 && childPgid != getpgid(0) {
            kill(-childPgid, sig)
        } else {
            kill(pid, sig)
        }
    }
    
    static func shellEscapeForExec(
        _ text: String,
        varName: String
    ) -> (prelude: String?, word: String) {
        if text.isEmpty { return (nil, "''") }
        
        let safe: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-=,:@+"
        )
        
        if text.allSatisfy({ character in safe.contains(character) }) { return (nil, text) }
        
        if text.allSatisfy({ character in character.isASCII }) && !text.contains("'") {
            return (nil, "'\(text)'")
        }
        
        let encoded = Data(text.utf8).base64EncodedString()
        let statement = "\(varName)=\"$(printf %s '\(encoded)' | base64 -d; printf X)\""
        let word = "\"${\(varName)%X}\""
        
        return (statement, word)
    }
}

private final class LineSplitter: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private let handler: Subprocess.StdoutLineHandler
    private var carry = Data()
    
    // MARK: - Initializer
    init(handler: @escaping Subprocess.StdoutLineHandler) {
        self.handler = handler
    }
    
    // MARK: - Public
    func feed(_ data: Data, at now: Date) {
        lock.lock()
        carry.append(data)
        
        var lines: [Data] = []
        
        while let newlineIndex = carry.firstIndex(of: 0x0A) {
            let lineData = carry.subdata(in: carry.startIndex..<newlineIndex)
            carry.removeSubrange(carry.startIndex...newlineIndex)
            
            if lineData.last == 0x0D {
                lines.append(
                    lineData.subdata(
                        in: lineData.startIndex..<lineData.index(before: lineData.endIndex)
                    )
                )
            } else {
                lines.append(lineData)
            }
        }
        
        lock.unlock()
        
        for line in lines { handler(line, now) }
    }
    
    func flushRemainder(at now: Date) {
        lock.lock()
        
        let remaining = carry
        carry = Data()
        
        lock.unlock()
        
        guard !remaining.isEmpty else { return }
        
        handler(remaining, now)
    }
    
    // MARK: - Private
}

private final class ProcessRunState: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var resolved = false
    
    // MARK: - Initializer
    // MARK: - Public
    func complete(
        _ result: Result<SubprocessResult, any Error>,
        to continuation: CheckedContinuation<SubprocessResult, any Error>
    ) {
        lock.lock()
        
        defer { lock.unlock() }
        
        guard !resolved else { return }
        
        resolved = true
        continuation.resume(with: result)
    }
    
    // MARK: - Private
}
