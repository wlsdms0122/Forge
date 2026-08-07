//
//  Session.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

package enum Session {
    // MARK: - Property
    package static let defaultName = "default"
    
    // MARK: - Initializer
    // MARK: - Public
    package static func socket(in home: URL) -> String {
        home.appendingPathComponent("forged.sock").path
    }
    
    package static func runtimeInfo(in home: URL) -> URL {
        home.appendingPathComponent("runtime.json")
    }
    
    package static func runtimeDirectory(in home: URL) -> URL {
        home.appendingPathComponent("runtime")
    }
    
    package static func canonicalSocket(
        session: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        let path = socket(in: try home(session: session, env: env))
        
        try checkSocketLength(path)
        
        return path
    }
    
    package static func clientSocket(
        session: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let socket = env["FORGE_SOCKET"], !socket.isEmpty { return expand(socket) }
        
        return try canonicalSocket(session: session, env: env)
    }
    
    package static func home(
        session: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let name = resolveName(session, env: env)
        
        try validate(name)
        
        return configRoot(env: env)
            .appendingPathComponent("forge", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
    
    package static func name(
        _ session: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        resolveName(session, env: env)
    }
    
    package static func checkSocketLength(_ path: String) throws {
        let limit = 104
        
        guard path.utf8.count < limit else {
            throw SessionError.socketPathTooLong(path: path, limit: limit)
        }
    }
    
    // MARK: - Private
    private static func resolveName(_ explicit: String?, env: [String: String]) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let fromEnv = env["FORGE_SESSION"], !fromEnv.isEmpty { return fromEnv }
        
        return defaultName
    }
    
    private static func configRoot(env: [String: String]) -> URL {
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: expand(xdg), isDirectory: true)
        }
        
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
    }
    
    private static func validate(_ name: String) throws {
        let ok = name.allSatisfy { character in
            character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_"
                || character == "."
        }
        
        guard ok, name != ".", name != ".." else { throw SessionError.invalidName(name) }
    }
    
    private static func expand(_ raw: String) -> String {
        (raw as NSString).expandingTildeInPath
    }
}
