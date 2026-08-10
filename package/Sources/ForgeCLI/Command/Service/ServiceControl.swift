//
//  ServiceControl.swift
//  ForgeCLI
//
//  Created by JSilver on 8/11/26.
//

import Foundation

func controlCall(
    global: GlobalOptions,
    method: String,
    params: [String: Any],
    context: String,
    json: Bool
) {
    let socketPath: String
    
    do {
        socketPath = try resolveSocket(global)
    } catch {
        die("\(error)", code: 4)
    }
    
    let token = resolveToken(global.token)
    
    switch callRPC(socketPath: socketPath, method: method, params: params, token: token) {
    case .err(let type, let message):
        dieRPC(context, type: type, message: message)
    
    case .ok(let dict):
        if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
    }
}
