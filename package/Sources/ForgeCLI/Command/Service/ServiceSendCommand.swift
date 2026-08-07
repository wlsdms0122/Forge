//
//  ServiceSendCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceSendCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a JSON payload to a service handler.",
        discussion: """
            Hands a payload to a registered external service handler
            (e.g. `slack`). The payload schema is service-specific — see
            `forge service describe <name>`.

            IDENTITY
                The bearer token (FORGE_ACCESS_TOKEN or --token) carries the
                caller's identity. principal / workflow_id / origin /
                correlator are derived server-side from the token — not
                spoofable.

            BLOCKING vs --async
                `send` blocks until the handler acks and returns its result.
                Pass --async to return as soon as the work is dispatched
                ({ message_id, status: "dispatched" }) without waiting.
                Whether to wait is the caller's business — a `wait` key in
                the payload is rejected; use --async.

            EXAMPLE
                forge service send slack \\
                    --payload '{"kind":"slack.channel","target":"C0XYZ","text":"hi"}'
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service handler name (e.g. `slack`).")
    var name: String
    
    @Option(help: "JSON object payload. Service-specific schema.")
    var payload: String
    
    @Flag(help: "Emit the full RPC response as JSON (default: readable result).")
    var json: Bool = false
    
    @Flag(
        name: .customLong("async"),
        help: "Return as soon as the work is dispatched, without blocking for the result."
    )
    var isAsync: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        
        guard let payloadData = payload.data(using: .utf8),
            let payloadAny = try? JSONSerialization.jsonObject(with: payloadData),
            let payloadObject = payloadAny as? [String: Any]
        else {
            die("service send: --payload must be a JSON object", code: 4)
        }
        
        if payloadObject["wait"] != nil {
            die("service send: control whether to wait with the --async flag, not a payload field (omit --async to block until completion)", code: 4)
        }
        
        let params: [String: Any] = [
            "service": name,
            "payload": payloadObject,
            "async": isAsync,
        ]
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "session.send",
            params: params,
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
            
            ForgeCommand.exit()
        
        case .err(let type, let message):
            dieRPC("service send", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
