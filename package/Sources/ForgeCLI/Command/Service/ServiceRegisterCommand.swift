//
//  ServiceRegisterCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceRegisterCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "register",
        abstract: "Register the current process as a service handler (dumb pipe co-process).",
        discussion: """
            Long-lived co-process — the stdio↔socket adapter a managed
            service runs so it never touches the socket itself. It connects
            and registers exactly once; resilience is not its job. The
            daemon's supervisor owns every restart decision: any failure
            here (connect refused, register rejected, connection lost) is a
            fail-fast exit(1), which the parent service should treat as
            fatal — exit, and let the supervisor respawn the whole service.
            The bearer token comes from FORGE_ACCESS_TOKEN / --token (a
            supervisor-minted, spawn-scoped token).

            STDOUT  one JSON line per incoming `session.message` frame
                    (kind / message_id / payload / envelope). Other RPC
                    envelopes (register ack, ack responses) are not emitted.

            STDIN   one JSON line per ack:
                        { "message_id": "...", "result": { ... } }
                        { "message_id": "...", "error": { ... } }
                    forge wraps it into a `session.handler.ack` RPC on the
                    same connection.

            Exits 0 on stdin EOF (parent-initiated shutdown), 1 on any
            connection or registration failure.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service name to register (e.g. `slack`).")
    var name: String
    
    @Option(help: "Handler schema as a JSON object (advertised via `forge service list`).")
    var schema: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        let schemaObject = schema.map { value in parseJSONObjectArg(value, flag: "--schema") }
        let bridge = ServiceBridge(
            service: name,
            socketPath: socketPath,
            schema: schemaObject,
            token: token
        )
        
        bridge.run()
    }
    
    // MARK: - Private
}
