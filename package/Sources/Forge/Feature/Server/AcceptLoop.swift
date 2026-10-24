//
//  AcceptLoop.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor AcceptLoop {
    // MARK: - Property
    private let server: UnixSocketServer
    private let router: RPCRouter
    
    private var task: Task<Void, Never>?
    
    // MARK: - Initializer
    init(server: UnixSocketServer, router: RPCRouter) {
        self.server = server
        self.router = router
    }
    
    // MARK: - Public
    func start() async throws {
        let stream = try await Self.startStream(server: server)
        
        task = Task { [router] in
            for await connection in stream {
                let handler = ConnectionHandler(connection: connection, router: router)
                
                Task { await handler.run() }
            }
        }
    }
    
    func stop() async {
        await server.stop()
        
        task?.cancel()
        task = nil
    }
    
    // MARK: - Private
    private static func startStream(
        server: UnixSocketServer
    ) async throws -> AsyncStream<Connection> {
        try await server.start()
    }
}
