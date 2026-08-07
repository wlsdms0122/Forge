//
//  ServiceBridge.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class ServiceBridge: @unchecked Sendable {
    // MARK: - Property
    private let service: String
    private let socketPath: String
    private let schema: [String: Any]?
    private let token: String
    private let lock = NSLock()
    private var sock: StreamSocket?
    private var stopped = false
    
    // MARK: - Initializer
    init(service: String, socketPath: String, schema: [String: Any]?, token: String) {
        self.service = service
        self.socketPath = socketPath
        self.schema = schema
        self.token = token
    }
    
    // MARK: - Public
    func run() {
        let reader = Thread { [weak self] in self?.readerLoop() }
        reader.stackSize = 1 << 20
        reader.start()
        
        stdinLoop()
    }
    
    // MARK: - Private
    private func readerLoop() {
        guard let socket = connectRegisterOnce() else {
            emitStderr("forge service: connect/register failed — exiting")
            exit(1)
        }
        
        setSocket(socket)
        
        while !isStopped() {
            guard let frame = socket.readFrame() else { break }
            
            if frame.isEmpty { continue }
            
            if let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                (object["kind"] as? String) == "session.message" {
                emitStdoutLine(String(decoding: frame, as: UTF8.self))
            }
        }
        
        setSocket(nil)
        socket.close()
        
        if isStopped() { return }
        
        emitStderr("forge service: connection lost — exiting")
        exit(1)
    }
    
    private func connectRegisterOnce() -> StreamSocket? {
        guard let socket = StreamSocket(path: socketPath) else { return nil }
        
        var params: [String: Any] = ["service": service, "token": token]
        
        if let schema { params["schema"] = schema }
        
        guard let data = RPC.requestLine(
            method: "session.handler.register",
            params: params,
            idPrefix: "reg"
        ), socket.writeLine(data) else {
            socket.close()
            
            return nil
        }
        
        guard let ackFrame = socket.readFrame() else {
            socket.close()
            
            return nil
        }
        
        if case .err(let type, let message) = RPC.parseFrame(ackFrame) {
            emitStderr("forge service: register failed: \(type): \(message)")
            socket.close()
            
            return nil
        }
        
        emitStderr("forge service: registered service=\(service)")
        
        return socket
    }
    
    private func stdinLoop() {
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let messageID = object["message_id"] as? String
            else {
                emitStderr("forge service: bad ack line dropped")
                
                continue
            }
            
            var params: [String: Any] = [
                "service": service,
                "message_id": messageID,
                "token": token,
            ]
            
            if let result = object["result"] { params["result"] = result }
            if let error = object["error"] { params["error"] = error }
            
            guard let requestData = RPC.requestLine(
                method: "session.handler.ack",
                params: params,
                idPrefix: "ack"
            ) else {
                continue
            }
            
            lock.lock()
            
            let socket = sock
            
            lock.unlock()
            
            if socket == nil || !(socket!.writeLine(requestData)) {
                emitStderr("forge service: ack drop — connection closed")
            }
        }
        
        stop()
    }
    
    private func isStopped() -> Bool {
        lock.lock()
        
        defer { lock.unlock() }
        
        return stopped
    }
    
    private func stop() {
        lock.lock()
        
        stopped = true
        
        let socket = sock
        sock = nil
        
        lock.unlock()
        socket?.close()
    }
    
    private func setSocket(_ socket: StreamSocket?) {
        lock.lock()
        sock = socket
        lock.unlock()
    }
}
