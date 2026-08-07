//
//  BootstrapSinkTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("BootstrapSink Tests")
struct BootstrapSinkTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a valid bootstrap fd takes precedence")
    func validFdTakesPrecedence() {
        #expect(Server.bootstrapSink(fdEnv: "3", isTTY: false) == .fd(3))
        #expect(Server.bootstrapSink(fdEnv: "3", isTTY: true) == .fd(3))
        #expect(Server.bootstrapSink(fdEnv: "7", isTTY: false) == .fd(7))
    }
    
    @Test("without an fd, interactive sessions go to stdout")
    func noFdInteractiveGoesStdout() {
        #expect(Server.bootstrapSink(fdEnv: nil, isTTY: true) == .stdout)
    }
    
    @Test("with neither fd nor TTY, nothing is emitted anywhere")
    func noFdNonTTYWithheld() {
        #expect(Server.bootstrapSink(fdEnv: nil, isTTY: false) == .withheld)
    }
    
    @Test("an invalid fd falls back without leaking to stdout")
    func invalidFdFallsBackNotStdoutLeak() {
        #expect(Server.bootstrapSink(fdEnv: "abc", isTTY: false) == .withheld)
        #expect(Server.bootstrapSink(fdEnv: "-1", isTTY: false) == .withheld)
        #expect(Server.bootstrapSink(fdEnv: "", isTTY: false) == .withheld)
        #expect(Server.bootstrapSink(fdEnv: "abc", isTTY: true) == .stdout)
    }
    
    // MARK: - Private
}
