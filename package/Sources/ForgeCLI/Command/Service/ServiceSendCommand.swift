//
//  ServiceSendCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct ServiceSendCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a JSON payload to a registered service.",
        discussion: """
            Hands a payload to a registered service
            (e.g. `slack`). The payload schema is service-specific — see
            `forge service describe <name>`.

            IDENTITY
                The bearer token (FORGE_ACCESS_TOKEN or --token) carries the
                caller's identity. principal / run_id / origin /
                correlator are derived server-side from the token — not
                spoofable.

            BLOCKING vs --async
                `send` blocks until the service acks and returns its result.
                Pass --async to return as soon as the work is dispatched
                ({ message_id, status: "dispatched" }) without waiting.

            EXAMPLE
                forge service send slack \\
                    --payload '{"kind":"slack.channel","target":"C0XYZ","text":"hi"}'
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service name (e.g. `slack`).")
    var name: String
    
    @Option(help: "JSON object payload. Service-specific schema.")
    var payload: String
    
    @Flag(help: "Emit the result as JSON (default: readable result).")
    var json: Bool = false
    
    @Flag(
        name: .customLong("async"),
        help: "Return as soon as the work is dispatched, without blocking for the result."
    )
    var isAsync: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "service send")
        
        let params: [String: JSONValue] = [
            "service": .string(name),
            "payload": JSONValue(objectArgument: payload, flag: "--payload"),
            "async": .bool(isAsync)
        ]
        
        client.call("service.send", params).printResult(json: json)
        
        Self.exit()
    }
    
    // MARK: - Private
}
