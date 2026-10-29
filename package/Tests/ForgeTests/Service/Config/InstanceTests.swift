//
//  InstanceTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("Instance Tests")
struct InstanceTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("The default instance lives under the config root")
    func defaultInstanceUnderConfigRoot() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg"]

        // Then
        #expect(try Instance.home(instance: nil, env: env).path == "/cfg/forge/default")
        #expect(try Instance.canonicalSocket(instance: nil, env: env) == "/cfg/forge/default/forged.sock")
    }
    
    @Test("A named instance replaces the default instance")
    func namedInstanceOverridesDefault() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg"]

        // Then
        #expect(try Instance.home(instance: "prod", env: env).path == "/cfg/forge/prod")
        #expect(Instance.name("prod", env: env) == "prod")
    }
    
    @Test("Instance name source precedence — the option beats the env var, the env var beats the default")
    func instanceNamePrecedence() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg", "FORGE_INSTANCE": "fromenv"]

        // Then
        #expect(Instance.name(nil, env: env) == "fromenv")
        #expect(Instance.name("flag", env: env) == "flag", "--instance beats FORGE_INSTANCE")
    }
    
    @Test("The socket path is derived from the instance home")
    func socketResolution() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/cfg", "FORGE_SOCKET": "/from/env.sock"]

        // Then
        #expect(try Instance.canonicalSocket(instance: "x", env: env) == "/cfg/forge/x/forged.sock")
        #expect(try Instance.clientSocket(instance: "x", env: env) == "/from/env.sock")
        #expect(try Instance.clientSocket(instance: "x", env: ["XDG_CONFIG_HOME": "/cfg"]) == "/cfg/forge/x/forged.sock")
    }
    
    @Test("An instance name unusable as a path is rejected")
    func invalidInstanceNameRejected() {
        // Given
        for bad in ["..", ".", "a/b", "x..y/../z"] {

        // Then
            #expect(throws: (any Error).self, "instance '\(bad)' must be rejected") { try Instance.home(instance: bad, env: [:]) }
        }
    }
    
    @Test("Exceeding the socket path length limit is rejected")
    func socketPathTooLongRejected() throws {
        // Given
        let env = ["XDG_CONFIG_HOME": "/" + String(repeating: "a", count: 200)]

        // Then
        let error = try #require(throws: (any Error).self) {
            try Instance.canonicalSocket(instance: "s", env: env)
        }
        
        guard case InstanceError.socketPathTooLong = error else {
            Issue.record("expected socketPathTooLong, got \(error)")
            
            return
        }
    }
    
    @Test("Without XDG, falls back to under the home directory")
    func configRootFallsBackToHomeWhenNoXDG() throws {
        // Given
        let home = try Instance.home(instance: "s", env: [:]).path

        // Then
        #expect(home.hasSuffix("/.config/forge/s"), "got \(home)")
    }
    
    // MARK: - Private
}
