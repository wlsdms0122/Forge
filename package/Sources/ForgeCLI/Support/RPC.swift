//
//  RPC.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Forge

enum RPC {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func requestLine(
        method: String,
        params: [String: Any],
        idPrefix: String = "fc"
    ) -> Data? {
        let request: [String: Any] = [
            "id": "\(idPrefix)-\(UUID().uuidString.prefix(8))",
            "method": method,
            "params": params
        ]
        
        return try? JSONSerialization.data(
            withJSONObject: request,
            options: [.withoutEscapingSlashes]
        )
    }
    
    static func parseFrame(_ frame: Data) -> RPCResult {
        guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
            return .err(type: "ClientError", message: "malformed daemon response")
        }
        
        if let error = object["error"] as? [String: Any] {
            return .err(
                type: (error["type"] as? String) ?? "RPCError",
                message: (error["message"] as? String) ?? "rpc error"
            )
        }
        
        return .ok((object["result"] as? [String: Any]) ?? [:])
    }
    
    static func call(socketPath: String, method: String, params: [String: Any]) -> RPCResult {
        guard let requestData = requestLine(method: method, params: params) else {
            return .err(type: "ClientError", message: "encode request failed")
        }
        
        guard let socket = StreamSocket(path: socketPath) else {
            return .err(type: "ClientError", message: "connect failed (socket=\(socketPath))")
        }
        
        defer { socket.close() }
        
        guard socket.writeLine(requestData) else {
            return .err(type: "ClientError", message: "write failed")
        }
        
        guard let frame = socket.readFrame() else {
            return .err(type: "ClientError", message: "connection closed before response")
        }
        
        return parseFrame(frame)
    }
    
    // MARK: - Private
}

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
