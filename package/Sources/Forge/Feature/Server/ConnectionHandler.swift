//
//  ConnectionHandler.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor ConnectionHandler {
    // MARK: - Property
    private let connection: Connection
    private let dispatch: DispatchService
    
    private var inFlightTasks: [Int: Task<Void, Never>] = [:]
    private var nextTaskID: Int = 0
    
    // MARK: - Initializer
    init(connection: Connection, dispatch: DispatchService) {
        self.connection = connection
        self.dispatch = dispatch
    }
    
    // MARK: - Public
    func run() async {
        let sink = ConnectionSink(connection: connection)
        
        for await frame in await connection.frames() {
            let id = nextTaskID
            nextTaskID &+= 1
            
            let task = Task { [connection, dispatch, sink] in
                await Self.handleOne(
                    frame: frame,
                    connection: connection,
                    dispatch: dispatch,
                    sink: sink
                )
                
                self.inFlightTasks.removeValue(forKey: id)
            }
            
            inFlightTasks[id] = task
        }
        
        let tasks = Array(inFlightTasks.values)
        
        for task in tasks { task.cancel() }
        for task in tasks { _ = await task.value }
        
        inFlightTasks.removeAll()
    }
    
    // MARK: - Private
    private static func handleOne(
        frame: Data,
        connection: Connection,
        dispatch: DispatchService,
        sink: ConnectionSink
    ) async {
        let request: RPCRequest
        
        do {
            request = try RPCRequest.decode(frame)
        } catch {
            await Log.shared.append(
                "rpc.malformed",
                [
                    "line_preview": String(decoding: frame.prefix(200), as: UTF8.self),
                    "error": String(describing: error)
                ],
                level: .error,
                category: "runtime.rpc"
            )
            
            return
        }
        
        if let streamingHandler = dispatch.streamingHandler(for: request.method) {
            do {
                try await streamingHandler(request, sink)
            } catch is CancellationError {
            } catch {
                let response = RPCResponse(id: request.id, error: error)
                
                if let data = try? response.encode() { await connection.send(data) }
            }
            
            return
        }
        
        let response: RPCResponse
        
        do {
            let result = try await dispatch.dispatch(request)
            response = RPCResponse(id: request.id, result: result)
        } catch {
            response = RPCResponse(id: request.id, error: error)
        }
        
        if let data = try? response.encode() {
            await connection.send(data)
        }
    }
}
