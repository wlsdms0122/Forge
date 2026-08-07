//
//  SessionTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("Session Tests")
struct SessionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("The default session lives under the config root")
    func defaultSessionUnderConfigRoot() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg"]

        // Then
        #expect(try Session.home(session: nil, env: env).path == "/cfg/forge/default")
        #expect(try Session.canonicalSocket(session: nil, env: env) == "/cfg/forge/default/forged.sock")
    }
    
    @Test("A named session replaces the default session")
    func namedSessionOverridesDefault() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg"]

        // Then
        #expect(try Session.home(session: "prod", env: env).path == "/cfg/forge/prod")
        #expect(Session.name("prod", env: env) == "prod")
    }
    
    @Test("Session name source precedence — the option beats the env var, the env var beats the default")
    func sessionNamePrecedence() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg", "FORGE_SESSION": "fromenv"]

        // Then
        #expect(Session.name(nil, env: env) == "fromenv")
        #expect(Session.name("flag", env: env) == "flag", "--session beats FORGE_SESSION")
    }
    
    @Test("The socket path is derived from the session home")
    func socketResolution() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg", "FORGE_SOCKET": "/from/env.sock"]

        // Then
        #expect(try Session.canonicalSocket(session: "x", env: env) == "/cfg/forge/x/forged.sock")
        #expect(try Session.clientSocket(session: "x", env: env) == "/from/env.sock")
        #expect(try Session.clientSocket(session: "x", env: ["XDG_CONFIG_HOME": "/cfg"]) == "/cfg/forge/x/forged.sock")
    }
    
    @Test("A session name unusable as a path is rejected")
    func invalidSessionNameRejected() {
        // Given
        for bad in ["..", ".", "a/b", "x..y/../z"] {

        // Then
            #expect(throws: (any Error).self, "session '\(bad)' must be rejected") { try Session.home(session: bad, env: [:]) }
        }
    }
    
    @Test("Exceeding the socket path length limit is rejected")
    func socketPathTooLongRejected() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/" + String(repeating: "a", count: 200)]

        // Then
        let error = try #require(throws: (any Error).self) {
            try Session.canonicalSocket(session: "s", env: env)
        }
        
        guard case SessionError.socketPathTooLong = error else {
            Issue.record("expected socketPathTooLong, got \(error)")
            
            return
        }
    }
    
    @Test("Without XDG, falls back to under the home directory")
    func configRootFallsBackToHomeWhenNoXDG() throws {
        // Given
        let home = try Session.home(session: "s", env: [:]).path

        // Then
        #expect(home.hasSuffix("/.config/forge/s"), "got \(home)")
    }
    
    // MARK: - Private
}
