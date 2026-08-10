//
//  Client.swift
//  ForgeCLI
//
//  Created by JSilver on 8/11/26.
//

import Foundation
import Forge

func resolveToken(_ flag: String?) -> String {
    if let flag, !flag.isEmpty { return flag }
    
    if
        let fromEnv = ProcessInfo.processInfo.environment["FORGE_ACCESS_TOKEN"],
        !fromEnv.isEmpty
    {
        return fromEnv
    }
    
    die(
        "no token — pass --token or set FORGE_ACCESS_TOKEN"
            + " (issue one with `forge token issue <principal>`)",
        code: 4
    )
}

func callRPC(
    socketPath: String,
    method: String,
    params: [String: Any],
    token: String
) -> RPCResult {
    var params = params
    params["token"] = token
    
    return RPC.call(socketPath: socketPath, method: method, params: params)
}

func dieRPC(_ context: String, type: String, message: String) -> Never {
    die("\(context): \(message)", code: type == "TokenRejected" ? 6 : 5)
}

func resolveSocket(_ global: GlobalOptions) throws -> String {
    do {
        return try Session.clientSocket(session: global.session)
    } catch {
        die("\(error)", code: 4)
    }
}
