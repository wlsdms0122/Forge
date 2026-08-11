//
//  Client.swift
//  ForgeCLI
//
//  Created by JSilver on 8/11/26.
//

import Foundation
import Forge

// The daemon as a command sees it — a socket, the token to speak with, and the
// command path to name when something goes wrong. A client command is one RPC
// and then exit, so every failure on that path is terminal: `call` answers a
// result or does not return.
struct Client {
    // MARK: - Property
    // ServiceBridge holds the connection open itself and needs the raw seams.
    let socketPath: String
    let token: String
    
    private let context: String
    
    // MARK: - Initializer
    init(_ global: GlobalOptions, context: String) {
        self.init(global, context: context, token: Client.resolvedToken(from: global.token))
    }
    
    // `daemon.status` is the one method the daemon answers unauthenticated, so
    // its caller passes whatever token it happens to have instead of demanding
    // one up front.
    init(_ global: GlobalOptions, context: String, token: String) {
        do {
            self.socketPath = try Session.clientSocket(session: global.session)
        } catch {
            die("\(error)", code: 4)
        }
        
        self.token = token
        self.context = context
    }
    
    // MARK: - Public
    func call(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        switch send(method, params) {
        case .ok(let result):
            return result
        
        case .err(let type, let message):
            fail(type: type, message: message)
        }
    }
    
    // For the caller that reads the failure before giving up — `forge status`
    // turns a dead socket into a diagnosis rather than an error line.
    func send(_ method: String, _ params: [String: Any] = [:]) -> RPCResult {
        var params = params
        params["token"] = token
        
        return RPC.call(socketPath: socketPath, method: method, params: params)
    }
    
    func fail(type: String, message: String) -> Never {
        die("\(context): \(message)", code: type == "TokenRejected" ? 6 : 5)
    }
    
    // MARK: - Private
    private static func resolvedToken(from flag: String?) -> String {
        if let flag, !flag.isEmpty { return flag }
        
        if
            let fromEnvironment = ProcessInfo.processInfo.environment["FORGE_ACCESS_TOKEN"],
            !fromEnvironment.isEmpty
        {
            return fromEnvironment
        }
        
        die(
            "no token — pass --token or set FORGE_ACCESS_TOKEN"
                + " (issue one with `forge token issue <principal>`)",
            code: 4
        )
    }
}
