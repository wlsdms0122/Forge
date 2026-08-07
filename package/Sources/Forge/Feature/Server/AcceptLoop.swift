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
    private let dispatch: DispatchService
    
    private var task: Task<Void, Never>?
    
    // MARK: - Initializer
    init(server: UnixSocketServer, dispatch: DispatchService) {
        self.server = server
        self.dispatch = dispatch
    }
    
    // MARK: - Public
    func start() async throws {
        let stream = try await Self.startStream(server: server)
        
        task = Task { [dispatch] in
            for await connection in stream {
                let handler = ConnectionHandler(connection: connection, dispatch: dispatch)
                
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
